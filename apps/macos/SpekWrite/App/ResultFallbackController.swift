import AppKit
import SwiftUI

@MainActor
protocol PasteboardWriting: AnyObject {
    func writeString(_ value: String)
}

@MainActor
final class SystemPasteboardWriter: PasteboardWriting {
    func writeString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

@MainActor
private final class ResultFallbackWindowDelegate: NSObject,
    NSWindowDelegate
{
    var onClose: @MainActor () -> Void = {}

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class ResultFallbackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol ResultFallbackPresenting: AnyObject {
    func show(
        text: String,
        language: TxChatLanguage,
        onRetry: @escaping @MainActor () async -> Bool,
        onClose: @escaping @MainActor () -> Void
    )
    func hide()
}

@MainActor
final class ResultFallbackController: ResultFallbackPresenting {
    typealias RetryHandler = @MainActor () async -> Bool
    typealias CloseHandler = @MainActor () -> Void

    private let pasteboard: any PasteboardWriting
    private let activateApplication: @MainActor () -> Void
    private let windowDelegate = ResultFallbackWindowDelegate()
    private let retryPromptPanel: NSPanel
    private var window: NSWindow?
    private var text: String?
    private var language: TxChatLanguage = .productDefault
    private var onRetry: RetryHandler = { false }
    private var onClose: CloseHandler = {}

    init(
        pasteboard: any PasteboardWriting = SystemPasteboardWriter(),
        window: NSWindow? = nil,
        retryPromptPanel: NSPanel = DictationOverlayController.makePanel(),
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.pasteboard = pasteboard
        self.window = window
        self.retryPromptPanel = retryPromptPanel
        self.activateApplication = activateApplication
        windowDelegate.onClose = { [weak self] in
            self?.closeResult()
        }
        window?.delegate = windowDelegate
    }

    func show(
        text: String,
        language: TxChatLanguage = .productDefault,
        onRetry: @escaping RetryHandler = { false },
        onClose: @escaping CloseHandler = {}
    ) {
        retryPromptPanel.orderOut(nil)
        self.text = text
        self.language = language
        self.onRetry = onRetry
        self.onClose = onClose
        let window = window ?? Self.makeWindow()
        self.window = window
        window.delegate = windowDelegate
        window.contentViewController = NSHostingController(
            rootView: ResultFallbackView(
                text: text,
                retry: { [weak self] in await self?.retry() },
                copy: { [weak self] in self?.copy() },
                close: { [weak self] in self?.closeResult() }
            )
            .txChatLanguage(language)
        )
        window.center()
        activateApplication()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func retry() async {
        guard text != nil else {
            return
        }
        window?.orderOut(nil)
        showRetryPrompt()
    }

    func confirmRetry() async {
        guard text != nil, retryPromptPanel.isVisible else {
            return
        }
        let handler = onRetry
        showRetryInProgress()
        if await handler() {
            clearPayloadAndHide()
        } else if text != nil {
            retryPromptPanel.orderOut(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func copy() {
        guard let text else {
            return
        }
        pasteboard.writeString(text)
    }

    func closeResult() {
        guard text != nil else {
            return
        }
        let handler = onClose
        clearPayloadAndHide()
        handler()
    }

    func hide() {
        clearPayloadAndHide()
    }

    private func clearPayloadAndHide() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        retryPromptPanel.orderOut(nil)
        retryPromptPanel.contentViewController = nil
        text = nil
        onRetry = { false }
        onClose = {}
    }

    private func showRetryPrompt() {
        retryPromptPanel.contentViewController = NSHostingController(
            rootView: DictationOverlayView(
                presentation: OverlayPresentation(
                    title: language.select(
                        "重新写入 · 1/2",
                        "Reinsert · 1/2"
                    ),
                    detail: language.select(
                        "请点击可输入文字的位置",
                        "Click in a text field"
                    ),
                    actionLabel: language.select("写入", "Write"),
                    visualState: .inserting,
                    claimsInsertionCompleted: false
                ),
                action: { [weak self] in
                    Task { @MainActor in
                        await self?.confirmRetry()
                    }
                }
            )
            .txChatLanguage(language)
        )
        positionRetryPrompt()
        retryPromptPanel.orderFrontRegardless()
    }

    private func showRetryInProgress() {
        retryPromptPanel.contentViewController = NSHostingController(
            rootView: DictationOverlayView(
                presentation: OverlayPresentation(
                    title: language.select(
                        "重新写入 · 2/2",
                        "Reinsert · 2/2"
                    ),
                    detail: language.select(
                        "已定位输入位置，点击写入",
                        "Text field detected. Click Write."
                    ),
                    actionLabel: language.select("写入", "Write"),
                    visualState: .inserting,
                    claimsInsertionCompleted: false
                )
            )
            .txChatLanguage(language)
        )
    }

    private func positionRetryPrompt() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return
        }
        retryPromptPanel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - retryPromptPanel.frame.width / 2,
                y: visibleFrame.minY + 52
            )
        )
    }

    static func makeWindow() -> NSWindow {
        let window = ResultFallbackWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isExcludedFromWindowsMenu = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 300)
        window.maxSize = NSSize(width: 480, height: 300)
        return window
    }
}
