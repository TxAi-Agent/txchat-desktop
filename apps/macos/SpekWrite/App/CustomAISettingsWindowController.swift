import Foundation

@MainActor
final class CustomAISettingsRuntime {
    let coordinator: CustomAISettingsCoordinator
    private var loadTask: Task<Void, Never>?

    init(
        configurations: any CustomAIConfigurationStoring,
        secrets: any CustomAISecretStoring,
        tester: any CustomAIConfigurationTesting,
        testDiagnostics: any CustomAITestDiagnosticRecording =
            NullCustomAITestDiagnosticRecorder(),
        languageProvider: @escaping () -> TxChatLanguage
    ) {
        coordinator = CustomAISettingsCoordinator(
            configurations: configurations,
            secrets: secrets,
            tester: tester,
            testDiagnostics: testDiagnostics
        )
        _ = languageProvider
    }

    func setCloseHandler(
        _ close: @escaping CustomAISettingsCoordinator.CloseHandler
    ) {
        coordinator.setCloseHandler(close)
    }

    func beginEditing() {
        loadTask?.cancel()
        coordinator.cancelLoading()
        loadTask = Task { @MainActor [coordinator] in
            guard !Task.isCancelled else { return }
            await coordinator.load()
        }
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        coordinator.cancelLoading()
    }
}
