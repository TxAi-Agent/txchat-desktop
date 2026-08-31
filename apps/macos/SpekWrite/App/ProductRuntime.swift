import AppKit
import Combine
import Foundation

enum ProductReadySurface: Equatable, Sendable {
    case statusCenter
    case customAISettings
    case dictionary
}

enum AppLaunchRoute: Equatable, Sendable {
    case product

    static func resolve(
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> AppLaunchRoute {
        return .product
    }

    var requiresProductRuntime: Bool {
        switch self {
        case .product:
            true
        }
    }
}

@MainActor
private final class ProductSessionInvalidationRelay {
    weak var coordinator: ProductCoordinator?

    func handle(_ error: AuthenticationServiceError) async {
        await coordinator?.sessionInvalidated(error)
    }
}


@MainActor
protocol ProductDiagnosticLifecycle: AnyObject {
    func prepareForLaunch() async
    func terminate() async
}

extension DiagnosticRuntime: ProductDiagnosticLifecycle {}

@MainActor
final class ProductRuntime: ObservableObject {
    private struct HUDSnapshot: Equatable {
        let state: DictationState
        let shortcut: ProductShortcut
        let audioLevel: Double?
        let usedVerbatimFallback: Bool
        let language: TxChatLanguage
    }

    private struct FallbackSnapshot: Equatable {
        let text: String
        let language: TxChatLanguage
    }

    @Published var isShortcutEditorPresented = false {
        didSet {
            synchronizeHotkey()
        }
    }
    @Published private(set) var readySurface = ProductReadySurface.statusCenter

    let coordinator: ProductCoordinator
    let dictation: ProductionDictationRuntime
    let diagnostics: (any ProductDiagnosticLifecycle)?
    let customAISettings: CustomAISettingsRuntime?
    let dictionary: ProductDictionaryRuntime?
    let dictionarySettings: DictionarySettingsCoordinator?
    let launchAtLogin: (any LaunchAtLoginActivating)?
    let dependenciesAreInMemory: Bool

    private let overlayController: any DictationOverlayPresenting
    private let fallbackController: any ResultFallbackPresenting
    private var observations: Set<AnyCancellable> = []
    private var hotkeyMonitoring = false
    private var hotkeyLifecycleBlocked = false
    private var presentedFallback: FallbackSnapshot?
    private var lastHUDSnapshot: HUDSnapshot?
    private var launchTask: Task<Void, Never>?
    private var launchAtLoginActivationTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var isTerminating = false

    init(
        coordinator: ProductCoordinator,
        dictation: ProductionDictationRuntime,
        overlayController: any DictationOverlayPresenting =
            DictationOverlayController(),
        fallbackController: any ResultFallbackPresenting =
            ResultFallbackController(),
        diagnostics: (any ProductDiagnosticLifecycle)? = nil,
        customAISettings: CustomAISettingsRuntime? = nil,
        dictionary: ProductDictionaryRuntime? = nil,
        launchAtLogin: (any LaunchAtLoginActivating)? = nil,
        dependenciesAreInMemory: Bool
    ) {
        self.coordinator = coordinator
        self.dictation = dictation
        self.overlayController = overlayController
        self.fallbackController = fallbackController
        self.diagnostics = diagnostics
        self.customAISettings = customAISettings
        self.dictionary = dictionary
        self.launchAtLogin = launchAtLogin
        dictionarySettings = dictionary.map {
            DictionarySettingsCoordinator(service: $0)
        }
        self.dependenciesAreInMemory = dependenciesAreInMemory
        customAISettings?.setCloseHandler { [weak self] in
            self?.dismissCustomAISettings()
        }
        dictionarySettings?.setCloseHandler { [weak self] in
            self?.dismissDictionarySettings()
        }
        overlayController.setCancellationHandler { [weak dictation] in
            await dictation?.cancel() ?? false
        }
        dictation.setHotkeyIntentHandler { [weak coordinator] in
            await coordinator?.toggleDictation()
        }
        bindLifecycle()
    }

    static func bootstrap(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> ProductRuntime {
#if DEBUG
        if let local = PublicLocalDevelopmentConfiguration.load(
            environment: environment
        ),
        let configuration = try? ProductConfiguration(
            apiBaseURL: local.apiBaseURL,
            realtimeBaseURL: local.realtimeBaseURL,
            allowsInsecureLoopbackForTesting: true
        ),
        let authentication = try? PublicLocalAuthenticationService(
            baseURL: local.apiBaseURL
        ) {
            let credentialStore = PublicLocalBootstrapCredentialStore {
                try await authentication.bootstrapCredential()
            }
            return configured(
                configuration: configuration,
                authentication: authentication,
                credentialStore: credentialStore,
                info: info,
                diagnosticLog: AuthenticationDiagnosticLogger.disabled,
                dependenciesAreInMemory: true
            )
        }
#endif
        guard let configuration = ProductConfigurationLoader.load(
            info: info,
            environment: environment
        ) else {
            return unavailable()
        }
        return production(configuration: configuration, info: info)
    }

    static func production(
        configuration: ProductConfiguration,
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        diagnosticLog: AuthenticationDiagnosticLogger =
            AuthenticationDiagnosticLogger.disabled
    ) -> ProductRuntime {
        let authentication = OpenAPIAuthenticationService(
            serverURL: configuration.apiBaseURL,
            diagnosticLog: diagnosticLog
        )
        let credentialStore = VolatileCredentialStore()
        return configured(
            configuration: configuration,
            authentication: authentication,
            credentialStore: credentialStore,
            info: info,
            diagnosticLog: diagnosticLog,
            dependenciesAreInMemory: false
        )
    }

    private static func configured(
        configuration: ProductConfiguration,
        authentication: any AuthenticationServing,
        credentialStore: any CredentialStoring,
        info: [String: Any],
        diagnosticLog: AuthenticationDiagnosticLogger,
        dependenciesAreInMemory: Bool
    ) -> ProductRuntime {
        _ = info
        diagnosticLog.recordApplicationLaunch()
        let relay = ProductSessionInvalidationRelay()
        let diagnosticRelay = ProductDiagnosticRelay()
        let session = SessionManager(
            service: authentication,
            store: credentialStore,
            invalidationHandler: { error in
                await relay.handle(error)
            }
        )
        let inputDeviceProvider = CoreAudioInputDeviceProvider()
        let customAIConfigurations = UserDefaultsCustomAIConfigurationStore()
        let customAISecrets = CustomAIKeychainSecretStore()
        let customAIResolver = CustomAIRuntimeConfigurationResolver(
            configurations: customAIConfigurations,
            secrets: customAISecrets
        )
        let customAIProvider = CustomAIProviderService()
        let dictionary = ProductDictionaryRuntime(
            store: DictionaryStore.production(),
            diagnostics: SystemDictionaryDiagnosticRecorder()
        )
        let customAIRouter = CustomAIDictationConnectionRouter(
            resolver: customAIResolver,
            asr: customAIProvider,
            optimizer: customAIProvider,
            cloud: {
                let token = try await AppDependencies.validatedAccessToken(
                    from: session
                )
                return DictationStreamingSession(
                    client: StreamingDictationClient(
                        transport: SpekWriteWebSocketTransport(
                            baseURL: configuration.realtimeBaseURL,
                            allowsInsecureLoopbackForTesting:
                                configuration.allowsInsecureLoopbackForTesting
                        )
                    ),
                    accessToken: token,
                    backend: .txchatCloud
                )
            }
        )
        let dictation = ProductionDictationRuntime.production(
            configuration: configuration,
            accessTokenProvider: session,
            targetHandler: AccessibilityTargetHandler(
                base: CoreAccessibilityTargetHandler(
                    diagnostics: diagnosticRelay
                )
            ),
            inputDeviceProvider: inputDeviceProvider,
            streamingSessionFactory: {
                try await customAIRouter.connection()
            },
            finalPreparer: ProductFinalTextPreparer(dictionary: dictionary),
            diagnosticRecorder: diagnosticRelay,
            sessionInvalidationHandler: { error in
                await relay.handle(error)
            }
        )
        let coordinator = ProductCoordinator(
            authentication: authentication,
            session: session,
            permissions: ProductPermissionService(),
            dictation: dictation,
            diagnosticLog: diagnosticLog,
            diagnosticRecorder: diagnosticRelay
        )
        relay.coordinator = coordinator
        let diagnostics = DiagnosticRuntime.production(
            configuration: configuration,
            productCoordinator: coordinator
        )
        diagnosticRelay.target = diagnostics
        let customAISettings = CustomAISettingsRuntime(
            configurations: customAIConfigurations,
            secrets: customAISecrets,
            tester: CustomAIProductionSettingsTester(
                asr: customAIProvider,
                optimizer: customAIProvider
            ),
            testDiagnostics: SystemCustomAITestDiagnosticRecorder(),
            languageProvider: { [weak coordinator] in
                coordinator?.language ?? .productDefault
            }
        )
        return ProductRuntime(
            coordinator: coordinator,
            dictation: dictation,
            diagnostics: diagnostics,
            customAISettings: customAISettings,
            dictionary: dictionary,
            launchAtLogin: LaunchAtLoginRuntime.production(),
            dependenciesAreInMemory: dependenciesAreInMemory
        )
    }


    static func unavailable() -> ProductRuntime {
        let session = ProductUnavailableSession()
        let dictation = ProductionDictationRuntime(
            dependencies: AppDependencies(
                accessTokenProvider: session,
                captureFactory: { ProductUnavailableCapture() },
                streamingFactory: { ProductUnavailableStream() },
                targetHandler: ProductUnavailableTarget(),
                finalPreparer: ProductFinalTextPreparer()
            ),
            hotkeyMonitor: ProductUnavailableHotkeyMonitor()
        )
        let coordinator = ProductCoordinator(
            authentication: ProductUnavailableAuthentication(),
            session: session,
            permissions: ProductUnavailablePermissions(),
            dictation: dictation
        )
        coordinator.showSetupUnavailable()
        return ProductRuntime(
            coordinator: coordinator,
            dictation: dictation,
            dependenciesAreInMemory: false
        )
    }

    func toggleDictation() async {
        await coordinator.toggleDictation()
    }

    func launch() async {
        guard !isTerminating else { return }
        if let launchTask {
            await launchTask.value
            return
        }
        let task = Task { @MainActor [weak self, diagnostics] in
            await diagnostics?.prepareForLaunch()
            guard
                !Task.isCancelled,
                let self,
                !self.isTerminating,
                self.coordinator.phase == .launching
            else {
                return
            }
            await self.coordinator.launch()
            guard !Task.isCancelled, !self.isTerminating else { return }
            self.synchronizeLaunchAtLogin()
        }
        launchTask = task
        await task.value
    }

    func presentShortcutEditor() {
        guard coordinator.phase == .ready else {
            return
        }
        isShortcutEditorPresented = true
    }

    func presentCustomAISettings() {
        guard coordinator.phase == .ready,
              !isTerminating,
              let customAISettings else {
            return
        }
        readySurface = .customAISettings
        customAISettings.beginEditing()
    }

    func presentDictionary() {
        guard coordinator.phase == .ready,
              !isTerminating,
              let dictionarySettings else {
            return
        }
        readySurface = .dictionary
        Task { await dictionarySettings.load() }
    }

    func logout() async {
        hotkeyLifecycleBlocked = true
        isShortcutEditorPresented = false
        dismissCustomAISettings()
        dismissDictionarySettings()
        stopHotkeyMonitoring()
        await coordinator.logout()
        hotkeyLifecycleBlocked = false
        synchronizeHotkey()
    }

    func terminate() async {
        if let terminationTask {
            await terminationTask.value
            return
        }
        isTerminating = true
        let launching = launchTask
        launching?.cancel()
        hotkeyLifecycleBlocked = true
        isShortcutEditorPresented = false
        dismissCustomAISettings()
        dismissDictionarySettings()
        stopHotkeyMonitoring()
        let task = Task { @MainActor [dictation, diagnostics, launching] in
            await dictation.terminate()
            await diagnostics?.terminate()
            await launching?.value
        }
        terminationTask = task
        await task.value
    }


    private func bindLifecycle() {
        coordinator.objectWillChange
            .sink { [weak self] _ in
                self?.suspendHotkeyForShortcutEditor()
                self?.objectWillChange.send()
                Task { @MainActor in
                    await Task.yield()
                    self?.synchronizeReadySurface()
                    self?.synchronizeHotkey()
                    self?.synchronizeLaunchAtLogin()
                    self?.synchronizeWindows()
                }
            }
            .store(in: &observations)
        dictation.objectWillChange
            .sink { [weak self] _ in
                self?.suspendHotkeyForShortcutEditor()
                Task { @MainActor in
                    await Task.yield()
                    self?.synchronizeWindows()
                    self?.objectWillChange.send()
                }
            }
            .store(in: &observations)
    }

    private func synchronizeHotkey() {
        let phaseAllowsMonitoring = coordinator.phase == .ready ||
            coordinator.phase == .onboarding(.voiceTest)
        let permissionAllowsMonitoring =
            coordinator.permissionSnapshot.accessibility == .ready &&
            coordinator.permissionSnapshot.hotkey == .ready
        let shouldMonitor = phaseAllowsMonitoring &&
            permissionAllowsMonitoring &&
            !isShortcutEditorPresented &&
            !hotkeyLifecycleBlocked
        if shouldMonitor, !hotkeyMonitoring {
            hotkeyMonitoring = dictation.startHotkeyMonitoring()
        } else if !shouldMonitor, hotkeyMonitoring {
            stopHotkeyMonitoring()
        }
    }

    private func synchronizeReadySurface() {
        guard coordinator.phase == .ready, !isTerminating else {
            dismissCustomAISettings()
            dismissDictionarySettings()
            return
        }
    }

    private func synchronizeLaunchAtLogin() {
        guard coordinator.phase == .ready,
              !isTerminating,
              launchAtLoginActivationTask == nil,
              let launchAtLogin else {
            return
        }
        launchAtLoginActivationTask = Task {
            await launchAtLogin.activateWhenReady()
        }
    }

    private func dismissCustomAISettings() {
        readySurface = .statusCenter
        customAISettings?.dismiss()
    }

    private func dismissDictionarySettings() {
        readySurface = .statusCenter
    }

    private func suspendHotkeyForShortcutEditor() {
        guard isShortcutEditorPresented else {
            return
        }
        stopHotkeyMonitoring()
    }

    private func stopHotkeyMonitoring() {
        dictation.stopHotkeyMonitoring()
        hotkeyMonitoring = false
    }

    private func synchronizeWindows() {
        let hudSnapshot = HUDSnapshot(
            state: dictation.state,
            shortcut: dictation.shortcut,
            audioLevel: dictation.audioLevel,
            usedVerbatimFallback: dictation.completionUsedVerbatimFallback,
            language: coordinator.language
        )
        if hudSnapshot != lastHUDSnapshot {
            overlayController.update(
                for: hudSnapshot.state,
                shortcut: hudSnapshot.shortcut,
                audioLevel: hudSnapshot.audioLevel,
                usedVerbatimFallback:
                    hudSnapshot.usedVerbatimFallback,
                language: coordinator.language
            )
            lastHUDSnapshot = hudSnapshot
        }
        switch dictation.state {
        case .resultFallback(let text):
            let snapshot = FallbackSnapshot(
                text: text,
                language: coordinator.language
            )
            guard presentedFallback != snapshot else {
                return
            }
            presentedFallback = snapshot
            fallbackController.show(
                text: text,
                language: coordinator.language,
                onRetry: { [weak self] in
                    await self?.coordinator.retryInsertion() ?? false
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.dictation.dismissResult()
                    }
                }
            )
        default:
            presentedFallback = nil
            fallbackController.hide()
        }
    }
}

private actor ProductUnavailableSession: ProductSessionManaging,
    DictationAccessTokenProviding
{
    func install(_ session: AuthenticatedSession) async throws {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }

    func restore() async throws -> AccountSummary? { nil }
    func logout() async throws {}

    func accessToken() async throws -> String {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }
}

private struct ProductUnavailableAuthentication: AuthenticationServing {
    func verifyEnrollment(
        phone: MainlandPhone,
        credential: EnrollmentCredential
    ) async throws -> AuthenticatedSession {
        _ = phone
        _ = credential
        throw unavailableError
    }

    func refresh(
        refreshToken: String,
        requestID: String
    ) async throws -> RefreshedSession {
        throw unavailableError
    }

    func currentAccount(
        accessToken: String
    ) async throws -> AccountSummary {
        throw unavailableError
    }

    func logout(accessToken: String) async throws {}

    private var unavailableError: AuthenticationServiceError {
        .serviceUnavailable(retryAfterSeconds: nil)
    }
}

@MainActor
private final class ProductUnavailablePermissions: ProductPermissionServing {
    private let value = ProductPermissionSnapshot(
        microphone: .needsSetup,
        accessibility: .needsSetup,
        hotkey: .needsSetup,
        voiceTest: .ready
    )

    func snapshot() async -> ProductPermissionSnapshot { value }
    func requestMicrophone() async -> ProductPermissionSnapshot { value }
    func requestAccessibility() async -> ProductPermissionSnapshot { value }
    func completeVoiceTest() async -> ProductPermissionSnapshot { value }
    func openSystemSettings(for permission: ProductPermissionKind) async {}
}

private actor ProductUnavailableCapture: DictationAudioCapturing {
    func start() async throws -> AsyncThrowingStream<Data, Error> {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }

    func stop() async {}
    func cancel() async {}
}

private actor ProductUnavailableStream: DictationStreamingServing {
    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }

    func send(audio: Data) async throws {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }

    func finish() async throws -> String {
        throw AuthenticationServiceError.serviceUnavailable(
            retryAfterSeconds: nil
        )
    }

    func cancel() async {}
}

@MainActor
private final class ProductUnavailableTarget: DictationTargetHandling {
    func capture() -> DictationTargetCaptureOutcome { .unavailable }
    func insert(_ text: String, into target: DictationTarget) -> Bool { false }
    func discard(_ target: DictationTarget) {}
}

@MainActor
private final class ProductUnavailableHotkeyMonitor: FunctionKeyMonitoring {
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        _ = shortcut
        _ = handler
        return .failed(.unavailable)
    }
    func stop() {}
}
