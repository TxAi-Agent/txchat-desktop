import Combine
import Foundation

struct ProductFinalTextPreparer: FinalTextPreparing {
    private let dictionary: any DictionaryTextReplacing

    init(
        dictionary: any DictionaryTextReplacing =
            PassthroughDictionaryTextReplacer()
    ) {
        self.dictionary = dictionary
    }

    func prepare(
        _ rawText: String,
        mode: DictationMode
    ) async throws -> String {
        _ = mode
        return try await dictionary.replaceFinalText(rawText)
    }
}

@MainActor
final class ProductionDictationRuntime: ObservableObject,
    ProductDictationControlling
{
    typealias SessionInvalidationHandler = @MainActor @Sendable (
        AuthenticationServiceError
    ) async -> Void
    typealias HotkeyIntentHandler = @MainActor @Sendable () async -> Void

    private let coordinator: AppCoordinator
    private let hotkeyMonitor: any FunctionKeyMonitoring
    private let shortcutStore: any ShortcutPreferenceStoring
    private let modeStore: any DictationModePreferenceStoring
    private var coordinatorObservation: AnyCancellable?
    private var hotkeyMonitoring = false
    private var hotkeyIntentHandler: HotkeyIntentHandler?

    var state: DictationState { coordinator.state }
    var mode: DictationMode { coordinator.mode }
    var voiceTestResultText: String? { coordinator.voiceTestResultText }
    var audioLevel: Double? { coordinator.audioLevel }
    var completionUsedVerbatimFallback: Bool {
        coordinator.completionUsedVerbatimFallback
    }
    private(set) var shortcut: ProductShortcut

    init(
        dependencies: AppDependencies,
        hotkeyMonitor: any FunctionKeyMonitoring = FunctionKeyMonitor(),
        shortcutStore: any ShortcutPreferenceStoring =
            UserDefaultsShortcutStore(),
        modeStore: any DictationModePreferenceStoring =
            UserDefaultsDictationModeStore(),
        initialState: DictationState = .idle,
        mode: DictationMode? = nil,
        diagnosticRecorder: any DiagnosticIncidentRecording =
            DisabledDiagnosticIncidentRecorder.shared,
        sessionInvalidationHandler:
            @escaping SessionInvalidationHandler = { _ in }
    ) {
        self.hotkeyMonitor = hotkeyMonitor
        self.shortcutStore = shortcutStore
        self.modeStore = modeStore
        shortcut = shortcutStore.loadShortcut()
        coordinator = AppCoordinator(
            dependencies: dependencies,
            initialState: initialState,
            mode: mode ?? modeStore.loadMode(),
            diagnosticRecorder: diagnosticRecorder,
            authenticationInvalidationHandler: { availability in
                await sessionInvalidationHandler(
                    Self.authenticationError(for: availability)
                )
            }
        )
        coordinatorObservation = coordinator.objectWillChange.sink {
            [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    static func production(
        configuration: ProductConfiguration,
        accessTokenProvider: any DictationAccessTokenProviding,
        targetHandler: any DictationTargetHandling =
            AccessibilityTargetHandler(),
        hotkeyMonitor: any FunctionKeyMonitoring = FunctionKeyMonitor(),
        inputDeviceProvider: any TxChatInputDeviceProviding =
            CoreAudioInputDeviceProvider(),
        streamingSessionFactory: AppDependencies.StreamingSessionFactory? = nil,
        finalPreparer: any FinalTextPreparing = ProductFinalTextPreparer(),
        diagnosticRecorder: any DiagnosticIncidentRecording =
            DisabledDiagnosticIncidentRecorder.shared,
        sessionInvalidationHandler:
            @escaping SessionInvalidationHandler = { _ in }
    ) -> ProductionDictationRuntime {
        let realtimeBaseURL = configuration.realtimeBaseURL
        let allowsLoopback =
            configuration.allowsInsecureLoopbackForTesting
        let captureFactory: AppDependencies.CaptureFactory = {
            CoreAudioCapture(
                deviceProvider: inputDeviceProvider
            )
        }
        let dependencies: AppDependencies
        if let streamingSessionFactory {
            dependencies = AppDependencies(
                captureFactory: captureFactory,
                streamingSessionFactory: streamingSessionFactory,
                targetHandler: targetHandler,
                finalPreparer: finalPreparer
            )
        } else {
            dependencies = AppDependencies(
                accessTokenProvider: accessTokenProvider,
                captureFactory: captureFactory,
                streamingFactory: {
                    StreamingDictationClient(
                        transport: SpekWriteWebSocketTransport(
                            baseURL: realtimeBaseURL,
                            allowsInsecureLoopbackForTesting: allowsLoopback
                        )
                    )
                },
                targetHandler: targetHandler,
                finalPreparer: finalPreparer
            )
        }
        return ProductionDictationRuntime(
            dependencies: dependencies,
            hotkeyMonitor: hotkeyMonitor,
            diagnosticRecorder: diagnosticRecorder,
            sessionInvalidationHandler: sessionInvalidationHandler
        )
    }

    @discardableResult
    func startHotkeyMonitoring() -> Bool {
        let result = hotkeyMonitor.start(
            shortcut: shortcut,
            handler: makeHotkeyHandler()
        )
        hotkeyMonitoring = result.isRegistered
        return hotkeyMonitoring
    }

    func stopHotkeyMonitoring() {
        hotkeyMonitor.stop()
        hotkeyMonitoring = false
    }

    func setHotkeyIntentHandler(
        _ handler: @escaping HotkeyIntentHandler
    ) {
        hotkeyIntentHandler = handler
    }

    @discardableResult
    func updateShortcut(
        _ candidate: ProductShortcut
    ) -> ShortcutUpdateResult {
        if candidate == shortcut, hotkeyMonitoring {
            return .updated
        }

        let original = shortcut
        let registration = hotkeyMonitor.start(
            shortcut: candidate,
            handler: makeHotkeyHandler()
        )
        guard case .registered = registration else {
            guard restoreShortcutRegistration(original) else {
                return .failed(.unavailable)
            }
            if case let .failed(failure) = registration {
                return .failed(failure)
            }
            return .failed(.unavailable)
        }
        hotkeyMonitoring = true

        guard shortcutStore.saveShortcut(candidate) else {
            guard restoreShortcutRegistration(original) else {
                return .failed(.unavailable)
            }
            return .saveFailed
        }

        shortcut = candidate
        objectWillChange.send()
        return .updated
    }

    func toggle() async {
        await coordinator.toggle()
    }

    func toggleVoiceTest() async {
        await coordinator.toggleVoiceTest()
    }

    func clearVoiceTestResult() {
        coordinator.clearVoiceTestResult()
    }

    @discardableResult
    func retryInsertion() async -> Bool {
        await coordinator.retryInsertion()
    }

    @discardableResult
    func cancel() async -> Bool {
        await coordinator.cancel()
    }

    func dismissResult() async {
        await coordinator.dismissResult()
    }

    func logout() async {
        stopHotkeyMonitoring()
        await coordinator.logout()
    }

    func terminate() async {
        stopHotkeyMonitoring()
        await coordinator.terminate()
    }

    func setMode(_ mode: DictationMode) {
        let previousMode = coordinator.mode
        guard previousMode != mode else {
            return
        }
        coordinator.setMode(mode)
        guard coordinator.mode == mode else {
            return
        }
        guard modeStore.saveMode(mode) else {
            coordinator.setMode(previousMode)
            return
        }
    }

    func reloadPreferences() {
        shortcut = shortcutStore.loadShortcut()
        let restoredMode = modeStore.loadMode()
        coordinator.setMode(restoredMode)
        objectWillChange.send()
    }

    private func makeHotkeyHandler() -> @MainActor () -> Void {
        { [weak self] in
            guard let self else {
                return
            }
            Task { @MainActor in
                if let hotkeyIntentHandler = self.hotkeyIntentHandler {
                    await hotkeyIntentHandler()
                } else {
                    await self.toggle()
                }
            }
        }
    }

    @discardableResult
    private func restoreShortcutRegistration(
        _ original: ProductShortcut
    ) -> Bool {
        let result = hotkeyMonitor.start(
            shortcut: original,
            handler: makeHotkeyHandler()
        )
        hotkeyMonitoring = result.isRegistered
        return hotkeyMonitoring
    }

    private static func authenticationError(
        for availability: DictationAvailability
    ) -> AuthenticationServiceError {
        switch availability {
        case .sessionReplaced:
            return .sessionReplaced
        case .accountDisabled:
            return .accountDisabled
        case .authenticationRequired, .sessionExpired,
             .prerequisitesMissing:
            return .authenticationRequired
        }
    }
}
