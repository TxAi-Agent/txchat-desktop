import Foundation
import XCTest
@testable import SpekWrite

@MainActor
private final class CoordinatorEventLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

private struct CoordinatorTokenProvider: DictationAccessTokenProviding {
    let log: CoordinatorEventLog
    var value = "session-token"
    var error: AuthenticationServiceError?

    func accessToken() async throws -> String {
        await log.append("token.read")
        if let error {
            throw error
        }
        return value
    }
}

private actor CoordinatorCapture: DictationAudioCapturing {
    let log: CoordinatorEventLog
    let frames: [Data]
    let failsOnStart: Bool
    let preflightError: CoreAudioCaptureError?
    private var audioLevelHandler: AudioLevelHandler?

    init(
        log: CoordinatorEventLog,
        frames: [Data],
        failsOnStart: Bool = false,
        preflightError: CoreAudioCaptureError? = nil
    ) {
        self.log = log
        self.frames = frames
        self.failsOnStart = failsOnStart
        self.preflightError = preflightError
    }

    func preflight() async throws {
        await log.append("capture.preflight")
        if let preflightError {
            throw preflightError
        }
    }

    func start() async throws -> AsyncThrowingStream<Data, Error> {
        await log.append("capture.start")
        if failsOnStart {
            throw CoordinatorTestError.captureFailed
        }
        let frames = self.frames
        return AsyncThrowingStream { continuation in
            for frame in frames {
                continuation.yield(frame)
            }
            continuation.finish()
        }
    }

    func start(
        onAudioLevel: @escaping AudioLevelHandler
    ) async throws -> AsyncThrowingStream<Data, Error> {
        audioLevelHandler = onAudioLevel
        return try await start()
    }

    func stop() async {
        await log.append("capture.stop")
    }

    func cancel() async {
        await log.append("capture.cancel")
    }

    func emitAudioLevel(_ level: Double) async {
        if let audioLevelHandler {
            await audioLevelHandler(level)
        }
    }
}

private actor CoordinatorBlockingCancellationCapture:
    DictationAudioCapturing
{
    let log: CoordinatorEventLog
    private var cancellationContinuation:
        CheckedContinuation<Void, Never>?

    init(log: CoordinatorEventLog) {
        self.log = log
    }

    func start() async throws -> AsyncThrowingStream<Data, Error> {
        await log.append("capture.start")
        return AsyncThrowingStream { _ in }
    }

    func stop() async {
        await log.append("capture.stop")
    }

    func cancel() async {
        await log.append("capture.cancel")
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
        }
    }

    func waitUntilCancellationPending() async -> Bool {
        for _ in 0..<200 {
            if cancellationContinuation != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func finishCancellation() {
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}

private actor CoordinatorStream: DictationStreamingServing {
    let log: CoordinatorEventLog
    let finalText: String
    let sendError: RealtimeDictationError?
    let finishError: RealtimeDictationError?
    let resultMode: RealtimeFinalResultMode?
    let fallbackReason: RealtimeFallbackReason?
    private var partialHandler: StreamingDictationClient.PartialHandler?
    private var historicalPartialHandler: StreamingDictationClient.PartialHandler?
    private var organizingHandler: OrganizingHandler?
    private var requestedModes: [RealtimeSessionMode] = []

    init(
        log: CoordinatorEventLog,
        finalText: String,
        sendError: RealtimeDictationError? = nil,
        finishError: RealtimeDictationError? = nil,
        resultMode: RealtimeFinalResultMode? = nil,
        fallbackReason: RealtimeFallbackReason? = nil
    ) {
        self.log = log
        self.finalText = finalText
        self.sendError = sendError
        self.finishError = finishError
        self.resultMode = resultMode
        self.fallbackReason = fallbackReason
    }

    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws {
        partialHandler = onPartial
        historicalPartialHandler = onPartial
        await log.append("stream.start")
    }

    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping StreamingDictationClient.PartialHandler,
        onOrganizing: @escaping OrganizingHandler
    ) async throws {
        requestedModes.append(mode)
        organizingHandler = onOrganizing
        try await start(
            accessToken: accessToken,
            onPartial: onPartial
        )
    }

    func send(audio: Data) async throws {
        await log.append("stream.audio:\(audio.count)")
        if let sendError {
            throw sendError
        }
    }

    func finish() async throws -> String {
        await log.append("stream.finish")
        if let finishError {
            throw finishError
        }
        return finalText
    }

    func finishResult() async throws -> DictationStreamingResult {
        DictationStreamingResult(
            text: try await finish(),
            mode: resultMode,
            fallbackReason: fallbackReason
        )
    }

    func cancel() async {
        partialHandler = nil
        await log.append("stream.cancel")
    }

    func emitPartial(_ text: String) async {
        if let partialHandler {
            await partialHandler(text)
        }
    }

    func emitHistoricalPartial(_ text: String) async {
        if let historicalPartialHandler {
            await historicalPartialHandler(text)
        }
    }

    func emitOrganizing() async {
        if let organizingHandler {
            await organizingHandler()
        }
    }

    func requestedModesSnapshot() -> [RealtimeSessionMode] {
        requestedModes
    }
}

@MainActor
private final class CoordinatorTargetHandler: DictationTargetHandling {
    let log: CoordinatorEventLog
    let captureOutcome: DictationTargetCaptureOutcome?
    let insertionSucceeds: Bool
    let target = DictationTarget(
        id: UUID(uuidString: "019c1a9d-235c-7b9d-919c-38e0e3b56c01")!,
        processIdentifier: 42
    )
    private(set) var insertedTexts: [String] = []

    init(
        log: CoordinatorEventLog,
        captureOutcome: DictationTargetCaptureOutcome? = nil,
        insertionSucceeds: Bool = true
    ) {
        self.log = log
        self.captureOutcome = captureOutcome
        self.insertionSucceeds = insertionSucceeds
    }

    func capture() -> DictationTargetCaptureOutcome {
        log.append("target.capture")
        return captureOutcome ?? .captured(target)
    }

    func insert(_ text: String, into target: DictationTarget) -> Bool {
        log.append("target.insert")
        insertedTexts.append(text)
        return insertionSucceeds
    }

    func discard(_ target: DictationTarget) {
        log.append("target.discard")
    }
}

@MainActor
private final class OneShotRetryTargetHandler: DictationTargetHandling {
    private let log: CoordinatorEventLog
    private let targets = [
        DictationTarget(
            id: UUID(uuidString: "019fd0ef-dc98-7537-8d76-419839072e32")!,
            processIdentifier: 42
        ),
        DictationTarget(
            id: UUID(uuidString: "019fd0ef-e95f-76b5-b74a-284210f1546e")!,
            processIdentifier: 84
        ),
    ]
    private var availableTargetIDs: Set<UUID> = []
    private(set) var captureCount = 0
    private(set) var insertions: [(String, DictationTarget)] = []

    init(log: CoordinatorEventLog) {
        self.log = log
    }

    func capture() -> DictationTargetCaptureOutcome {
        log.append("target.capture")
        guard captureCount < targets.count else {
            return .unavailable
        }
        let target = targets[captureCount]
        captureCount += 1
        availableTargetIDs.insert(target.id)
        return .captured(target)
    }

    func insert(_ text: String, into target: DictationTarget) -> Bool {
        log.append("target.insert")
        insertions.append((text, target))
        guard availableTargetIDs.remove(target.id) != nil else {
            return false
        }
        return target == targets[1]
    }

    func discard(_ target: DictationTarget) {
        log.append("target.discard")
        availableTargetIDs.remove(target.id)
    }
}

private struct CoordinatorFinalPreparer: FinalTextPreparing {
    let log: CoordinatorEventLog
    let fails: Bool

    init(log: CoordinatorEventLog, fails: Bool = false) {
        self.log = log
        self.fails = fails
    }

    func prepare(
        _ rawText: String,
        mode: DictationMode
    ) async throws -> String {
        await log.append("prepare")
        if fails {
            throw CoordinatorTestError.preparationFailed
        }
        return rawText
    }
}

private struct ReplacingCoordinatorFinalPreparer: FinalTextPreparing {
    let log: CoordinatorEventLog

    func prepare(
        _ rawText: String,
        mode: DictationMode
    ) async throws -> String {
        _ = mode
        await log.append("dictionary.prepare")
        return rawText.replacingOccurrences(of: "Txchat", with: "TxChat")
    }
}

private enum CoordinatorTestError: Error {
    case preparationFailed
    case captureFailed
}

@MainActor
private final class CoordinatorDiagnosticRecorder:
    DiagnosticIncidentRecording
{
    private(set) var incidents: [DiagnosticIncident] = []

    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date,
        durationMs: Int?,
        httpStatus: Int?
    ) {
        _ = occurredAt
        _ = durationMs
        _ = httpStatus
        incidents.append(incident)
    }
}

private struct SuspendedCoordinatorClock: DictationClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

private struct ImmediateCoordinatorClock: DictationClock {
    func sleep(for duration: Duration) async throws {}
}

private actor DeferredFinishStream: DictationStreamingServing {
    let log: CoordinatorEventLog
    private var historicalPartialHandler: StreamingDictationClient.PartialHandler?
    private var finishContinuation: CheckedContinuation<String, Never>?

    init(log: CoordinatorEventLog) {
        self.log = log
    }

    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws {
        historicalPartialHandler = onPartial
        await log.append("stream.start")
    }

    func send(audio: Data) async throws {
        await log.append("stream.audio:\(audio.count)")
    }

    func finish() async throws -> String {
        await log.append("stream.finish")
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func cancel() async {
        await log.append("stream.cancel")
    }

    func emitHistoricalPartial(_ text: String) async {
        if let historicalPartialHandler {
            await historicalPartialHandler(text)
        }
    }

    func resolveFinal(_ text: String) {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(returning: text)
    }
}

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testCustomProviderDiagnosticUsesExactContentFreeTaxonomy() async {
        let log = CoordinatorEventLog()
        let diagnostics = CoordinatorDiagnosticRecorder()
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                captureFactory: {
                    CoordinatorCapture(log: log, frames: [])
                },
                streamingSessionFactory: {
                    throw CustomAIDiagnosticError(
                        category: .customASR,
                        stage: .providerConfiguration,
                        code: .providerConfigurationInvalid
                    )
                },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            ),
            diagnosticRecorder: diagnostics
        )

        await coordinator.start()

        XCTAssertEqual(coordinator.state, .failed(.serviceUnavailable))
        XCTAssertEqual(diagnostics.incidents.count, 1)
        XCTAssertEqual(diagnostics.incidents.first?.category, .customASR)
        XCTAssertEqual(
            diagnostics.incidents.first?.stage,
            .providerConfiguration
        )
        XCTAssertEqual(
            diagnostics.incidents.first?.code,
            .providerConfigurationInvalid
        )
        XCTAssertNotNil(diagnostics.incidents.first?.taskId)
    }

    func testReportableCaptureFailuresRecordExactStageAndTaskID() async {
        let cases: [(CoreAudioCaptureError, DiagnosticCode)] = [
            (.conversionFailed, .audioConversionFailed),
            (.conversionUnavailable, .audioConversionFailed),
            (.frameBufferOverflow, .audioBufferOverflow),
            (.invalidState, .captureInternalFailure),
        ]
        for (error, code) in cases {
            let log = CoordinatorEventLog()
            let diagnostics = CoordinatorDiagnosticRecorder()
            let coordinator = AppCoordinator(
                dependencies: AppDependencies(
                    accessTokenProvider: CoordinatorTokenProvider(log: log),
                    captureFactory: {
                        CoordinatorCapture(
                            log: log,
                            frames: [],
                            preflightError: error
                        )
                    },
                    streamingFactory: {
                        CoordinatorStream(log: log, finalText: "unused")
                    },
                    targetHandler: CoordinatorTargetHandler(log: log),
                    clock: SuspendedCoordinatorClock()
                ),
                diagnosticRecorder: diagnostics
            )

            await coordinator.start()

            XCTAssertEqual(diagnostics.incidents.count, 1)
            XCTAssertEqual(diagnostics.incidents[0].category, .dictation)
            XCTAssertEqual(diagnostics.incidents[0].stage, .capturePreflight)
            XCTAssertEqual(diagnostics.incidents[0].code, code)
            XCTAssertNotNil(diagnostics.incidents[0].taskId)
        }
    }

    func testExpectedCaptureAndNetworkFailuresDoNotReport() async {
        for error in [
            CoreAudioCaptureError.microphoneUnavailable,
            .calibrationRequired,
            .inputDeviceChanged,
            .nearSpeechNotDetected,
        ] {
            let log = CoordinatorEventLog()
            let diagnostics = CoordinatorDiagnosticRecorder()
            let coordinator = AppCoordinator(
                dependencies: AppDependencies(
                    accessTokenProvider: CoordinatorTokenProvider(log: log),
                    captureFactory: {
                        CoordinatorCapture(log: log, frames: [], preflightError: error)
                    },
                    streamingFactory: {
                        CoordinatorStream(log: log, finalText: "unused")
                    },
                    targetHandler: CoordinatorTargetHandler(log: log),
                    clock: SuspendedCoordinatorClock()
                ),
                diagnosticRecorder: diagnostics
            )
            await coordinator.start()
            XCTAssertTrue(diagnostics.incidents.isEmpty, "\(error)")
        }
    }

    func testAuthenticationProtocolViolationReportsExactRestoreStage() async {
        let log = CoordinatorEventLog()
        let diagnostics = CoordinatorDiagnosticRecorder()
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(
                    log: log,
                    error: .protocolViolation
                ),
                captureFactory: {
                    CoordinatorCapture(log: log, frames: [])
                },
                streamingFactory: {
                    CoordinatorStream(log: log, finalText: "unused")
                },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            ),
            diagnosticRecorder: diagnostics
        )

        await coordinator.start()

        XCTAssertEqual(
            diagnostics.incidents,
            [
                DiagnosticIncident(
                    category: .authentication,
                    taskId: diagnostics.incidents.first?.taskId,
                    stage: .sessionRestore,
                    code: .protocolViolation
                ),
            ]
        )
        XCTAssertNotNil(diagnostics.incidents.first?.taskId)
    }

    func testExpectedAuthenticationErrorDoesNotReport() async {
        let log = CoordinatorEventLog()
        let diagnostics = CoordinatorDiagnosticRecorder()
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(
                    log: log,
                    error: .serviceUnavailable(retryAfterSeconds: 30)
                ),
                captureFactory: {
                    CoordinatorCapture(log: log, frames: [])
                },
                streamingFactory: {
                    CoordinatorStream(log: log, finalText: "unused")
                },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            ),
            diagnosticRecorder: diagnostics
        )

        await coordinator.start()

        XCTAssertTrue(diagnostics.incidents.isEmpty)
    }

    func testProtocolFailureRecordsStreamFinishInsteadOfGenericProviderStage()
        async
    {
        let log = CoordinatorEventLog()
        let diagnostics = CoordinatorDiagnosticRecorder()
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { CoordinatorCapture(log: log, frames: []) },
                streamingFactory: {
                    CoordinatorStream(
                        log: log,
                        finalText: "unused",
                        finishError: .protocolViolation
                    )
                },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            ),
            diagnosticRecorder: diagnostics
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(diagnostics.incidents.count, 1)
        XCTAssertEqual(diagnostics.incidents[0].stage, .streamFinish)
        XCTAssertEqual(diagnostics.incidents[0].code, .protocolViolation)
    }
    func testNewSessionWaitsForAcceptedCancellationCleanup() async {
        let log = CoordinatorEventLog()
        let capture = CoordinatorBlockingCancellationCapture(log: log)
        let stream = CoordinatorStream(log: log, finalText: "unused")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        XCTAssertEqual(coordinator.state, .listening(.empty))

        let cancellationTask = Task { @MainActor in
            await coordinator.cancel()
        }
        let cancellationPending =
            await capture.waitUntilCancellationPending()
        XCTAssertTrue(cancellationPending)
        XCTAssertEqual(coordinator.state, .idle)

        await coordinator.start()
        XCTAssertEqual(
            coordinator.state,
            .idle,
            "a new session must not overlap accepted cancellation cleanup"
        )

        await capture.finishCancellation()
        let cancellationAccepted = await cancellationTask.value
        XCTAssertTrue(cancellationAccepted)

        await coordinator.start()
        XCTAssertEqual(coordinator.state, .listening(.empty))
    }

    func testHappyPathOrdersServicesAndInsertsOneFinal() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(
            log: log,
            frames: [Data(repeating: 0, count: 3_200)]
        )
        let stream = CoordinatorStream(log: log, finalText: "唯一终稿")
        var captureFactoryCount = 0
        var streamingFactoryCount = 0
        let dependencies = AppDependencies(
            accessTokenProvider: CoordinatorTokenProvider(log: log),
            captureFactory: {
                captureFactoryCount += 1
                return capture
            },
            streamingFactory: {
                streamingFactoryCount += 1
                return stream
            },
            targetHandler: targetHandler,
            finalPreparer: CoordinatorFinalPreparer(log: log),
            clock: SuspendedCoordinatorClock()
        )
        let coordinator = AppCoordinator(dependencies: dependencies)

        await coordinator.start()
        try await waitUntil {
            log.entries.contains("stream.audio:3200")
        }
        await stream.emitPartial("可替换假设")
        try await waitUntil {
            coordinator.state == .listening(
                .init(partialText: "可替换假设")
            )
        }
        await coordinator.start()

        XCTAssertEqual(captureFactoryCount, 1)
        XCTAssertEqual(streamingFactoryCount, 1)
        let requestedModes = await stream.requestedModesSnapshot()
        XCTAssertEqual(requestedModes, [.smart])
        XCTAssertFalse(log.entries.contains("prepare"))
        XCTAssertFalse(log.entries.contains("target.insert"))

        await coordinator.stop()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(
            log.entries,
            [
                "target.capture",
                "capture.preflight",
                "token.read",
                "capture.start",
                "stream.start",
                "stream.audio:3200",
                "capture.stop",
                "stream.finish",
                "prepare",
                "target.insert",
                "target.discard",
            ]
        )
    }

    func testInjectedAudioLevelIsSmoothedAndResetWithoutMicrophoneAccess()
        async throws
    {
        let log = CoordinatorEventLog()
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "fixture")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await capture.emitAudioLevel(1)
        try await waitUntil { coordinator.audioLevel != nil }

        XCTAssertEqual(coordinator.audioLevel ?? 0, 0.494, accuracy: 0.000_1)

        await coordinator.stop()
        XCTAssertNil(coordinator.audioLevel)
    }

    func testVerbatimFallbackResultStillCompletesAndSetsSafeFeedbackFlag()
        async
    {
        let log = CoordinatorEventLog()
        let stream = CoordinatorStream(
            log: log,
            finalText: "fixture fallback",
            resultMode: .verbatimFallback,
            fallbackReason: .textOptimizationTimeout
        )
        let target = CoordinatorTargetHandler(log: log)
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: {
                    CoordinatorCapture(log: log, frames: [])
                },
                streamingFactory: { stream },
                targetHandler: target,
                clock: SuspendedCoordinatorClock()
            ),
            mode: .smart
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertTrue(coordinator.completionUsedVerbatimFallback)
        XCTAssertEqual(
            coordinator.completionTextOptimizationFallbackReason,
            .textOptimizationTimeout
        )
        XCTAssertEqual(target.insertedTexts, ["fixture fallback"])
    }

    func testUnavailableTargetStillRecordsAndRetainsFinalInFallback() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(
            log: log,
            captureOutcome: .unavailable
        )
        var captureFactoryCount = 0
        var streamingFactoryCount = 0
        let dependencies = AppDependencies(
            accessTokenProvider: CoordinatorTokenProvider(log: log),
            captureFactory: {
                captureFactoryCount += 1
                return CoordinatorCapture(log: log, frames: [])
            },
            streamingFactory: {
                streamingFactoryCount += 1
                return CoordinatorStream(
                    log: log,
                    finalText: "保留的最终文字"
                )
            },
            targetHandler: targetHandler,
            clock: SuspendedCoordinatorClock()
        )
        let coordinator = AppCoordinator(dependencies: dependencies)

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(
            coordinator.state,
            .resultFallback(text: "保留的最终文字")
        )
        XCTAssertEqual(captureFactoryCount, 1)
        XCTAssertEqual(streamingFactoryCount, 1)
        XCTAssertTrue(log.entries.contains("token.read"))
        XCTAssertTrue(log.entries.contains("capture.start"))
        XCTAssertTrue(log.entries.contains("stream.start"))
        XCTAssertTrue(log.entries.contains("stream.finish"))
        XCTAssertFalse(log.entries.contains("target.insert"))
    }

    func testBlockedTargetDoesNotCreateCaptureClientOrReadToken() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(
            log: log,
            captureOutcome: .blocked
        )
        var captureFactoryCount = 0
        var streamingFactoryCount = 0
        let dependencies = AppDependencies(
            accessTokenProvider: CoordinatorTokenProvider(log: log),
            captureFactory: {
                captureFactoryCount += 1
                return CoordinatorCapture(log: log, frames: [])
            },
            streamingFactory: {
                streamingFactoryCount += 1
                return CoordinatorStream(log: log, finalText: "unused")
            },
            targetHandler: targetHandler,
            clock: SuspendedCoordinatorClock()
        )
        let coordinator = AppCoordinator(dependencies: dependencies)

        await coordinator.start()

        XCTAssertEqual(coordinator.state, .failed(.targetUnavailable))
        XCTAssertEqual(log.entries, ["target.capture"])
        XCTAssertEqual(captureFactoryCount, 0)
        XCTAssertEqual(streamingFactoryCount, 0)
    }

    func testVoiceTestStreamsWithoutCapturingOrInsertingExternalTarget()
        async throws
    {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(
            log: log,
            captureOutcome: .unavailable
        )
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "语音测试结果")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.toggleVoiceTest()
        XCTAssertEqual(coordinator.state, .listening(.empty))
        await stream.emitPartial("实时文字")
        try await waitUntil {
            coordinator.state == .listening(
                .init(partialText: "实时文字")
            )
        }

        await coordinator.toggleVoiceTest()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(coordinator.voiceTestResultText, "语音测试结果")
        XCTAssertFalse(log.entries.contains("target.capture"))
        XCTAssertFalse(log.entries.contains("target.insert"))
        XCTAssertTrue(log.entries.contains("capture.start"))
        XCTAssertTrue(log.entries.contains("stream.start"))
        XCTAssertTrue(log.entries.contains("stream.finish"))
    }

    func testEmptyTokenFailsBeforeCaptureOrStreamStart() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "unused")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(
                    log: log,
                    value: " \n "
                ),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()

        XCTAssertEqual(
            coordinator.state,
            .unavailable(.authenticationRequired)
        )
        XCTAssertFalse(log.entries.contains("capture.start"))
        XCTAssertFalse(log.entries.contains("stream.start"))
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testCaptureFailureDoesNotStartNetwork() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(
            log: log,
            frames: [],
            failsOnStart: true
        )
        let stream = CoordinatorStream(log: log, finalText: "unused")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()

        XCTAssertEqual(coordinator.state, .failed(.captureUnavailable))
        XCTAssertFalse(log.entries.contains("stream.start"))
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testCalibrationPreflightFailsBeforeTokenAndNetwork() async {
        let log = CoordinatorEventLog()
        let capture = CoordinatorCapture(
            log: log,
            frames: [],
            preflightError: .calibrationRequired
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: {
                    CoordinatorStream(log: log, finalText: "unused")
                },
                targetHandler: CoordinatorTargetHandler(log: log),
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()

        XCTAssertEqual(
            coordinator.state,
            .failed(.microphoneCalibrationRequired)
        )
        XCTAssertTrue(log.entries.contains("capture.preflight"))
        XCTAssertFalse(log.entries.contains("token.read"))
        XCTAssertFalse(log.entries.contains("capture.start"))
        XCTAssertFalse(log.entries.contains("stream.start"))
    }

    func testInvalidCapturedFrameFailsClosedBeforeStreamSend() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(
            log: log,
            frames: [Data(repeating: 0, count: 3)]
        )
        let stream = CoordinatorStream(log: log, finalText: "unused")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        try await waitUntil {
            coordinator.state == .failed(.captureUnavailable)
        }

        XCTAssertFalse(
            log.entries.contains { $0.hasPrefix("stream.audio:") }
        )
        XCTAssertTrue(targetHandler.insertedTexts.isEmpty)
    }

    func testPreparationFailureInSmartModeInsertsRawFinal() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "原始 final")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                finalPreparer: CoordinatorFinalPreparer(
                    log: log,
                    fails: true
                ),
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(targetHandler.insertedTexts, ["原始 final"])
        XCTAssertEqual(log.entries.filter { $0 == "prepare" }.count, 1)
        XCTAssertEqual(
            log.entries.filter { $0 == "target.insert" }.count,
            1
        )
    }

    func testDictionaryPreparationRunsAfterProviderFinalAndBeforeInsertion()
        async throws
    {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(
            log: log,
            finalText: "Hello Txchat"
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                finalPreparer: ReplacingCoordinatorFinalPreparer(log: log),
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(targetHandler.insertedTexts, ["Hello TxChat"])
        let finish = try XCTUnwrap(log.entries.firstIndex(of: "stream.finish"))
        let prepare = try XCTUnwrap(
            log.entries.firstIndex(of: "dictionary.prepare")
        )
        let insert = try XCTUnwrap(log.entries.firstIndex(of: "target.insert"))
        XCTAssertLessThan(finish, prepare)
        XCTAssertLessThan(prepare, insert)
    }

    func testInsertionFailureRetainsOnlyFinalUntilDismissed() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(
            log: log,
            insertionSucceeds: false
        )
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "需要兜底的 final")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(
            coordinator.state,
            .resultFallback(text: "需要兜底的 final")
        )
        XCTAssertEqual(targetHandler.insertedTexts, ["需要兜底的 final"])
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            0
        )

        await coordinator.dismissResult()
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(targetHandler.insertedTexts, ["需要兜底的 final"])
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testRetryInsertionRecapturesTargetWithoutStartingNewSession() async {
        let log = CoordinatorEventLog()
        let targetHandler = OneShotRetryTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(
            log: log,
            finalText: "需要重新写入的 final"
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await coordinator.stop()
        XCTAssertEqual(
            coordinator.state,
            .resultFallback(text: "需要重新写入的 final")
        )

        let succeeded = await coordinator.retryInsertion()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(targetHandler.captureCount, 2)
        XCTAssertEqual(
            targetHandler.insertions.map(\.0),
            ["需要重新写入的 final", "需要重新写入的 final"]
        )
        XCTAssertNotEqual(
            targetHandler.insertions[0].1,
            targetHandler.insertions[1].1
        )
        XCTAssertEqual(
            log.entries.filter { $0 == "capture.start" }.count,
            1
        )
        XCTAssertEqual(
            log.entries.filter { $0 == "stream.start" }.count,
            1
        )
        XCTAssertEqual(
            log.entries.filter { $0 == "stream.finish" }.count,
            1
        )
    }

    func testRetryInsertionWithoutFreshTargetKeepsFallback() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(
            log: log,
            captureOutcome: .unavailable
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { CoordinatorCapture(log: log, frames: []) },
                streamingFactory: {
                    CoordinatorStream(log: log, finalText: "保留的 final")
                },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            ),
            initialState: .resultFallback(text: "保留的 final")
        )

        let succeeded = await coordinator.retryInsertion()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .resultFallback(text: "保留的 final")
        )
    }

    func testServiceFailureBeforeFinalDoesNotRetainPartial() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(
            log: log,
            finalText: "unused",
            finishError: .serviceUnavailable
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await stream.emitPartial("不可兜底的 partial")
        try await waitUntil {
            coordinator.state == .listening(
                .init(partialText: "不可兜底的 partial")
            )
        }
        await coordinator.stop()

        XCTAssertEqual(coordinator.state, .failed(.serviceUnavailable))
        XCTAssertTrue(targetHandler.insertedTexts.isEmpty)
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testUnexpectedClientCancellationFailsAndCleansUp() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(
            log: log,
            finalText: "unused",
            finishError: .cancelled
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(coordinator.state, .failed(.serviceUnavailable))
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testRealtimeErrorsMapToContentFreeDomainStates() async {
        let cases: [(RealtimeDictationError, DictationState)] = [
            (.authRequired, .unavailable(.authenticationRequired)),
            (.sessionReplaced, .unavailable(.sessionReplaced)),
            (.sessionExpired, .unavailable(.sessionExpired)),
            (.accountDisabled, .unavailable(.accountDisabled)),
            (.tooManyRequests, .failed(.tooManyRequests)),
            (.protocolViolation, .failed(.protocolViolation)),
            (.invalidState, .failed(.protocolViolation)),
            (.invalidAudioFrame, .failed(.protocolViolation)),
            (.audioLimitExceeded, .failed(.audioLimitExceeded)),
            (.serviceUnavailable, .failed(.serviceUnavailable)),
            (.finalTimeout, .failed(.finalTimeout)),
        ]

        for (error, expectedState) in cases {
            let log = CoordinatorEventLog()
            let targetHandler = CoordinatorTargetHandler(log: log)
            let capture = CoordinatorCapture(log: log, frames: [])
            let stream = CoordinatorStream(
                log: log,
                finalText: "unused",
                finishError: error
            )
            let coordinator = AppCoordinator(
                dependencies: AppDependencies(
                    accessTokenProvider: CoordinatorTokenProvider(log: log),
                    captureFactory: { capture },
                    streamingFactory: { stream },
                    targetHandler: targetHandler,
                    clock: SuspendedCoordinatorClock()
                )
            )

            await coordinator.start()
            await coordinator.stop()

            XCTAssertEqual(coordinator.state, expectedState)
            XCTAssertTrue(targetHandler.insertedTexts.isEmpty)
            XCTAssertEqual(
                log.entries.filter { $0 == "target.discard" }.count,
                1
            )
        }
    }

    func testMaximumDurationUsesTheSameStopPathOnce() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(log: log, finalText: "超时 final")
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: ImmediateCoordinatorClock()
            )
        )

        await coordinator.start()
        try await waitUntil { coordinator.state == .completed }
        await coordinator.stop()

        XCTAssertEqual(
            log.entries.filter { $0 == "capture.stop" }.count,
            1
        )
        XCTAssertEqual(
            log.entries.filter { $0 == "stream.finish" }.count,
            1
        )
        XCTAssertEqual(targetHandler.insertedTexts, ["超时 final"])
    }

    func testSessionReplacementBecomesUnavailableAndClearsEverything() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = CoordinatorStream(
            log: log,
            finalText: "unused",
            finishError: .sessionReplaced
        )
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        await stream.emitPartial("必须清除")
        await coordinator.stop()

        XCTAssertEqual(
            coordinator.state,
            .unavailable(.sessionReplaced)
        )
        XCTAssertTrue(targetHandler.insertedTexts.isEmpty)
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testLogoutAndTerminationCancelAndDiscardActiveSession() async {
        for terminates in [false, true] {
            let log = CoordinatorEventLog()
            let targetHandler = CoordinatorTargetHandler(log: log)
            let capture = CoordinatorCapture(log: log, frames: [])
            let stream = CoordinatorStream(log: log, finalText: "unused")
            let coordinator = AppCoordinator(
                dependencies: AppDependencies(
                    accessTokenProvider: CoordinatorTokenProvider(log: log),
                    captureFactory: { capture },
                    streamingFactory: { stream },
                    targetHandler: targetHandler,
                    clock: SuspendedCoordinatorClock()
                )
            )

            await coordinator.start()
            if terminates {
                await coordinator.terminate()
                XCTAssertEqual(coordinator.state, .idle)
            } else {
                await coordinator.logout()
                XCTAssertEqual(
                    coordinator.state,
                    .unavailable(.authenticationRequired)
                )
            }

            XCTAssertEqual(
                log.entries.filter { $0 == "capture.cancel" }.count,
                1
            )
            XCTAssertEqual(
                log.entries.filter { $0 == "stream.cancel" }.count,
                1
            )
            XCTAssertEqual(
                log.entries.filter { $0 == "target.discard" }.count,
                1
            )
        }
    }

    func testLatePartialAndFinalFromOldSessionAreIgnored() async throws {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        let capture = CoordinatorCapture(log: log, frames: [])
        let stream = DeferredFinishStream(log: log)
        let coordinator = AppCoordinator(
            dependencies: AppDependencies(
                accessTokenProvider: CoordinatorTokenProvider(log: log),
                captureFactory: { capture },
                streamingFactory: { stream },
                targetHandler: targetHandler,
                clock: SuspendedCoordinatorClock()
            )
        )

        await coordinator.start()
        let stopTask = Task { @MainActor in
            await coordinator.stop()
        }
        try await waitUntil { log.entries.contains("stream.finish") }
        await coordinator.cancel()
        await stream.emitHistoricalPartial("迟到 partial")
        await stream.resolveFinal("迟到 final")
        await stopTask.value

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(targetHandler.insertedTexts.isEmpty)
        XCTAssertEqual(
            log.entries.filter { $0 == "target.discard" }.count,
            1
        )
    }

    func testNewSessionUsesFreshCaptureAndClient() async {
        let log = CoordinatorEventLog()
        let targetHandler = CoordinatorTargetHandler(log: log)
        var captures: [CoordinatorCapture] = []
        var streams: [CoordinatorStream] = []
        let dependencies = AppDependencies(
            accessTokenProvider: CoordinatorTokenProvider(log: log),
            captureFactory: {
                let capture = CoordinatorCapture(log: log, frames: [])
                captures.append(capture)
                return capture
            },
            streamingFactory: {
                let stream = CoordinatorStream(
                    log: log,
                    finalText: "final \(streams.count + 1)"
                )
                streams.append(stream)
                return stream
            },
            targetHandler: targetHandler,
            clock: SuspendedCoordinatorClock()
        )
        let coordinator = AppCoordinator(dependencies: dependencies)

        await coordinator.start()
        await coordinator.stop()
        await coordinator.start()
        await coordinator.stop()

        XCTAssertEqual(captures.count, 2)
        XCTAssertEqual(streams.count, 2)
        XCTAssertFalse(captures[0] === captures[1])
        XCTAssertFalse(streams[0] === streams[1])
        XCTAssertEqual(targetHandler.insertedTexts, ["final 1", "final 2"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let started = ContinuousClock.now
        while !predicate() {
            if ContinuousClock.now - started > timeout {
                XCTFail("condition timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
