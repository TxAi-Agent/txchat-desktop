import AppKit
import XCTest
@testable import SpekWrite

@MainActor
private final class ProductPasteboardFake: PasteboardWriting {
    private(set) var values: [String] = []

    func writeString(_ value: String) {
        values.append(value)
    }
}

@MainActor
private class ProductTestWindow: NSWindow {
    private var testVisible = false
    private(set) var makeKeyCallCount = 0
    private(set) var orderFrontRegardlessCallCount = 0

    init(width: CGFloat = 480, height: CGFloat = 300) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
    }

    override var isVisible: Bool { testVisible }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyCallCount += 1
        testVisible = true
    }

    override func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
        testVisible = true
    }

    override func orderOut(_ sender: Any?) {
        testVisible = false
    }

    override func center() {}

    override func close() {
        testVisible = false
        delegate?.windowWillClose?(
            Notification(name: NSWindow.willCloseNotification, object: self)
        )
    }
}

@MainActor
private final class ProductTestPanel: NSPanel {
    private var testVisible = false
    private(set) var orderFrontCallCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override var isVisible: Bool { testVisible }

    override func orderFrontRegardless() {
        orderFrontCallCount += 1
        testVisible = true
    }

    override func orderOut(_ sender: Any?) {
        testVisible = false
    }

    override func setFrameOrigin(_ point: NSPoint) {}
}

private actor OverlayDismissClock: DictationClock {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var recordedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDurations.append(duration)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
    }

    func waitUntilSleeping(_ count: Int = 1) async -> Bool {
        for _ in 0..<200 {
            if continuations.count >= count {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func durations() -> [Duration] {
        recordedDurations
    }

    func advance() {
        guard !continuations.isEmpty else {
            return
        }
        continuations.removeFirst().resume()
    }
}

private actor CancellationDecisionGate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilPending() async -> Bool {
        for _ in 0..<200 {
            if continuation != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func resolve(_ accepted: Bool) {
        continuation?.resume(returning: accepted)
        continuation = nil
    }
}

@MainActor
private final class ProductMainWindowOpenTargetFake {
    private(set) var requestedIDs: [String] = []
    private(set) var existingWindowIDs: Set<String> = []
    private(set) var activationCount = 0

    func open(id: String) {
        requestedIDs.append(id)
        existingWindowIDs.insert(id)
    }

    func activate() {
        activationCount += 1
    }
}

@MainActor
final class ProductWindowControllerTests: XCTestCase {
    func testTwentyMainWindowOpenRequestsReuseOneIdentityAndActivate() {
        let target = ProductMainWindowOpenTargetFake()
        let opener = ProductMainWindowOpener(
            openWindow: target.open,
            activateApplication: target.activate
        )

        for _ in 0..<20 {
            opener.openMainWindow()
        }

        XCTAssertEqual(target.requestedIDs, Array(repeating: "main", count: 20))
        XCTAssertEqual(target.existingWindowIDs, ["main"])
        XCTAssertEqual(target.activationCount, 20)
    }

    func testMainWindowOpenAllowsPendingPresentationBeforeOpening() {
        var trace: [String] = []
        let opener = ProductMainWindowOpener(
            openWindow: { _ in trace.append("open") },
            activateApplication: { trace.append("activate") },
            allowInitialPresentations: { trace.append("allow") }
        )

        opener.openMainWindow()

        XCTAssertEqual(trace, ["allow", "open", "activate"])
    }

    func testMainWindowConfiguratorRestoresInteractionWithoutOrderingFront() {
        let window = ProductTestWindow(width: 300, height: 200)
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.isMovableByWindowBackground = true

        TxChatWindowConfigurator.configure(window)

        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.acceptsMouseMovedEvents)
        XCTAssertFalse(
            window.isMovableByWindowBackground,
            "content-wide window dragging must not intercept SwiftUI buttons"
        )
        XCTAssertEqual(
            window.backgroundColor,
            NSColor(TxChatTheme.Palette.canvas),
            "native title/layout regions must use the Figma canvas color"
        )
        XCTAssertEqual(window.makeKeyCallCount, 0)
        XCTAssertFalse(window.isVisible)
    }

    func testFrameEnforcerConfiguresAnInitiallyCorrectSizedWindow() async {
        let window = ProductTestWindow(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        window.setFrame(
            NSRect(
                x: 0,
                y: 0,
                width: TxChatTheme.Layout.windowWidth,
                height: TxChatTheme.Layout.windowHeight
            ),
            display: false
        )
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        let enforcer = TxChatWindowFrameEnforcer(window: window)

        for _ in 0..<20 where window.ignoresMouseEvents {
            await Task.yield()
        }

        XCTAssertEqual(window.makeKeyCallCount, 0)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.acceptsMouseMovedEvents)
        withExtendedLifetime(enforcer) {}
    }

    func testFrameEnforcerReconfiguresAReplacementWindow() async {
        let first = ProductTestWindow(width: 300, height: 200)
        let enforcer = TxChatWindowFrameEnforcer(window: first)
        for _ in 0..<20 where first.minSize.width != 720 {
            await Task.yield()
        }
        XCTAssertEqual(first.makeKeyCallCount, 0)

        let replacement = ProductTestWindow()
        replacement.setFrame(
            NSRect(
                x: 0,
                y: 0,
                width: TxChatTheme.Layout.windowWidth,
                height: TxChatTheme.Layout.windowHeight
            ),
            display: false
        )
        replacement.ignoresMouseEvents = false
        replacement.acceptsMouseMovedEvents = true

        enforcer.attach(to: replacement)
        for _ in 0..<20 where replacement.minSize.width != 720 {
            await Task.yield()
        }

        XCTAssertEqual(replacement.makeKeyCallCount, 0)
    }

    func testBackgroundWindowStaysHiddenAfterDeferredFirstEnforcement()
        async
    {
        let window = ProductTestWindow(width: 300, height: 200)
        window.makeKeyAndOrderFront(nil)
        let foregroundCallCount = window.makeKeyCallCount
        let enforcer = TxChatWindowFrameEnforcer(window: window)

        window.orderOut(nil)
        for _ in 0..<20 where window.minSize.width != 720 {
            await Task.yield()
        }

        XCTAssertEqual(window.makeKeyCallCount, foregroundCallCount)
        XCTAssertFalse(window.isVisible)
        withExtendedLifetime(enforcer) {}
    }

    func testFrameEnforcerRestoresConstraintsAfterWindowUpdate() {
        let fixedSize = NSSize(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        let window = ProductTestWindow(
            width: fixedSize.width,
            height: fixedSize.height
        )
        window.setFrame(
            NSRect(origin: .zero, size: fixedSize),
            display: false
        )
        let enforcer = TxChatWindowFrameEnforcer(window: window)

        let initialDeadline = Date().addingTimeInterval(0.25)
        while window.makeKeyCallCount == 0, Date() < initialDeadline {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }
        XCTAssertEqual(window.minSize, fixedSize)
        XCTAssertEqual(window.maxSize, fixedSize)

        window.minSize = NSSize(width: 0, height: 0)
        window.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = false
        NotificationCenter.default.post(
            name: NSWindow.didUpdateNotification,
            object: window
        )

        let updateDeadline = Date().addingTimeInterval(0.25)
        while (
            window.minSize != fixedSize ||
                window.maxSize != fixedSize ||
                window.styleMask.contains(.resizable) ||
                window.collectionBehavior.contains(.fullScreenPrimary) ||
                window.standardWindowButton(.zoomButton)?.isEnabled == true ||
                window.standardWindowButton(.zoomButton)?.isHidden == false
        ),
              Date() < updateDeadline
        {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }

        XCTAssertEqual(window.minSize, fixedSize)
        XCTAssertEqual(window.maxSize, fixedSize)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(
            window.collectionBehavior.contains(.fullScreenPrimary)
        )
        XCTAssertEqual(
            window.standardWindowButton(.zoomButton)?.isEnabled,
            false
        )
        XCTAssertEqual(
            window.standardWindowButton(.zoomButton)?.isHidden,
            true
        )
        XCTAssertEqual(
            window.makeKeyCallCount,
            0,
            "late SwiftUI window updates must restore the contract without " +
                "stealing focus again"
        )
        withExtendedLifetime(enforcer) {}
    }

    func testAttachedWindowOwnsFrameEnforcerUntilAssociationReleases()
        throws
    {
        let window = ProductTestWindow(
            width: TxChatTheme.Layout.windowWidth,
            height: TxChatTheme.Layout.windowHeight
        )
        weak var retainedEnforcer: TxChatWindowFrameEnforcer?
        var coordinator: TxChatWindowAttachment.Coordinator? =
            TxChatWindowAttachment.Coordinator()

        coordinator?.attach(to: window)
        retainedEnforcer = coordinator?.enforcer
        XCTAssertNotNil(retainedEnforcer)

        coordinator = nil
        XCTAssertNotNil(
            retainedEnforcer,
            "the NSWindow lifetime, not a transient SwiftUI coordinator, " +
                "must own late frame enforcement"
        )

        TxChatWindowFrameEnforcerAssociation.release(
            try XCTUnwrap(retainedEnforcer),
            for: window
        )
        XCTAssertNil(retainedEnforcer)
    }

    func testCoordinatorMigratesFrameEnforcerAssociationToReplacementWindow()
        throws
    {
        let first = ProductTestWindow()
        let replacement = ProductTestWindow()
        let coordinator = TxChatWindowAttachment.Coordinator()

        coordinator.attach(to: first)
        let enforcer = try XCTUnwrap(coordinator.enforcer)
        XCTAssertTrue(
            TxChatWindowFrameEnforcerAssociation.retained(for: first) ===
                enforcer
        )

        coordinator.attach(to: replacement)

        XCTAssertNil(
            TxChatWindowFrameEnforcerAssociation.retained(for: first),
            "a replaced SwiftUI window must release the old association"
        )
        XCTAssertTrue(
            TxChatWindowFrameEnforcerAssociation.retained(
                for: replacement
            ) === enforcer,
            "the replacement window must retain the existing enforcer"
        )
        TxChatWindowFrameEnforcerAssociation.release(
            enforcer,
            for: replacement
        )
    }

    func testFallbackUsesExactBorderlessKeyCapableWindow() {
        let window = ResultFallbackController.makeWindow()

        XCTAssertTrue(window.styleMask.contains(.borderless))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            NSSize(width: 480, height: 300)
        )
        XCTAssertEqual(window.minSize, NSSize(width: 480, height: 300))
        XCTAssertEqual(window.maxSize, NSSize(width: 480, height: 300))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(
            window.collectionBehavior.contains(.fullScreenAuxiliary)
        )
    }

    func testFallbackActionsUseExactFigmaDimensionsInBothLanguages() {
        XCTAssertEqual(ResultFallbackView.secondaryActionWidth, 80)
        XCTAssertEqual(ResultFallbackView.actionHeight, 42)
        XCTAssertEqual(
            ResultFallbackView.primaryActionWidth(
                language: .simplifiedChinese
            ),
            96
        )
        XCTAssertEqual(
            ResultFallbackView.primaryActionWidth(language: .english),
            113
        )
    }

    func testPermissionRepairWindowUsesExactFixedSize() {
        let window = ProductTestWindow(width: 300, height: 200)

        PermissionRepairWindowConfigurator.configure(window)

        XCTAssertEqual(
            window.contentView?.frame.size,
            NSSize(width: 480, height: 280)
        )
        XCTAssertEqual(window.minSize, NSSize(width: 480, height: 280))
        XCTAssertEqual(window.maxSize, NSSize(width: 480, height: 280))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
    }

    func testOverlayCannotBecomeKeyOrMain() {
        let panel = DictationOverlayController.makePanel()

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testOverlayUsesFixedCompactContentSize() {
        let panel = DictationOverlayController.makePanel()

        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).width, 360)
        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).height, 80)
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(
            panel.collectionBehavior.contains(.fullScreenAuxiliary)
        )
    }

    func testCompletedStateIsShownThenHiddenAfterConfiguredDelay() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            completionDisplayDuration: .seconds(1.5)
        )
        defer { controller.hide() }

        controller.update(for: .completed)
        XCTAssertTrue(panel.isVisible)

        let dismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(dismissalScheduled)
        await clock.advance()
        for _ in 0..<20 where panel.isVisible {
            await Task.yield()
        }
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.contentViewController)
    }

    func testEveryFailedStateIsShownThenHiddenAfterConfiguredDelay() async {
        let failures: [DictationFailure] = [
            .targetUnavailable,
            .captureUnavailable,
            .serviceUnavailable,
            .tooManyRequests,
            .protocolViolation,
            .audioLimitExceeded,
            .finalTimeout,
        ]

        for failure in failures {
            let panel = ProductTestPanel()
            let clock = OverlayDismissClock()
            let controller = DictationOverlayController(
                panel: panel,
                completionClock: clock,
                completionDisplayDuration: .seconds(1.5)
            )

            controller.update(for: .failed(failure))
            XCTAssertTrue(panel.isVisible, "failed to show \(failure)")
            let dismissalScheduled = await clock.waitUntilSleeping()
            XCTAssertTrue(
                dismissalScheduled,
                "failed to schedule dismissal for \(failure)"
            )
            let durations = await clock.durations()
            XCTAssertEqual(durations, [.seconds(1.5)])

            await clock.advance()
            for _ in 0..<20 where panel.isVisible {
                await Task.yield()
            }
            XCTAssertFalse(panel.isVisible, "failed to hide \(failure)")
            XCTAssertNil(panel.contentViewController)
        }
    }

    func testNewActiveStateCancelsPendingCompletionHide() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            completionDisplayDuration: .seconds(1.5)
        )
        defer { controller.hide() }

        controller.update(for: .completed)
        let dismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(dismissalScheduled)
        controller.update(
            for: .listening(.init(partialText: "new session"))
        )
        await clock.advance()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(panel.isVisible)
    }

    func testNewActiveStateCancelsPendingFailureHide() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            completionDisplayDuration: .seconds(1.5)
        )
        defer { controller.hide() }

        controller.update(for: .failed(.targetUnavailable))
        let dismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(dismissalScheduled)
        controller.update(
            for: .listening(.init(partialText: "new session"))
        )
        await clock.advance()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(panel.isVisible)
    }

    func testSecondFailureRestartsDismissalDelay() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            completionDisplayDuration: .seconds(1.5)
        )
        defer { controller.hide() }

        controller.update(for: .failed(.targetUnavailable))
        let firstDismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(firstDismissalScheduled)
        controller.update(for: .failed(.serviceUnavailable))
        let secondDismissalScheduled = await clock.waitUntilSleeping(2)
        XCTAssertTrue(secondDismissalScheduled)

        await clock.advance()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertTrue(panel.isVisible)

        await clock.advance()
        for _ in 0..<20 where panel.isVisible {
            await Task.yield()
        }
        XCTAssertFalse(panel.isVisible)
    }

    func testContinuousAudioUpdatesKeepStableHostingControllerAndFrontOrder() {
        let panel = ProductTestPanel()
        let controller = DictationOverlayController(panel: panel)
        defer { controller.hide() }

        controller.update(
            for: .listening(.init(partialText: "")),
            audioLevel: 0.1
        )
        let initialHostingController = panel.contentViewController
        for level in stride(from: 0.2, through: 0.9, by: 0.1) {
            controller.update(
                for: .listening(.init(partialText: "")),
                audioLevel: level
            )
        }

        XCTAssertTrue(panel.contentViewController === initialHostingController)
        XCTAssertEqual(panel.orderFrontCallCount, 1)
    }

    func testHUDCancellationShowsConfirmationUntilConfiguredDelay() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        var cancellationCount = 0
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            completionDisplayDuration: .seconds(1.5),
            cancellationHandler: {
                cancellationCount += 1
                return true
            }
        )
        defer { controller.hide() }

        controller.update(for: .listening(.empty))
        XCTAssertTrue(controller.requestCancellation())
        await Task.yield()
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertTrue(panel.isVisible)

        controller.update(for: .idle)
        XCTAssertTrue(
            panel.isVisible,
            "the runtime idle transition must not erase cancellation feedback"
        )
        let dismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(dismissalScheduled)

        await clock.advance()
        for _ in 0..<20 where panel.isVisible {
            await Task.yield()
        }
        XCTAssertFalse(panel.isVisible)
    }

    func testHUDCancellationIsRejectedAfterInsertionStarts() async {
        var cancellationCount = 0
        let controller = DictationOverlayController(
            panel: ProductTestPanel(),
            cancellationHandler: {
                cancellationCount += 1
                return true
            }
        )
        defer { controller.hide() }

        controller.update(for: .inserting(text: "final"))

        XCTAssertFalse(controller.requestCancellation())
        await Task.yield()
        XCTAssertEqual(cancellationCount, 0)
    }

    func testHUDCancellationDoesNotClaimSuccessWhenRuntimeRejects() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        var cancellationCount = 0
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            cancellationHandler: {
                cancellationCount += 1
                return false
            }
        )
        defer { controller.hide() }

        controller.update(for: DictationState.finalizing(.empty))
        let activeHostingController = panel.contentViewController

        XCTAssertTrue(controller.requestCancellation())
        for _ in 0..<20 where cancellationCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(cancellationCount, 1)
        XCTAssertTrue(panel.contentViewController === activeHostingController)
        let dismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertFalse(
            dismissalScheduled,
            "a rejected cancellation must not schedule success dismissal"
        )
    }

    func testOldCancellationResultCannotOverrideNewDictationHUD() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let gate = CancellationDecisionGate()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            cancellationHandler: { await gate.wait() }
        )
        defer { controller.hide() }

        controller.update(for: .finalizing(.empty))
        XCTAssertTrue(controller.requestCancellation())
        let cancellationPending = await gate.waitUntilPending()
        XCTAssertTrue(cancellationPending)

        controller.update(for: .starting)
        await gate.resolve(true)
        for _ in 0..<20 {
            await Task.yield()
        }

        let oldSuccessScheduledDismissal = await clock.waitUntilSleeping()
        XCTAssertFalse(
            oldSuccessScheduledDismissal,
            "an old accepted request must not replace or dismiss a new HUD"
        )
        XCTAssertTrue(panel.isVisible)
    }

    func testSameSessionHUDRefreshKeepsAcceptedCancellationFeedback() async {
        let panel = ProductTestPanel()
        let clock = OverlayDismissClock()
        let gate = CancellationDecisionGate()
        let controller = DictationOverlayController(
            panel: panel,
            completionClock: clock,
            cancellationHandler: { await gate.wait() }
        )
        defer { controller.hide() }

        controller.update(
            for: .listening(.init(partialText: "first")),
            audioLevel: 0.2
        )
        XCTAssertTrue(controller.requestCancellation())
        let cancellationPending = await gate.waitUntilPending()
        XCTAssertTrue(cancellationPending)

        controller.update(
            for: .listening(.init(partialText: "same session refresh")),
            audioLevel: 0.8
        )
        await gate.resolve(true)

        let successDismissalScheduled = await clock.waitUntilSleeping()
        XCTAssertTrue(
            successDismissalScheduled,
            "same-session refreshes must not discard accepted feedback"
        )
    }

    func testFallbackCopiesOnlyAfterExplicitIntent() {
        let pasteboard = ProductPasteboardFake()
        let controller = ResultFallbackController(
            pasteboard: pasteboard,
            window: ProductTestWindow(),
            retryPromptPanel: ProductTestPanel()
        )
        defer { controller.hide() }

        controller.show(text: "final")

        XCTAssertTrue(pasteboard.values.isEmpty)
        controller.copy()
        XCTAssertEqual(pasteboard.values, ["final"])
    }

    func testFallbackActivatesAndOrdersAboveFullScreenApplications() {
        let window = ProductTestWindow()
        var activationCount = 0
        let controller = ResultFallbackController(
            window: window,
            retryPromptPanel: ProductTestPanel(),
            activateApplication: { activationCount += 1 }
        )
        defer { controller.hide() }

        controller.show(text: "final")

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 1)
        XCTAssertEqual(window.makeKeyCallCount, 1)
        XCTAssertTrue(window.isVisible)
    }

    func testFallbackRetryAndCloseAreExplicitIntents() async {
        let pasteboard = ProductPasteboardFake()
        let controller = ResultFallbackController(
            pasteboard: pasteboard,
            window: ProductTestWindow(),
            retryPromptPanel: ProductTestPanel()
        )
        defer { controller.hide() }
        var retries = 0
        var closes = 0
        controller.show(
            text: "final",
            onRetry: {
                retries += 1
                return true
            },
            onClose: { closes += 1 }
        )

        await controller.retry()
        XCTAssertEqual(retries, 0)
        await controller.confirmRetry()
        controller.show(
            text: "final",
            onRetry: {
                retries += 1
                return true
            },
            onClose: { closes += 1 }
        )
        controller.closeResult()

        XCTAssertEqual(retries, 1)
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(pasteboard.values.isEmpty)
    }

    func testFallbackFailedRetryKeepsPayloadVisibleAndCopyable() async {
        let pasteboard = ProductPasteboardFake()
        let window = ProductTestWindow()
        let controller = ResultFallbackController(
            pasteboard: pasteboard,
            window: window,
            retryPromptPanel: ProductTestPanel()
        )
        defer { controller.hide() }
        controller.show(
            text: "必须保留的 final",
            onRetry: { false }
        )

        await controller.retry()
        await controller.confirmRetry()
        controller.copy()

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(pasteboard.values, ["必须保留的 final"])
    }

    func testFallbackRetryWaitsForExplicitFocusConfirmation() async {
        let resultWindow = ProductTestWindow()
        let promptPanel = ProductTestPanel()
        let controller = ResultFallbackController(
            window: resultWindow,
            retryPromptPanel: promptPanel
        )
        defer { controller.hide() }
        var retries = 0
        controller.show(
            text: "必须保留的 final",
            onRetry: {
                retries += 1
                return true
            }
        )

        await controller.retry()

        XCTAssertFalse(resultWindow.isVisible)
        XCTAssertTrue(promptPanel.isVisible)
        XCTAssertEqual(retries, 0)

        await controller.confirmRetry()

        XCTAssertFalse(promptPanel.isVisible)
        XCTAssertEqual(retries, 1)
    }

    func testFallbackHideReleasesPayloadAndCallbacks() async {
        let pasteboard = ProductPasteboardFake()
        let controller = ResultFallbackController(
            pasteboard: pasteboard,
            window: ProductTestWindow(),
            retryPromptPanel: ProductTestPanel()
        )
        defer { controller.hide() }
        var retries = 0
        var closes = 0
        controller.show(
            text: "sensitive final",
            onRetry: {
                retries += 1
                return true
            },
            onClose: { closes += 1 }
        )

        controller.hide()
        controller.copy()
        await controller.retry()
        controller.closeResult()

        XCTAssertTrue(pasteboard.values.isEmpty)
        XCTAssertEqual(retries, 0)
        XCTAssertEqual(closes, 0)
    }

    func testFallbackSystemCloseDismissesResultExactlyOnce() {
        let pasteboard = ProductPasteboardFake()
        let window = ProductTestWindow()
        let controller = ResultFallbackController(
            pasteboard: pasteboard,
            window: window,
            retryPromptPanel: ProductTestPanel()
        )
        defer { controller.hide() }
        var closes = 0
        controller.show(
            text: "final",
            onClose: { closes += 1 }
        )

        window.close()
        controller.closeResult()

        XCTAssertEqual(closes, 1)
        controller.copy()
        XCTAssertTrue(pasteboard.values.isEmpty)
    }
}
