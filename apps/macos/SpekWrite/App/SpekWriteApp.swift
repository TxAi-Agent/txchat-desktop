import AppKit
import SwiftUI

enum ProductInitialWindowDisposition: Equatable, Sendable {
    case foreground
    case background
}

enum ProductInitialWindowPolicy {
    static func disposition(
        wasLaunchedAsLoginItem: Bool,
        forceForeground: Bool
    ) -> ProductInitialWindowDisposition {
        if wasLaunchedAsLoginItem, !forceForeground {
            return .background
        }
        return .foreground
    }
}

@MainActor
final class ProductInitialPresentationGate {
    static let production = ProductInitialPresentationGate()

    private(set) var allowsPresentation = false
    private var resolved = false
    private var waitingHandlers: [() -> Void] = []

    func resolve(_ disposition: ProductInitialWindowDisposition) {
        guard !resolved else { return }
        resolved = true
        if disposition == .foreground {
            allowPresentations()
        }
    }

    func whenAllowed(_ handler: @escaping () -> Void) {
        if allowsPresentation {
            handler()
        } else {
            waitingHandlers.append(handler)
        }
    }

    func allowPresentations() {
        guard !allowsPresentation else { return }
        allowsPresentation = true
        let handlers = waitingHandlers
        waitingHandlers.removeAll()
        handlers.forEach { $0() }
    }
}

enum ProductLaunchEvent {
    static func wasLaunchedAsLoginItem(
        _ event: NSAppleEventDescriptor?
    ) -> Bool {
        guard event?.eventClass == AEEventClass(kCoreEventClass),
              event?.eventID == AEEventID(kAEOpenApplication)
        else {
            return false
        }
        return event?.paramDescriptor(
            forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
        ) != nil
    }
}

@MainActor
final class ProductInitialWindowCoordinator {
    private let handle: (ProductInitialWindowDisposition) -> Void
    private var launchedAsLoginItem: Bool?
    private var forceForeground: Bool?
    private var handled = false

    init(handle: @escaping (ProductInitialWindowDisposition) -> Void) {
        self.handle = handle
    }

    func applicationDidFinishLaunching(wasLaunchedAsLoginItem: Bool) {
        guard launchedAsLoginItem == nil else { return }
        launchedAsLoginItem = wasLaunchedAsLoginItem
        handleIfReady()
    }

    func mainWindowDidAppear(forceForeground: Bool) {
        guard self.forceForeground == nil else { return }
        self.forceForeground = forceForeground
        handleIfReady()
    }

    func explicitForegroundRequested() {
        guard !handled else { return }
        forceForeground = true
        handleIfReady()
    }

    private func handleIfReady() {
        guard !handled,
              let launchedAsLoginItem,
              let forceForeground
        else {
            return
        }
        handled = true
        handle(
            ProductInitialWindowPolicy.disposition(
                wasLaunchedAsLoginItem: launchedAsLoginItem,
                forceForeground: forceForeground
            )
        )
    }
}

@MainActor
final class SpekWriteAppDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (@MainActor () async -> Void)?
    var openMainWindowHandler: (@MainActor () -> Void)?
    var replyToTermination: (NSApplication, Bool) -> Void = {
        application, shouldTerminate in
        application.reply(toApplicationShouldTerminate: shouldTerminate)
    }
    private var terminationInFlight = false
    private var terminationCompleted = false
    private lazy var initialWindowCoordinator =
        ProductInitialWindowCoordinator { [weak self] disposition in
            self?.applyInitialWindowDisposition(disposition)
        }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        let event = NSAppleEventManager.shared().currentAppleEvent
        initialWindowCoordinator.applicationDidFinishLaunching(
            wasLaunchedAsLoginItem:
                ProductLaunchEvent.wasLaunchedAsLoginItem(event)
        )
    }

    func handleInitialProductMainWindowAppearance(
        forceForeground: Bool = false
    ) {
        initialWindowCoordinator.mainWindowDidAppear(
            forceForeground: forceForeground
        )
    }

    func requestForegroundPresentation() {
        initialWindowCoordinator.explicitForegroundRequested()
        ProductInitialPresentationGate.production.allowPresentations()
    }

    @discardableResult
    func openMainWindow() -> Bool {
        requestForegroundPresentation()
        guard let openMainWindowHandler else { return false }
        openMainWindowHandler()
        return true
    }

    private func applyInitialWindowDisposition(
        _ disposition: ProductInitialWindowDisposition
    ) {
        ProductInitialPresentationGate.production.resolve(disposition)
        switch disposition {
        case .foreground:
            NSApp.activate(ignoringOtherApps: true)
        case .background:
            for window in NSApp.windows where window.title == "TxChat" {
                window.orderOut(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        _ = sender
        _ = flag
        return openMainWindow()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if terminationCompleted {
            return .terminateNow
        }
        if terminationInFlight {
            return .terminateLater
        }
        guard let terminationHandler else {
            return .terminateNow
        }
        terminationInFlight = true
        Task { @MainActor in
            await terminationHandler()
            terminationInFlight = false
            terminationCompleted = true
            replyToTermination(sender, true)
        }
        return .terminateLater
    }
}

@MainActor
enum ProductApplicationLifecycle {
    static func installTerminationHandler(
        runtime: ProductRuntime,
        appDelegate: SpekWriteAppDelegate
    ) {
        appDelegate.terminationHandler = {
            await runtime.terminate()
        }
    }

    static func launch(
        runtime: ProductRuntime,
        appDelegate: SpekWriteAppDelegate
    ) async {
        installTerminationHandler(
            runtime: runtime,
            appDelegate: appDelegate
        )
        await runtime.launch()
    }
}

@main
struct SpekWriteApp: App {
    @NSApplicationDelegateAdaptor(SpekWriteAppDelegate.self)
    private var appDelegate
    @StateObject private var runtimeStore: SpekWriteRuntimeStore
    private let route: AppLaunchRoute
    private let productUISelfTestRequested: Bool

    init() {
        _ = try? TxChatFontRegistry.registerBundledFont()
        let environment = ProcessInfo.processInfo.environment
        let resolvedRoute = AppLaunchRoute.resolve(environment: environment)
        route = resolvedRoute
        productUISelfTestRequested = false
        _runtimeStore = StateObject(
            wrappedValue: SpekWriteRuntimeStore(
                route: resolvedRoute,
                environment: environment
            )
        )
    }

    var body: some Scene {
        Window("TxChat", id: "main") {
            ProductApplicationView(
                runtime: runtimeStore.requiredProductRuntime,
                appDelegate: appDelegate,
                selfTestRequested: productUISelfTestRequested
            )
        }
        .defaultSize(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowContentHeight
        )
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            ProductMenuView(
                runtime: runtimeStore.requiredProductRuntime,
                appDelegate: appDelegate
            )
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)
    }

}

@MainActor
private final class SpekWriteRuntimeStore: ObservableObject {
    let productRuntime: ProductRuntime?

    init(route: AppLaunchRoute, environment: [String: String]) {
        if route.requiresProductRuntime {
            productRuntime = ProductRuntime.bootstrap(environment: environment)
        } else {
            productRuntime = nil
        }
    }

    var requiredProductRuntime: ProductRuntime {
        guard let productRuntime else {
            preconditionFailure("Product runtime requested for an isolated route")
        }
        return productRuntime
    }
}


private struct ProductApplicationView: View {
    @ObservedObject var runtime: ProductRuntime
    @Environment(\.openWindow) private var openWindow
    let appDelegate: SpekWriteAppDelegate
    let selfTestRequested: Bool
    @State private var didRunSelfTest = false

    var body: some View {
        ProductRootView(
            coordinator: runtime.coordinator,
            launch: {
                await ProductApplicationLifecycle.launch(
                    runtime: runtime,
                    appDelegate: appDelegate
                )
            },
            readySurface: runtime.readySurface,
            customAISettingsCoordinator:
                runtime.customAISettings?.coordinator,
            dictionarySettingsCoordinator: runtime.dictionarySettings,
            showCustomAISettings: runtime.presentCustomAISettings,
            showDictionary: runtime.presentDictionary,
            showShortcutEditor: runtime.presentShortcutEditor,
            logout: runtime.logout
        )
            .txChatLanguage(runtime.coordinator.language)
            .ignoresSafeArea()
            .frame(
                width: TxChatTheme.Layout.windowWidth,
                height: TxChatTheme.Layout.windowContentHeight,
                alignment: .bottom
            )
            .background {
                TxChatWindowAttachment()
                    .frame(width: 0, height: 0)
            }
            .sheet(isPresented: $runtime.isShortcutEditorPresented) {
                ProductShortcutEditorView(
                    current: runtime.dictation.shortcut,
                    updateShortcut: runtime.coordinator.updateShortcut
                )
                .txChatLanguage(runtime.coordinator.language)
            }
            .onAppear {
                appDelegate.openMainWindowHandler = {
                    ProductMainWindowOpener(
                        openWindow: { _ in openWindow(id: "main") },
                        activateApplication: {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    ).openMainWindow()
                }
                appDelegate.handleInitialProductMainWindowAppearance(
                    forceForeground: selfTestRequested
                )
                ProductApplicationLifecycle.installTerminationHandler(
                    runtime: runtime,
                    appDelegate: appDelegate
                )
            }
            .task {
            }
    }

}

@MainActor
struct ProductMainWindowOpener {
    let openWindow: (String) -> Void
    let activateApplication: () -> Void
    var allowInitialPresentations: () -> Void = {}

    func openMainWindow() {
        allowInitialPresentations()
        openWindow("main")
        activateApplication()
    }
}

private struct ProductMenuView: View {
    @ObservedObject var runtime: ProductRuntime
    let appDelegate: SpekWriteAppDelegate

    var body: some View {
        ProductMenuPanelView(
            presentation: presentation,
            openApp: openMainWindow,
            quit: { NSApp.terminate(nil) }
        )
        .txChatLanguage(runtime.coordinator.language)
    }

    private var presentation: ProductMenuPresentation {
        ProductPresentation.menu(
            phase: runtime.coordinator.phase,
            readyStatus: runtime.coordinator.homePresentation.status,
            dictation: runtime.dictation.state,
            language: runtime.coordinator.language
        )
    }

    private func openMainWindow() {
        appDelegate.openMainWindow()
    }
}
