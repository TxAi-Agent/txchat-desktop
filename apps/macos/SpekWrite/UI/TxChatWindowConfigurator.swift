import AppKit
import ObjectiveC
import SwiftUI

nonisolated(unsafe) private var txChatFrameEnforcerAssociationKey: UInt8 = 0

@MainActor
enum TxChatWindowFrameEnforcerAssociation {
    static func retained(
        for window: NSWindow
    ) -> TxChatWindowFrameEnforcer? {
        objc_getAssociatedObject(
            window,
            &txChatFrameEnforcerAssociationKey
        ) as? TxChatWindowFrameEnforcer
    }

    static func retain(
        _ enforcer: TxChatWindowFrameEnforcer,
        for window: NSWindow
    ) {
        objc_setAssociatedObject(
            window,
            &txChatFrameEnforcerAssociationKey,
            enforcer,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func release(
        _ enforcer: TxChatWindowFrameEnforcer,
        for window: NSWindow
    ) {
        guard let retained = retained(for: window),
            retained === enforcer
        else {
            return
        }
        objc_setAssociatedObject(
            window,
            &txChatFrameEnforcerAssociationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

@MainActor
enum TxChatWindowConfigurator {
    static func configure(_ window: NSWindow) {
        applyContract(to: window)
    }

    static func restoreContract(_ window: NSWindow) {
        applyContract(to: window)
    }

    private static func applyContract(to window: NSWindow) {
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.styleMask.remove(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        let zoomButton = window.standardWindowButton(.zoomButton)
        zoomButton?.isEnabled = false
        zoomButton?.isHidden = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = NSColor(TxChatTheme.Palette.canvas)
        let fixedSize = NSSize(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        var fixedFrame = window.frame
        fixedFrame.origin.y += fixedFrame.height - fixedSize.height
        fixedFrame.size = fixedSize
        window.setFrame(fixedFrame, display: false)
        window.minSize = fixedSize
        window.maxSize = fixedSize
    }
}

@MainActor
final class TxChatWindowFrameEnforcer: NSObject {
    private weak var window: NSWindow?
    private var enforcementScheduled = false
    private var configuredAtLeastOnce = false

    init(window: NSWindow) {
        self.window = window
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        scheduleEnforcement()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else {
            scheduleEnforcement()
            return
        }
        NotificationCenter.default.removeObserver(self)
        self.window = window
        configuredAtLeastOnce = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        scheduleEnforcement()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        scheduleEnforcement()
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        scheduleEnforcement()
    }

    private func scheduleEnforcement() {
        guard !enforcementScheduled else { return }
        enforcementScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.enforcementScheduled = false
            self.enforceNow()
        }
    }

    private func enforceNow() {
        guard let window else { return }
        let fixedSize = NSSize(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        guard !configuredAtLeastOnce ||
            window.frame.size != fixedSize ||
            window.minSize != fixedSize ||
            window.maxSize != fixedSize ||
            window.ignoresMouseEvents ||
            !window.acceptsMouseMovedEvents ||
            window.styleMask.contains(.resizable) ||
            window.collectionBehavior.contains(.fullScreenPrimary) ||
            window.collectionBehavior.contains(.fullScreenAuxiliary) ||
            window.standardWindowButton(.zoomButton)?.isEnabled == true ||
            window.standardWindowButton(.zoomButton)?.isHidden == false ||
            window.isMovableByWindowBackground ||
            window.backgroundColor != NSColor(TxChatTheme.Palette.canvas)
        else {
            return
        }
        if configuredAtLeastOnce {
            TxChatWindowConfigurator.restoreContract(window)
        } else {
            configuredAtLeastOnce = true
            TxChatWindowConfigurator.configure(window)
        }
    }
}

@MainActor
struct TxChatWindowAttachment: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        var enforcer: TxChatWindowFrameEnforcer?
        private weak var attachedWindow: NSWindow?

        func attach(to window: NSWindow) {
            if let enforcer, let attachedWindow,
               attachedWindow !== window
            {
                TxChatWindowFrameEnforcerAssociation.release(
                    enforcer,
                    for: attachedWindow
                )
            }
            if let enforcer {
                enforcer.attach(to: window)
            } else {
                enforcer = TxChatWindowFrameEnforcer(window: window)
            }
            attachedWindow = window
            if let enforcer {
                TxChatWindowFrameEnforcerAssociation.retain(
                    enforcer,
                    for: window
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        WindowProbeView { window in
            context.coordinator.attach(to: window)
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else {
            return
        }
        context.coordinator.attach(to: window)
    }

    private final class WindowProbeView: NSView {
        let attach: (NSWindow) -> Void

        init(attach: @escaping (NSWindow) -> Void) {
            self.attach = attach
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                return
            }
            attach(window)
        }
    }
}
