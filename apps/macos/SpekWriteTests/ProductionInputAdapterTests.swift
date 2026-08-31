import AppKit
import XCTest
@testable import SpekWrite

@MainActor
private final class ProductEventTapFake: CoreHotkeyEventTapping {
    private var handler: ((CoreHotkeyInputEvent) -> CoreHotkeyDecision)?
    private(set) var stopCount = 0

    func start(
        handler: @escaping @MainActor (CoreHotkeyInputEvent) ->
            CoreHotkeyDecision
    ) -> Bool {
        self.handler = handler
        return true
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func emit(_ event: CoreHotkeyInputEvent) -> CoreHotkeyDecision {
        handler?(event) ?? .passThrough
    }
}

@MainActor
private final class HotkeyRecoverySchedulerFake {
    struct Pending {
        let delay: TimeInterval
        let action: @MainActor () -> Void
    }

    private(set) var pending: [Pending] = []

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        pending.append(Pending(delay: delay, action: action))
    }

    func runNext() {
        guard !pending.isEmpty else {
            return
        }
        pending.removeFirst().action()
    }
}

@MainActor
private final class ProductTargetFake: CoreTargetHandling {
    let target = CoreCapturedTarget(
        id: UUID(uuidString: "019c1aa5-677c-7898-983d-60cc26a8fcdd")!,
        processIdentifier: 42
    )
    private(set) var inserted: [(String, CoreCapturedTarget)] = []
    private(set) var discarded: [CoreCapturedTarget] = []

    func capture() -> CoreTargetCaptureOutcome {
        .captured(target)
    }

    func insert(_ text: String, into target: CoreCapturedTarget) -> Bool {
        inserted.append((text, target))
        return true
    }

    func discard(_ target: CoreCapturedTarget) {
        discarded.append(target)
    }
}

@MainActor
final class ProductionInputAdapterTests: XCTestCase {
    func testDisabledHotkeyTapStopsAndDoesNotRetryWithoutAccessibility() {
        let scheduler = HotkeyRecoverySchedulerFake()
        var trusted = false
        var stopCount = 0
        var restartCount = 0
        let safety = CoreHotkeyTapSafetyController(
            accessibilityTrusted: { trusted },
            schedule: scheduler.schedule
        )

        safety.handleTapDisabled(
            stop: { stopCount += 1 },
            restart: {
                restartCount += 1
                return true
            }
        )

        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(restartCount, 0)
        XCTAssertTrue(scheduler.pending.isEmpty)
        trusted = true
        XCTAssertEqual(restartCount, 0)
    }

    func testDisabledHotkeyTapRechecksPermissionBeforeDelayedRetry() {
        let scheduler = HotkeyRecoverySchedulerFake()
        var trusted = true
        var restartCount = 0
        let safety = CoreHotkeyTapSafetyController(
            accessibilityTrusted: { trusted },
            schedule: scheduler.schedule
        )

        safety.handleTapDisabled(
            stop: {},
            restart: {
                restartCount += 1
                return true
            }
        )
        XCTAssertEqual(scheduler.pending.map(\.delay), [0.25])

        trusted = false
        scheduler.runNext()

        XCTAssertEqual(restartCount, 0)
    }

    func testRepeatedHotkeyTapDisablementUsesBoundedBackoff() {
        let scheduler = HotkeyRecoverySchedulerFake()
        var restartCount = 0
        let safety = CoreHotkeyTapSafetyController(
            accessibilityTrusted: { true },
            schedule: scheduler.schedule
        )

        for _ in 0..<8 {
            safety.handleTapDisabled(
                stop: {},
                restart: {
                    restartCount += 1
                    return true
                }
            )
            scheduler.runNext()
        }

        XCTAssertEqual(
            scheduler.pending.map(\.delay),
            [],
            "each fake retry is consumed before the next disablement"
        )
        XCTAssertEqual(restartCount, 6)
    }

    func testHealthyHotkeyEventResetsRecoveryBackoff() {
        let scheduler = HotkeyRecoverySchedulerFake()
        let safety = CoreHotkeyTapSafetyController(
            accessibilityTrusted: { true },
            schedule: scheduler.schedule
        )

        safety.handleTapDisabled(stop: {}, restart: { true })
        XCTAssertEqual(scheduler.pending.map(\.delay), [0.25])
        scheduler.runNext()
        safety.handleTapDisabled(stop: {}, restart: { true })
        XCTAssertEqual(scheduler.pending.map(\.delay), [0.5])
        scheduler.runNext()

        safety.noteHealthyEvent()
        safety.handleTapDisabled(stop: {}, restart: { true })

        XCTAssertEqual(scheduler.pending.map(\.delay), [0.25])
    }

    func testProductFunctionMonitorDelegatesOneStandaloneFnTrigger() {
        let tap = ProductEventTapFake()
        let monitor = FunctionKeyMonitor(
            base: CoreHotkeyMonitor(eventTap: tap)
        )
        var triggers = 0

        XCTAssertEqual(
            monitor.start(shortcut: .defaultFn) { triggers += 1 },
            .registered
        )
        XCTAssertEqual(
            tap.emit(.flagsChanged(keyCode: 63, flags: [.function])),
            .suppress
        )
        XCTAssertEqual(
            tap.emit(.flagsChanged(keyCode: 63, flags: [])),
            .triggerAndSuppress
        )
        XCTAssertEqual(triggers, 1)
    }

    func testProductFunctionMonitorPreservesFnCombination() {
        let tap = ProductEventTapFake()
        let monitor = FunctionKeyMonitor(
            base: CoreHotkeyMonitor(eventTap: tap)
        )
        var triggers = 0
        XCTAssertEqual(
            monitor.start(shortcut: .defaultFn) { triggers += 1 },
            .registered
        )

        _ = tap.emit(.flagsChanged(keyCode: 63, flags: [.function]))
        XCTAssertEqual(tap.emit(.keyDown(keyCode: 0)), .passThrough)
        XCTAssertEqual(
            tap.emit(.flagsChanged(keyCode: 63, flags: [])),
            .passThrough
        )
        XCTAssertEqual(triggers, 0)
    }

    func testAccessibilityAdapterPreservesCapturedIdentity() {
        let base = ProductTargetFake()
        let adapter = AccessibilityTargetHandler(base: base)

        guard case .captured(let target) = adapter.capture() else {
            return XCTFail("expected a captured target")
        }

        XCTAssertEqual(target.id, base.target.id)
        XCTAssertEqual(
            target.processIdentifier,
            base.target.processIdentifier
        )
        XCTAssertTrue(adapter.insert("final", into: target))
        XCTAssertEqual(base.inserted.map(\.0), ["final"])
    }

    func testAccessibilityAdapterDiscardsSameCapturedIdentity() {
        let base = ProductTargetFake()
        let adapter = AccessibilityTargetHandler(base: base)
        guard case .captured(let target) = adapter.capture() else {
            return XCTFail("expected a captured target")
        }

        adapter.discard(target)

        XCTAssertEqual(base.discarded, [base.target])
    }
}
