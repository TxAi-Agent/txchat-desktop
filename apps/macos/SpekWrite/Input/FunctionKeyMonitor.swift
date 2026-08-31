import Foundation

@MainActor
protocol FunctionKeyMonitoring: ProductShortcutMonitoring {}

@MainActor
final class FunctionKeyMonitor: FunctionKeyMonitoring {
    private let base: any ProductShortcutMonitoring

    init(base: CoreHotkeyMonitor = CoreHotkeyMonitor()) {
        self.base = ProductShortcutMonitor(
            functionRegistrar: CoreProductFunctionShortcutRegistrar(
                monitor: base
            )
        )
    }

    @discardableResult
    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        base.start(shortcut: shortcut, handler: handler)
    }

    func stop() {
        base.stop()
    }
}
