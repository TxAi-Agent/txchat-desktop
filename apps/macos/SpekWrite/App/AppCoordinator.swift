import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    private enum SessionDestination {
        case insertion
        case voiceTest
    }

    typealias AuthenticationInvalidationHandler = @MainActor @Sendable (
        DictationAvailability
    ) async -> Void

    @Published private(set) var state: DictationState
    @Published private(set) var mode: DictationMode
    @Published private(set) var voiceTestResultText: String?
    @Published private(set) var audioLevel: Double?
    @Published private(set) var completionTextOptimizationFallbackReason:
        RealtimeFallbackReason?

    var completionUsedVerbatimFallback: Bool {
        completionTextOptimizationFallbackReason != nil
    }

    private let dependencies: AppDependencies
    private let authenticationInvalidationHandler:
        AuthenticationInvalidationHandler
    private let diagnosticRecorder: any DiagnosticIncidentRecording
    private var sessionIdentifier: UUID?
    private var client: (any DictationStreamingServing)?
    private var capture: (any DictationAudioCapturing)?
    private var target: DictationTarget?
    private var pumpTask: Task<Void, Error>?
    private var maximumDurationTask: Task<Void, Never>?
    private var cancellationTask: Task<Bool, Never>?
    private var cancellationTaskGeneration = 0
    private var sessionDestination: SessionDestination = .insertion
    private var audioLevelSmoother = TxChatAudioLevelSmoother()

    init(
        dependencies: AppDependencies,
        initialState: DictationState = .idle,
        mode: DictationMode = .smart,
        diagnosticRecorder: any DiagnosticIncidentRecording =
            DisabledDiagnosticIncidentRecorder.shared,
        authenticationInvalidationHandler:
            @escaping AuthenticationInvalidationHandler = { _ in }
    ) {
        self.dependencies = dependencies
        self.authenticationInvalidationHandler =
            authenticationInvalidationHandler
        self.diagnosticRecorder = diagnosticRecorder
        state = initialState
        self.mode = mode
        voiceTestResultText = nil
        audioLevel = nil
        completionTextOptimizationFallbackReason = nil
    }

    func toggle() async {
        switch state {
        case .idle, .completed, .failed:
            await start()
        case .listening:
            await stop()
        case .unavailable, .starting, .finalizing, .organizing, .inserting,
             .resultFallback:
            break
        }
    }

    func toggleVoiceTest() async {
        switch state {
        case .idle, .completed, .failed:
            voiceTestResultText = nil
            await start(destination: .voiceTest)
        case .listening where sessionDestination == .voiceTest:
            await stop()
        case .unavailable, .starting, .listening, .finalizing, .organizing,
             .inserting, .resultFallback:
            break
        }
    }

    func clearVoiceTestResult() {
        voiceTestResultText = nil
    }

    func start() async {
        await start(destination: .insertion)
    }

    private func start(destination: SessionDestination) async {
        guard cancellationTask == nil else {
            return
        }
        completionTextOptimizationFallbackReason = nil
        audioLevel = nil
        audioLevelSmoother = TxChatAudioLevelSmoother()
        sessionDestination = destination
        await send(.userStarted(mode: mode))
    }

    func stop() async {
        await send(.userStopped)
    }

    @discardableResult
    func cancel() async -> Bool {
        if let cancellationTask {
            return await cancellationTask.value
        }
        cancellationTaskGeneration &+= 1
        let generation = cancellationTaskGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await send(.userCancelled)
        }
        cancellationTask = task
        let accepted = await task.value
        if cancellationTaskGeneration == generation {
            cancellationTask = nil
        }
        return accepted
    }

    func dismissResult() async {
        await send(.resultDismissed)
    }

    @discardableResult
    func retryInsertion() async -> Bool {
        guard case .resultFallback = state else {
            return false
        }
        if let target {
            dependencies.targetHandler.discard(target)
        }
        target = nil
        guard case .captured(let retryTarget) =
            dependencies.targetHandler.capture() else {
            return false
        }
        target = retryTarget
        await send(.insertionRetried)
        return state == .completed
    }

    func logout() async {
        await send(.loggedOut)
    }

    func terminate() async {
        await send(.applicationTerminated)
    }

    func setMode(_ mode: DictationMode) {
        guard !hasActiveSession else {
            return
        }
        self.mode = mode
    }

    private var hasActiveSession: Bool {
        switch state {
        case .starting, .listening, .finalizing, .organizing, .inserting:
            return true
        case .unavailable, .idle, .resultFallback, .completed, .failed:
            return false
        }
    }

    @discardableResult
    private func send(_ event: DictationEvent) async -> Bool {
        let transition = DictationStateReducer.reduce(
            state: state,
            event: event
        )
        guard transition.accepted else {
            return false
        }
        state = transition.state
        for effect in transition.effects {
            await execute(effect)
        }
        return true
    }

    private func execute(_ effect: DictationEffect) async {
        switch effect {
        case .captureTarget:
            await captureTarget()
        case .startSession:
            await startSession()
        case .stopAndFinalize:
            await stopAndFinalize()
        case .prepareFinal(let text):
            await prepareFinal(text)
        case .insert(let text):
            await insert(text)
        case .cancelSession:
            await cancelActiveSession()
        case .releaseSession:
            releaseCompletedSession()
        }
    }

    private func captureTarget() async {
        guard sessionIdentifier == nil else {
            return
        }
        sessionIdentifier = UUID()
        if sessionDestination == .voiceTest {
            await send(.targetCaptured)
            return
        }
        switch dependencies.targetHandler.capture() {
        case .captured(let capturedTarget):
            target = capturedTarget
            await send(.targetCaptured)
        case .unavailable:
            target = nil
            await send(.targetUnavailable)
        case .blocked:
            target = nil
            await send(.targetBlocked)
        }
    }

    private func startSession() async {
        guard
            let identifier = sessionIdentifier,
            capture == nil,
            client == nil
        else {
            return
        }

        let newCapture = dependencies.captureFactory()
        capture = newCapture

        do {
            try await newCapture.preflight()
        } catch {
            await handle(
                error,
                sessionIdentifier: identifier,
                stage: .capturePreflight,
                fallback: .captureUnavailable
            )
            return
        }
        guard sessionIdentifier == identifier else {
            return
        }

        let streamingSession: DictationStreamingSession
        do {
            streamingSession = try await dependencies.streamingSessionFactory()
        } catch {
            await handle(
                error,
                sessionIdentifier: identifier,
                stage: .sessionRestore,
                fallback: .serviceUnavailable
            )
            return
        }
        guard sessionIdentifier == identifier else {
            return
        }
        let newClient = streamingSession.client
        client = newClient

        let frames: AsyncThrowingStream<Data, Error>
        do {
            frames = try await newCapture.start(
                onAudioLevel: { [weak self] level in
                    await self?.receiveAudioLevel(
                        level,
                        sessionIdentifier: identifier
                    )
                }
            )
        } catch {
            await handle(
                error,
                sessionIdentifier: identifier,
                stage: .captureStart,
                fallback: .captureUnavailable
            )
            return
        }
        guard sessionIdentifier == identifier else {
            return
        }

        do {
            try await newClient.start(
                accessToken: streamingSession.accessToken,
                mode: RealtimeSessionMode(mode),
                onPartial: { [weak self] text in
                    await self?.receivePartial(
                        text,
                        sessionIdentifier: identifier
                    )
                },
                onOrganizing: { [weak self] in
                    await self?.receiveOrganizing(
                        sessionIdentifier: identifier
                    )
                }
            )
        } catch {
            await handle(
                error,
                sessionIdentifier: identifier,
                stage: .streamStart,
                fallback: .serviceUnavailable
            )
            return
        }
        guard sessionIdentifier == identifier else {
            return
        }

        pumpTask = makePumpTask(
            frames: frames,
            client: newClient,
            sessionIdentifier: identifier
        )
        await send(.sessionStarted)
        guard sessionIdentifier == identifier else {
            return
        }
        armMaximumDuration(for: identifier)
    }

    private func makePumpTask(
        frames: AsyncThrowingStream<Data, Error>,
        client: any DictationStreamingServing,
        sessionIdentifier identifier: UUID
    ) -> Task<Void, Error> {
        Task { [weak self] in
            do {
                for try await frame in frames {
                    try CoreAudioFramePolicy.validate(frame)
                    try await client.send(audio: frame)
                }
            } catch {
                await self?.handle(
                    error,
                    sessionIdentifier: identifier,
                    stage: .audioPump,
                    fallback: .captureUnavailable
                )
                throw error
            }
        }
    }

    private func armMaximumDuration(for identifier: UUID) {
        maximumDurationTask?.cancel()
        let clock = dependencies.clock
        let duration = dependencies.maximumDuration
        maximumDurationTask = Task { [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.maximumDurationReached(
                sessionIdentifier: identifier
            )
        }
    }

    private func receivePartial(
        _ text: String,
        sessionIdentifier identifier: UUID
    ) async {
        guard sessionIdentifier == identifier else {
            return
        }
        await send(.partialReceived(text))
    }

    private func receiveAudioLevel(
        _ level: Double,
        sessionIdentifier identifier: UUID
    ) async {
        guard sessionIdentifier == identifier,
              case .listening = state else {
            return
        }
        audioLevel = audioLevelSmoother.update(with: level)
    }

    private func receiveOrganizing(
        sessionIdentifier identifier: UUID
    ) async {
        guard sessionIdentifier == identifier else {
            return
        }
        await send(.organizingStarted)
    }

    private func maximumDurationReached(
        sessionIdentifier identifier: UUID
    ) async {
        guard sessionIdentifier == identifier else {
            return
        }
        await send(.maximumDurationReached)
    }

    private func stopAndFinalize() async {
        guard
            let identifier = sessionIdentifier,
            let capture,
            let client
        else {
            await send(.serviceFailed(.serviceUnavailable))
            return
        }

        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        await capture.stop()
        guard sessionIdentifier == identifier else {
            return
        }

        do {
            try await pumpTask?.value
        } catch {
            if sessionIdentifier == identifier {
                await handle(
                    error,
                    sessionIdentifier: identifier,
                    stage: .audioPump,
                    fallback: .captureUnavailable
                )
            }
            return
        }
        guard sessionIdentifier == identifier else {
            return
        }

        do {
            let result = try await client.finishResult()
            guard sessionIdentifier == identifier else {
                return
            }
            guard Self.isNonempty(result.text) else {
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: .streamFinish,
                    code: .protocolViolation
                )
                await send(.serviceFailed(.protocolViolation))
                return
            }
            guard
                (result.mode == .verbatimFallback) ==
                    (result.fallbackReason != nil)
            else {
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: .streamFinish,
                    code: .protocolViolation
                )
                await send(.serviceFailed(.protocolViolation))
                return
            }
            completionTextOptimizationFallbackReason =
                result.fallbackReason
            await send(.finalReceived(result.text))
        } catch {
            await handle(
                error,
                sessionIdentifier: identifier,
                stage: .streamFinish,
                fallback: .serviceUnavailable
            )
        }
    }

    private func prepareFinal(_ rawText: String) async {
        guard let identifier = sessionIdentifier else {
            return
        }
        do {
            let prepared = try await dependencies.finalPreparer.prepare(
                rawText,
                mode: mode
            )
            guard sessionIdentifier == identifier else {
                return
            }
            if Self.isNonempty(prepared) {
                await send(.finalPrepared(prepared))
            } else {
                await send(.finalPreparationFailed(rawText: rawText))
            }
        } catch {
            guard sessionIdentifier == identifier else {
                return
            }
            await send(.finalPreparationFailed(rawText: rawText))
        }
    }

    private func insert(_ text: String) async {
        if sessionDestination == .voiceTest {
            voiceTestResultText = text
            await send(.insertionSucceeded)
            return
        }
        guard let target else {
            await send(.insertionFailed)
            return
        }
        let inserted = dependencies.targetHandler.insert(text, into: target)
        await send(inserted ? .insertionSucceeded : .insertionFailed)
    }

    private func handle(
        _ error: Error,
        sessionIdentifier identifier: UUID,
        stage: DiagnosticStage,
        fallback: DictationFailure
    ) async {
        guard sessionIdentifier == identifier else {
            return
        }
        if let dependencyError = error as? AppDependencyError,
           dependencyError == .invalidAccessToken {
            await invalidateAuthentication(.authenticationRequired)
            return
        }
        if error as? AuthenticationServiceError == .protocolViolation {
            recordDiagnostic(
                category: .authentication,
                taskID: identifier,
                stage: stage,
                code: .protocolViolation
            )
            await send(.serviceFailed(.protocolViolation))
            return
        }
        if let diagnosticError = error as? CustomAIDiagnosticError {
            recordDiagnostic(
                category: diagnosticError.category,
                taskID: identifier,
                stage: diagnosticError.stage,
                code: diagnosticError.code
            )
            await send(.serviceFailed(fallback))
            return
        }
        if stage == .sessionRestore,
           !(error is AuthenticationServiceError)
        {
            recordDiagnostic(
                category: .authentication,
                taskID: identifier,
                stage: .sessionRestore,
                code: .localStateReadFailed
            )
        }
        if let captureError = error as? CoreAudioCaptureError {
            switch captureError {
            case .calibrationRequired:
                await send(
                    .serviceFailed(.microphoneCalibrationRequired)
                )
            case .inputDeviceChanged:
                await send(.serviceFailed(.inputDeviceChanged))
            case .nearSpeechNotDetected:
                await send(.serviceFailed(.nearSpeechNotDetected))
            case .conversionUnavailable, .conversionFailed:
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: stage,
                    code: .audioConversionFailed
                )
                await send(.serviceFailed(fallback))
            case .frameBufferOverflow:
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: stage,
                    code: .audioBufferOverflow
                )
                await send(.serviceFailed(fallback))
            case .invalidState:
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: stage,
                    code: .captureInternalFailure
                )
                await send(.serviceFailed(fallback))
            case .microphoneUnavailable:
                await send(.serviceFailed(fallback))
            }
            return
        }
        guard let realtimeError = error as? RealtimeDictationError else {
            if stage == .capturePreflight || stage == .captureStart ||
                stage == .audioPump
            {
                recordDiagnostic(
                    category: .dictation,
                    taskID: identifier,
                    stage: stage,
                    code: .captureInternalFailure
                )
            }
            await send(.serviceFailed(fallback))
            return
        }
        switch realtimeError {
        case .authRequired:
            await invalidateAuthentication(.authenticationRequired)
        case .sessionReplaced:
            await invalidateAuthentication(.sessionReplaced)
        case .sessionExpired:
            await invalidateAuthentication(.sessionExpired)
        case .accountDisabled:
            await invalidateAuthentication(.accountDisabled)
        case .tooManyRequests:
            await send(.serviceFailed(.tooManyRequests))
        case .protocolViolation, .invalidState, .invalidAudioFrame:
            recordDiagnostic(
                category: .dictation,
                taskID: identifier,
                stage: stage,
                code: .protocolViolation
            )
            await send(.serviceFailed(.protocolViolation))
        case .audioLimitExceeded:
            await send(.serviceFailed(.audioLimitExceeded))
        case .finalTimeout:
            await send(.serviceFailed(.finalTimeout))
        case .serviceUnavailable:
            await send(.serviceFailed(.serviceUnavailable))
        case .cancelled:
            await send(.serviceFailed(fallback))
        }
    }

    private func recordDiagnostic(
        category: DiagnosticCategory,
        taskID: UUID?,
        stage: DiagnosticStage,
        code: DiagnosticCode
    ) {
        diagnosticRecorder.record(
            DiagnosticIncident(
                category: category,
                taskId: taskID,
                stage: stage,
                code: code
            )
        )
    }

    private func invalidateAuthentication(
        _ availability: DictationAvailability
    ) async {
        await send(.authenticationInvalidated(availability))
        await authenticationInvalidationHandler(availability)
    }

    private func cancelActiveSession() async {
        let activeCapture = capture
        let activeClient = client
        let activeTarget = target

        maximumDurationTask?.cancel()
        pumpTask?.cancel()
        maximumDurationTask = nil
        pumpTask = nil
        capture = nil
        client = nil
        target = nil
        sessionIdentifier = nil
        sessionDestination = .insertion
        audioLevel = nil
        audioLevelSmoother = TxChatAudioLevelSmoother()
        completionTextOptimizationFallbackReason = nil

        await activeCapture?.cancel()
        await activeClient?.cancel()
        if let activeTarget {
            dependencies.targetHandler.discard(activeTarget)
        }
    }

    private func releaseCompletedSession() {
        let activeTarget = target
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        pumpTask = nil
        capture = nil
        client = nil
        target = nil
        sessionIdentifier = nil
        sessionDestination = .insertion
        audioLevel = nil
        audioLevelSmoother = TxChatAudioLevelSmoother()
        if let activeTarget {
            dependencies.targetHandler.discard(activeTarget)
        }
    }

    private static func isNonempty(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
