import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

enum CoreHotkeyInputEvent: Equatable {
    case flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags)
    case keyDown(keyCode: UInt16)
    case keyUp(keyCode: UInt16)
}

enum CoreHotkeyDecision: Equatable {
    case passThrough
    case suppress
    case triggerAndSuppress

    var suppressesSystemEvent: Bool {
        self != .passThrough
    }
}

enum CoreHotkeyTapConfiguration {
    static let location = CGEventTapLocation.cghidEventTap
    static let placement = CGEventTapPlacement.headInsertEventTap
    static let options = CGEventTapOptions.defaultTap
    static let eventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged,
    ]
}

#if DEBUG
enum CoreHotkeyDiagnostic {
    static func line(
        eventType: CGEventType,
        keyCode: UInt16,
        rawFlags: UInt64,
        decision: CoreHotkeyDecision
    ) -> String {
        "task3-hotkey event_type=\(eventType.rawValue) " +
            "key_code=\(keyCode) " +
            "flags=0x\(String(rawFlags, radix: 16)) " +
            "decision=\(decision)"
    }
}
#endif

enum CoreFunctionKeyPolicy {
    struct State {
        private enum CompanionFilterState {
            case idle
            case awaitingKeyDown
            case awaitingKeyUp
        }

        // Observed immediately after a standalone Fn release on macOS when
        // the Globe key is configured to show Emoji & Symbols.
        private static let postFnCompanionKeyCode: UInt16 = 179

        private var functionPressed = false
        private var standaloneCandidate = false
        private var companionFilterState = CompanionFilterState.idle

        mutating func update(
            event: CoreHotkeyInputEvent
        ) -> CoreHotkeyDecision {
            switch companionFilterState {
            case .awaitingKeyDown:
                if case .keyDown(let keyCode) = event,
                   keyCode == Self.postFnCompanionKeyCode {
                    companionFilterState = .awaitingKeyUp
                    return .suppress
                }
                companionFilterState = .idle
            case .awaitingKeyUp:
                if case .keyUp(let keyCode) = event,
                   keyCode == Self.postFnCompanionKeyCode {
                    companionFilterState = .idle
                    return .suppress
                }
                companionFilterState = .idle
            case .idle:
                break
            }

            switch event {
            case .keyUp:
                return .passThrough
            case .keyDown:
                if functionPressed {
                    standaloneCandidate = false
                }
                return .passThrough
            case .flagsChanged(let keyCode, let flags):
                let independent = flags.intersection(
                    .deviceIndependentFlagsMask
                )
                let pressed = independent.contains(.function)

                guard keyCode == 63 else {
                    if functionPressed,
                       independent.subtracting(.function).isEmpty == false {
                        standaloneCandidate = false
                    }
                    return .passThrough
                }

                if pressed, !functionPressed {
                    functionPressed = true
                    standaloneCandidate = independent == .function
                    return standaloneCandidate
                        ? .suppress
                        : .passThrough
                }

                if !pressed, functionPressed {
                    functionPressed = false
                    let shouldTrigger = standaloneCandidate &&
                        independent.isEmpty
                    standaloneCandidate = false
                    if shouldTrigger {
                        companionFilterState = .awaitingKeyDown
                    }
                    return shouldTrigger
                        ? .triggerAndSuppress
                        : .passThrough
                }

                return .passThrough
            }
        }
    }
}

@MainActor
protocol CoreHotkeyEventTapping: AnyObject {
    func start(
        handler: @escaping @MainActor (CoreHotkeyInputEvent) ->
            CoreHotkeyDecision
    ) -> Bool
    func stop()
}

@MainActor
final class CoreHotkeyTapSafetyController {
    typealias Schedule = (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void

    private static let retryDelays: [TimeInterval] = [
        0.25,
        0.5,
        1,
        2,
        4,
        8,
    ]

    private let accessibilityTrusted: () -> Bool
    private let schedule: Schedule
    private var retryAttempt = 0
    private var generation = 0

    init(
        accessibilityTrusted: @escaping () -> Bool,
        schedule: @escaping Schedule
    ) {
        self.accessibilityTrusted = accessibilityTrusted
        self.schedule = schedule
    }

    func handleTapDisabled(
        stop: () -> Void,
        restart: @escaping @MainActor () -> Bool
    ) {
        stop()
        generation += 1
        guard accessibilityTrusted(),
              retryAttempt < Self.retryDelays.count else {
            return
        }

        let scheduledGeneration = generation
        let delay = Self.retryDelays[retryAttempt]
        retryAttempt += 1
        schedule(delay) { [weak self] in
            guard let self,
                  generation == scheduledGeneration,
                  accessibilityTrusted() else {
                return
            }
            _ = restart()
        }
    }

    func noteHealthyEvent() {
        retryAttempt = 0
    }

    func cancel() {
        generation += 1
        retryAttempt = 0
    }
}

private func task3HotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let eventTap = Unmanaged<CoreCGEventTap>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        eventTap.handle(type: type, event: event)
    }
}

@MainActor
private final class CoreCGEventTap: CoreHotkeyEventTapping {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor (CoreHotkeyInputEvent) ->
        CoreHotkeyDecision)?
    private let safetyController: CoreHotkeyTapSafetyController
#if DEBUG
    private let diagnosticEnabled = ProcessInfo.processInfo.environment[
        "SPEKWRITE_CORE_HOTKEY_DIAGNOSTIC"
    ] == "1"
#endif

    init() {
        safetyController = CoreHotkeyTapSafetyController(
            accessibilityTrusted: { AXIsProcessTrusted() },
            schedule: { delay, action in
                Task { @MainActor in
                    let nanoseconds = UInt64(delay * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else {
                        return
                    }
                    action()
                }
            }
        )
    }

    func start(
        handler: @escaping @MainActor (CoreHotkeyInputEvent) ->
            CoreHotkeyDecision
    ) -> Bool {
        stop()
        guard AXIsProcessTrusted() else {
            return false
        }
        self.handler = handler
        return installEventTap()
    }

    private func installEventTap() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }
        let eventMask = CoreHotkeyTapConfiguration.eventTypes.reduce(
            CGEventMask(0)
        ) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: CoreHotkeyTapConfiguration.location,
            place: CoreHotkeyTapConfiguration.placement,
            options: CoreHotkeyTapConfiguration.options,
            eventsOfInterest: eventMask,
            callback: task3HotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            return false
        }
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        safetyController.cancel()
        handler = nil
        tearDownEventTap()
    }

    private func tearDownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout ||
            type == .tapDisabledByUserInput {
            safetyController.handleTapDisabled(
                stop: { [weak self] in
                    self?.tearDownEventTap()
                },
                restart: { [weak self] in
                    self?.installEventTap() ?? false
                }
            )
            return Unmanaged.passUnretained(event)
        }

        safetyController.noteHealthyEvent()

        let input: CoreHotkeyInputEvent
        let keyCode = UInt16(
            truncatingIfNeeded: event.getIntegerValueField(
                .keyboardEventKeycode
            )
        )
        switch type {
        case .flagsChanged:
            input = .flagsChanged(
                keyCode: keyCode,
                flags: NSEvent(cgEvent: event)?.modifierFlags ?? []
            )
        case .keyDown:
            input = .keyDown(keyCode: keyCode)
        case .keyUp:
            input = .keyUp(keyCode: keyCode)
        default:
            return Unmanaged.passUnretained(event)
        }

        let decision = handler?(input) ?? .passThrough
#if DEBUG
        if diagnosticEnabled {
            let line = CoreHotkeyDiagnostic.line(
                eventType: type,
                keyCode: keyCode,
                rawFlags: event.flags.rawValue,
                decision: decision
            ) + "\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
#endif
        return decision.suppressesSystemEvent
            ? nil
            : Unmanaged.passUnretained(event)
    }
}

@MainActor
final class CoreHotkeyMonitor {
    private let eventTap: any CoreHotkeyEventTapping
    private var policy = CoreFunctionKeyPolicy.State()

    init(
        eventTap: any CoreHotkeyEventTapping = CoreCGEventTap()
    ) {
        self.eventTap = eventTap
    }

    @discardableResult
    func start(handler: @escaping @MainActor () -> Void) -> Bool {
        stop()
        return eventTap.start { [weak self] event in
            guard let self else {
                return .passThrough
            }
            let decision = policy.update(event: event)
            if decision == .triggerAndSuppress {
                handler()
            }
            return decision
        }
    }

    func stop() {
        eventTap.stop()
        policy = CoreFunctionKeyPolicy.State()
    }
}
