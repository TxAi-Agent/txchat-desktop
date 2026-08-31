import AppKit
import SwiftUI

@MainActor
private final class DiagnosticReportWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
struct DiagnosticReportControllerActions {
    let notNow: () async -> Bool
    let send: () -> Void
    let retry: () -> Void
    let done: () -> Void

    static let noOp = Self(
        notNow: { false },
        send: {},
        retry: {},
        done: {}
    )
}

@MainActor
final class DiagnosticReportWindowController {
    private(set) var window: NSWindow?
    private(set) var presentedState: DiagnosticReportViewState?

    private let languageProvider: () -> TxChatLanguage
    private let actions: DiagnosticReportControllerActions
    private let ordersWindow: Bool
    private let initialPresentationGate: ProductInitialPresentationGate
    private let activateApplication: () -> Void
    private let orderWindow: (NSWindow) -> Void

    init(
        languageProvider: @escaping () -> TxChatLanguage,
        actions: DiagnosticReportControllerActions,
        ordersWindow: Bool = true,
        initialPresentationGate: ProductInitialPresentationGate = .production,
        activateApplication: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        orderWindow: @escaping (NSWindow) -> Void = { window in
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    ) {
        self.languageProvider = languageProvider
        self.actions = actions
        self.ordersWindow = ordersWindow
        self.initialPresentationGate = initialPresentationGate
        self.activateApplication = activateApplication
        self.orderWindow = orderWindow
        initialPresentationGate.whenAllowed { [weak self] in
            self?.orderPresentedWindowIfNeeded()
        }
    }

    func present(_ state: DiagnosticReportViewState?) {
        presentedState = state
        guard let state else {
            window?.orderOut(nil)
            return
        }
        let window = window ?? Self.makeWindow()
        self.window = window
        window.contentViewController = NSHostingController(
            rootView: DiagnosticReportView(
                state: state,
                notNow: actions.notNow,
                send: actions.send,
                retry: actions.retry,
                done: actions.done
            )
            .txChatLanguage(languageProvider())
        )
        Self.lockSize(of: window)
        orderPresentedWindowIfNeeded()
    }

    private func orderPresentedWindowIfNeeded() {
        guard ordersWindow,
              initialPresentationGate.allowsPresentation,
              presentedState != nil,
              let window
        else {
            return
        }
        if !window.isVisible { window.center() }
        activateApplication()
        orderWindow(window)
    }

    private static func makeWindow() -> NSWindow {
        let size = CGSize(width: 480, height: 280)
        let window = DiagnosticReportWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        lockSize(of: window)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private static func lockSize(of window: NSWindow) {
        let size = CGSize(width: 480, height: 280)
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.minSize = size
        window.maxSize = size
    }
}
