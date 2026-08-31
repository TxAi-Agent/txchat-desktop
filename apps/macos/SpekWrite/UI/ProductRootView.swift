import AppKit
import SwiftUI

struct ProductRootView: View {
    @ObservedObject var coordinator: ProductCoordinator
    let launch: () async -> Void
    let readySurface: ProductReadySurface
    let customAISettingsCoordinator: CustomAISettingsCoordinator?
    let dictionarySettingsCoordinator: DictionarySettingsCoordinator?
    let showCustomAISettings: () -> Void
    let showDictionary: () -> Void
    let showShortcutEditor: () -> Void
    let logout: () async -> Void
    private let textDocuments: BundledTxChatTextDocumentRepository
    @State private var selectedDocument: TxChatTextDocument?

    init(
        coordinator: ProductCoordinator,
        launch: (() async -> Void)? = nil,
        readySurface: ProductReadySurface = .statusCenter,
        customAISettingsCoordinator: CustomAISettingsCoordinator? = nil,
        dictionarySettingsCoordinator: DictionarySettingsCoordinator? = nil,
        showCustomAISettings: @escaping () -> Void = {},
        showDictionary: @escaping () -> Void = {},
        showShortcutEditor: @escaping () -> Void = {},
        logout: @escaping () async -> Void = {},
        textDocuments: BundledTxChatTextDocumentRepository =
            BundledTxChatTextDocumentRepository()
    ) {
        self.coordinator = coordinator
        self.launch = launch ?? {
            if coordinator.phase == .launching {
                await coordinator.launch()
            }
        }
        self.readySurface = readySurface
        self.customAISettingsCoordinator = customAISettingsCoordinator
        self.dictionarySettingsCoordinator = dictionarySettingsCoordinator
        self.showCustomAISettings = showCustomAISettings
        self.showDictionary = showDictionary
        self.showShortcutEditor = showShortcutEditor
        self.logout = logout
        self.textDocuments = textDocuments
        _selectedDocument = State(initialValue: nil)
    }

    var body: some View {
        Group {
            switch coordinator.phase {
            case .launching:
                loadingView
            case .signedOut:
                LoginView(
                    phone: $coordinator.phone,
                    verificationCode: $coordinator.verificationCode,
                    termsAccepted: $coordinator.termsAccepted,
                    presentation: coordinator.loginPresentation,
                    resendSecondsRemaining:
                        coordinator.resendSecondsRemaining,
                    isSMSRequestLocked:
                        coordinator.isSMSRequestLocked,
                    verificationCodeFocusGeneration:
                        coordinator.verificationCodeFocusGeneration,
                    isRequestingSMSCode:
                        coordinator.isRequestingSMSCode,
                    isVerifyingSMSCode:
                        coordinator.isVerifyingSMSCode,
                    shortcutDisplayName: coordinator.shortcutDisplayName,
                    requestSMSCode: coordinator.requestSMSCode,
                    verifySMSCode: coordinator.verifySMSCode,
                    toggleLanguage: coordinator.toggleLanguage,
                    showDocument: presentDocument
                )
            case .onboarding(let step):
                OnboardingView(
                    presentation: ProductPresentation.onboarding(
                        step: step,
                        shortcut: coordinator.currentShortcut,
                        permissions: coordinator.permissionSnapshot,
                        language: coordinator.language
                    ),
                    message: coordinator.formMessage,
                    accountLabel: TxChatAccountDisplay.maskedPhone(
                        coordinator.account?.maskedPhone ?? ""
                    ),
                    voiceTestState: coordinator.voiceTestState,
                    voiceTestResultText: coordinator.voiceTestResultText,
                    performAction: coordinator.performOnboardingAction,
                    testVoiceInput: coordinator.toggleDictation,
                    skipVoiceTest: coordinator.skipVoiceTest,
                    completeVoiceTest: coordinator.completeVoiceTest,
                    logout: logout,
                    toggleLanguage: coordinator.toggleLanguage
                )
            case .ready:
                readyView
            case .sessionInterruption(let interruption):
                SessionInterruptionView(
                    presentation: ProductPresentation.sessionInterruption(
                        interruption,
                        language: coordinator.language
                    ),
                    beginReauthentication:
                        coordinator.beginReauthentication
                )
            case .setupUnavailable:
                setupUnavailableView
            }
        }
        .task {
            await launch()
        }
        .task(id: permissionObservationKey) {
            guard permissionObservationKey else {
                return
            }
            while !Task.isCancelled {
                await coordinator.refreshPermissions()
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        .task(
            id: coordinator.resendSecondsRemaining > 0 ||
                coordinator.verificationRetrySecondsRemaining > 0 ||
                coordinator.isSMSRequestLocked
        ) {
            guard coordinator.phase == .signedOut,
                  coordinator.resendSecondsRemaining > 0 ||
                  coordinator.verificationRetrySecondsRemaining > 0 ||
                  coordinator.isSMSRequestLocked else {
                return
            }
            await coordinator.runLoginCountdown()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { await coordinator.refreshPermissions() }
        }
        .sheet(
            isPresented: Binding(
                get: { coordinator.isPermissionRepairPresented },
                set: { presented in
                    if !presented {
                        coordinator.dismissPermissionRepair()
                    }
                }
            )
        ) {
            if let presentation = coordinator.permissionRepairPresentation {
                PermissionRepairView(
                    presentation: presentation,
                    cancel: coordinator.dismissPermissionRepair,
                    repairPermission: {
                        await coordinator.repairPermission(
                            presentation.permission
                        )
                    },
                    recheckPermission: {
                        await coordinator.refreshPermissions()
                    }
                )
                .txChatLanguage(coordinator.language)
            }
        }
        .sheet(item: $selectedDocument) { document in
            TxChatTextReaderView(
                document: document,
                close: { selectedDocument = nil }
            )
            .txChatLanguage(document.language)
        }
    }

    @ViewBuilder
    private var readyView: some View {
        switch readySurface {
        case .statusCenter:
            productHomeView
        case .customAISettings:
            if let customAISettingsCoordinator {
                CustomAISettingsView(
                    coordinator: customAISettingsCoordinator
                )
            } else {
                productHomeView
            }
        case .dictionary:
            if let dictionarySettingsCoordinator {
                DictionarySettingsView(
                    coordinator: dictionarySettingsCoordinator
                )
            } else {
                productHomeView
            }
        }
    }

    private var productHomeView: some View {
        ProductHomeView(
                    presentation: coordinator.homePresentation,
                    accountLabel: TxChatAccountDisplay.maskedPhone(
                        coordinator.account?.maskedPhone ?? ""
                    ),
                    setMode: { mode in coordinator.setMode(mode) },
                    testVoiceInput: coordinator.toggleDictation,
                    showCustomAISettings: showCustomAISettings,
                    showDictionary: showDictionary,
                    showShortcutEditor: showShortcutEditor,
                    recalibrateMicrophone:
                        coordinator.recalibrateMicrophone,
                    repairPermissions:
                        coordinator.presentPermissionRepair,
                    logout: logout,
                    toggleLanguage: coordinator.toggleLanguage,
                    showDocument: presentDocument
                )
    }

    private var permissionObservationKey: Bool {
        switch coordinator.phase {
        case .onboarding:
            return true
        case .ready:
            return true
        default:
            return coordinator.isPermissionRepairPresented
        }
    }

    private func presentDocument(_ kind: TxChatTextDocumentKind) {
        selectedDocument = try? textDocuments.document(
            kind: kind,
            language: coordinator.language
        )
    }

    private var loadingView: some View {
        VStack(spacing: TxChatTheme.Spacing.large) {
            TxChatBrandMark(size: 72)
            ProgressView()
            Text(
                coordinator.language.select(
                    "正在准备 TxChat…",
                    "Preparing TxChat…"
                )
            )
                .font(TxChatTheme.body)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        .background(TxChatTheme.Palette.canvas)
    }

    private var setupUnavailableView: some View {
        VStack(spacing: TxChatTheme.Spacing.large) {
            TxChatBrandMark(size: 72)
            Text(
                coordinator.language.select(
                    "服务尚未配置",
                    "Service Not Configured"
                )
            )
                .font(TxChatTheme.title)
            Text(
                coordinator.language.select(
                    "请完成 TxChat 云服务地址配置后重新打开应用。",
                    "Configure the TxChat service address, then reopen the app."
                )
            )
                .font(TxChatTheme.body)
                .foregroundStyle(TxChatTheme.Palette.secondaryText)
        }
        .frame(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        .background(TxChatTheme.Palette.canvas)
        .accessibilityIdentifier("setup.unavailable")
    }
}
