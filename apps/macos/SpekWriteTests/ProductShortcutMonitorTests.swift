@preconcurrency import Carbon.HIToolbox
import XCTest
@testable import SpekWrite

@MainActor
private final class FunctionShortcutRegistrarFake:
    ProductFunctionShortcutRegistering
{
    var result: ShortcutRegistrationResult = .registered
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var handlers: [@MainActor () -> Void] = []

    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        startCount += 1
        handlers.append(handler)
        return result
    }

    func stop() {
        stopCount += 1
    }

    func trigger(_ index: Int = 0) {
        handlers[index]()
    }
}

@MainActor
private final class StandardShortcutRegistrarFake:
    ProductStandardShortcutRegistering
{
    var result: ShortcutRegistrationResult = .registered
    private(set) var shortcuts: [ProductShortcut] = []
    private(set) var stopCount = 0
    private(set) var handlers: [@MainActor () -> Void] = []

    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        shortcuts.append(shortcut)
        handlers.append(handler)
        return result
    }

    func stop() {
        stopCount += 1
    }

    func trigger(_ index: Int = 0) {
        handlers[index]()
    }
}

@MainActor
private final class RightOptionShortcutListenerFake:
    ProductRightOptionShortcutListening
{
    var result: ShortcutRegistrationResult = .registered
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var handlers: [@MainActor () -> Void] = []

    func start(
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        startCount += 1
        handlers.append(handler)
        return result
    }

    func stop() {
        stopCount += 1
    }

    func trigger(_ index: Int = 0) {
        handlers[index]()
    }
}

@MainActor
final class ProductShortcutMonitorTests: XCTestCase {
    func testFunctionShortcutRoutesOnlyToFunctionRegistrar() {
        let dependencies = makeDependencies()
        let monitor = dependencies.monitor
        var triggerCount = 0

        let result = monitor.start(shortcut: .defaultFn) {
            triggerCount += 1
        }
        dependencies.function.trigger()

        XCTAssertEqual(result, .registered)
        XCTAssertEqual(dependencies.function.startCount, 1)
        XCTAssertTrue(dependencies.standard.shortcuts.isEmpty)
        XCTAssertEqual(dependencies.rightOption.startCount, 0)
        XCTAssertEqual(triggerCount, 1)
    }

    func testStandardShortcutPassesCompleteIdentityToCarbonRoute() throws {
        let dependencies = makeDependencies()
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.option, .command]
        )
        var triggerCount = 0

        let result = dependencies.monitor.start(shortcut: shortcut) {
            triggerCount += 1
        }
        dependencies.standard.trigger()

        XCTAssertEqual(result, .registered)
        XCTAssertEqual(dependencies.standard.shortcuts, [shortcut])
        XCTAssertEqual(dependencies.function.startCount, 0)
        XCTAssertEqual(dependencies.rightOption.startCount, 0)
        XCTAssertEqual(triggerCount, 1)
    }

    func testRightOptionUsesDedicatedListenerRoute() throws {
        let dependencies = makeDependencies()
        let shortcut = try ProductShortcut(
            key: .rightOption,
            modifiers: []
        )
        var triggerCount = 0

        let result = dependencies.monitor.start(shortcut: shortcut) {
            triggerCount += 1
        }
        dependencies.rightOption.trigger()

        XCTAssertEqual(result, .registered)
        XCTAssertEqual(dependencies.rightOption.startCount, 1)
        XCTAssertEqual(dependencies.function.startCount, 0)
        XCTAssertTrue(dependencies.standard.shortcuts.isEmpty)
        XCTAssertEqual(triggerCount, 1)
    }

    func testFailedRegistrationCleansPartialRouteAndRejectsCallback() throws {
        let dependencies = makeDependencies()
        dependencies.standard.result = .failed(.conflict)
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 0, displayName: "A"),
            modifiers: [.command]
        )
        var triggerCount = 0

        let result = dependencies.monitor.start(shortcut: shortcut) {
            triggerCount += 1
        }
        dependencies.standard.trigger()

        XCTAssertEqual(result, .failed(.conflict))
        XCTAssertEqual(dependencies.standard.stopCount, 1)
        XCTAssertEqual(triggerCount, 0)
    }

    func testStartingReplacementStopsOldRouteAndRejectsStaleCallback() throws {
        let dependencies = makeDependencies()
        let standardShortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        var triggerCount = 0

        XCTAssertEqual(
            dependencies.monitor.start(shortcut: .defaultFn) {
                triggerCount += 1
            },
            .registered
        )
        XCTAssertEqual(
            dependencies.monitor.start(shortcut: standardShortcut) {
                triggerCount += 1
            },
            .registered
        )
        dependencies.function.trigger()
        dependencies.standard.trigger()

        XCTAssertEqual(dependencies.function.stopCount, 1)
        XCTAssertEqual(dependencies.standard.stopCount, 0)
        XCTAssertEqual(dependencies.rightOption.stopCount, 0)
        XCTAssertEqual(triggerCount, 1)
    }

    func testStopCleansActiveRouteAndRejectsLaterCallback() {
        let dependencies = makeDependencies()
        var triggerCount = 0
        _ = dependencies.monitor.start(shortcut: .defaultFn) {
            triggerCount += 1
        }

        dependencies.monitor.stop()
        dependencies.function.trigger()

        XCTAssertEqual(dependencies.function.stopCount, 1)
        XCTAssertEqual(triggerCount, 0)
    }

    func testProductionRightOptionListenerReportsUnsupported() {
        let listener = UnsupportedProductRightOptionShortcutListener()

        XCTAssertEqual(
            listener.start {},
            .failed(.unsupported)
        )
        listener.stop()
    }

    func testCarbonRouteAcceptsOnlyItsOwnHotKeyIdentifier() {
        XCTAssertTrue(
            CarbonProductStandardShortcutRegistrar.acceptsHotKey(
                signature: 0x5458_4348,
                identifier: 1
            )
        )
        XCTAssertFalse(
            CarbonProductStandardShortcutRegistrar.acceptsHotKey(
                signature: 0x4F54_4845,
                identifier: 1
            )
        )
        XCTAssertFalse(
            CarbonProductStandardShortcutRegistrar.acceptsHotKey(
                signature: 0x5458_4348,
                identifier: 2
            )
        )
    }

    func testCarbonRoutePreservesAllSupportedModifierFlags() {
        let expected = UInt32(controlKey) |
            UInt32(optionKey) |
            UInt32(shiftKey) |
            UInt32(cmdKey)

        XCTAssertEqual(
            CarbonProductStandardShortcutRegistrar.modifierMask(
                for: [.control, .option, .shift, .command]
            ),
            expected
        )
    }

    private func makeDependencies() -> (
        monitor: ProductShortcutMonitor,
        function: FunctionShortcutRegistrarFake,
        standard: StandardShortcutRegistrarFake,
        rightOption: RightOptionShortcutListenerFake
    ) {
        let function = FunctionShortcutRegistrarFake()
        let standard = StandardShortcutRegistrarFake()
        let rightOption = RightOptionShortcutListenerFake()
        return (
            ProductShortcutMonitor(
                functionRegistrar: function,
                standardRegistrar: standard,
                rightOptionListener: rightOption
            ),
            function,
            standard,
            rightOption
        )
    }
}
