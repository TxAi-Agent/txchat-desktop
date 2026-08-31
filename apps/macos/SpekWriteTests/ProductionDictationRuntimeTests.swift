import Foundation
import XCTest
@testable import SpekWrite

private struct RuntimeTokenProvider: DictationAccessTokenProviding {
    func accessToken() async throws -> String { "access-token" }
}

private actor RuntimeCapture: DictationAudioCapturing {
    func start() async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
    func cancel() async {}
}

private actor RuntimeStream: DictationStreamingServing {
    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws {}

    func send(audio: Data) async throws {}
    func finish() async throws -> String { "final" }
    func cancel() async {}
}

@MainActor
private final class RuntimeTarget: DictationTargetHandling {
    private let target = DictationTarget(
        id: UUID(uuidString: "019c1aa6-44a6-7c02-b782-73f02273e9b1")!,
        processIdentifier: 42
    )

    func capture() -> DictationTargetCaptureOutcome { .captured(target) }
    func insert(_ text: String, into target: DictationTarget) -> Bool { true }
    func discard(_ target: DictationTarget) {}
}

@MainActor
private final class RuntimeFactoryCounts {
    var capture = 0
    var streaming = 0
}

@MainActor
private final class RuntimeShortcutMonitor: FunctionKeyMonitoring {
    private(set) var shortcuts: [ProductShortcut] = []
    var results: [ShortcutRegistrationResult] = []

    func start(
        shortcut: ProductShortcut,
        handler: @escaping @MainActor () -> Void
    ) -> ShortcutRegistrationResult {
        _ = handler
        shortcuts.append(shortcut)
        return results.isEmpty ? .registered : results.removeFirst()
    }

    func stop() {}
}

private final class RuntimeShortcutStore: ShortcutPreferenceStoring {
    let value: ProductShortcut
    var saveSucceeds = true
    private(set) var saved: [ProductShortcut] = []

    init(value: ProductShortcut) {
        self.value = value
    }

    func loadShortcut() -> ProductShortcut { value }
    func saveShortcut(_ shortcut: ProductShortcut) -> Bool {
        saved.append(shortcut)
        return saveSucceeds
    }
}

private final class RuntimeModeStore: DictationModePreferenceStoring {
    var value: DictationMode
    var saveSucceeds = true
    private(set) var saved: [DictationMode] = []

    init(value: DictationMode) {
        self.value = value
    }

    func loadMode() -> DictationMode { value }

    func saveMode(_ mode: DictationMode) -> Bool {
        saved.append(mode)
        return saveSucceeds
    }
}

private final class RuntimeReadbackMismatchUserDefaults: UserDefaults,
    @unchecked Sendable
{
    var failNextWrittenReadback = false
    private var mismatchArmed = false

    override func set(_ value: Any?, forKey defaultName: String) {
        super.set(value, forKey: defaultName)
        if failNextWrittenReadback {
            failNextWrittenReadback = false
            mismatchArmed = true
        }
    }

    override func data(forKey defaultName: String) -> Data? {
        if mismatchArmed {
            mismatchArmed = false
            return Data("readback-mismatch".utf8)
        }
        return super.data(forKey: defaultName)
    }
}

@MainActor
final class ProductionDictationRuntimeTests: XCTestCase {
    func testRestoresAndPersistsDictationMode() {
        let store = RuntimeModeStore(value: .verbatim)
        let runtime = makeRuntime(modeStore: store)

        XCTAssertEqual(runtime.mode, .verbatim)

        runtime.setMode(.smart)

        XCTAssertEqual(runtime.mode, .smart)
        XCTAssertEqual(store.saved, [.smart])
    }

    func testReloadPreferencesAdoptsInstallationBootstrapDefaultMode() {
        let store = RuntimeModeStore(value: .verbatim)
        let runtime = makeRuntime(modeStore: store)
        XCTAssertEqual(runtime.mode, .verbatim)

        store.value = .smart
        runtime.reloadPreferences()

        XCTAssertEqual(runtime.mode, .smart)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testActiveSessionFreezesModeAndDoesNotPersistRejectedChange() async {
        let store = RuntimeModeStore(value: .smart)
        let runtime = makeRuntime(modeStore: store)

        await runtime.toggle()
        XCTAssertEqual(runtime.state, .listening(.empty))

        runtime.setMode(.verbatim)

        XCTAssertEqual(runtime.mode, .smart)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testModeSaveFailureRollsBackInMemorySelection() {
        let store = RuntimeModeStore(value: .smart)
        store.saveSucceeds = false
        let runtime = makeRuntime(modeStore: store)

        runtime.setMode(.verbatim)

        XCTAssertEqual(runtime.mode, .smart)
        XCTAssertEqual(store.saved, [.verbatim])
    }

    func testHotkeyMonitoringRegistersRestoredDeviceShortcut() throws {
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.option, .command]
        )
        let monitor = RuntimeShortcutMonitor()
        let runtime = ProductionDictationRuntime(
            dependencies: AppDependencies(
                accessTokenProvider: RuntimeTokenProvider(),
                captureFactory: { RuntimeCapture() },
                streamingFactory: { RuntimeStream() },
                targetHandler: RuntimeTarget()
            ),
            hotkeyMonitor: monitor,
            shortcutStore: RuntimeShortcutStore(value: shortcut)
        )

        XCTAssertTrue(runtime.startHotkeyMonitoring())
        XCTAssertEqual(runtime.shortcut, shortcut)
        XCTAssertEqual(monitor.shortcuts, [shortcut])
    }

    func testShortcutUpdateRegistersBeforePersisting() throws {
        let monitor = RuntimeShortcutMonitor()
        let store = RuntimeShortcutStore(value: .defaultFn)
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.option, .command]
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .updated)
        XCTAssertEqual(runtime.shortcut, candidate)
        XCTAssertEqual(monitor.shortcuts, [.defaultFn, candidate])
        XCTAssertEqual(store.saved, [candidate])
    }

    func testFailedShortcutUpdateRestoresOriginalAndDoesNotPersist() throws {
        let monitor = RuntimeShortcutMonitor()
        monitor.results = [
            .registered,
            .failed(.conflict),
            .registered,
        ]
        let store = RuntimeShortcutStore(value: .defaultFn)
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .failed(.conflict))
        XCTAssertEqual(runtime.shortcut, .defaultFn)
        XCTAssertEqual(
            monitor.shortcuts,
            [.defaultFn, candidate, .defaultFn]
        )
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testShortcutRegistrationRollbackFailureSurfacesUnavailable() throws {
        let monitor = RuntimeShortcutMonitor()
        monitor.results = [
            .registered,
            .failed(.conflict),
            .failed(.unavailable),
        ]
        let store = RuntimeShortcutStore(value: .defaultFn)
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .failed(.unavailable))
        XCTAssertEqual(runtime.shortcut, .defaultFn)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testShortcutSaveFailureRestoresOriginalRegistration() throws {
        let monitor = RuntimeShortcutMonitor()
        let store = RuntimeShortcutStore(value: .defaultFn)
        store.saveSucceeds = false
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .saveFailed)
        XCTAssertEqual(runtime.shortcut, .defaultFn)
        XCTAssertEqual(
            monitor.shortcuts,
            [.defaultFn, candidate, .defaultFn]
        )
        XCTAssertEqual(store.saved, [candidate])
    }

    func testShortcutReadbackFailureRestoresRegistrationAndPersistedValue()
        throws
    {
        let original = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 49, displayName: "Space"),
            modifiers: [.control, .option]
        )
        let suiteName = "ProductionDictationRuntimeTests.\(UUID().uuidString)"
        let defaults = RuntimeReadbackMismatchUserDefaults(
            suiteName: suiteName
        )!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsShortcutStore(
            userDefaults: defaults,
            key: "shortcut"
        )
        XCTAssertTrue(store.saveShortcut(original))
        let monitor = RuntimeShortcutMonitor()
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())
        defaults.failNextWrittenReadback = true

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .saveFailed)
        XCTAssertEqual(runtime.shortcut, original)
        XCTAssertEqual(
            monitor.shortcuts,
            [original, candidate, original]
        )
        XCTAssertEqual(store.loadShortcut(), original)
    }

    func testShortcutSaveRollbackFailureSurfacesUnavailable() throws {
        let monitor = RuntimeShortcutMonitor()
        monitor.results = [
            .registered,
            .registered,
            .failed(.unavailable),
        ]
        let store = RuntimeShortcutStore(value: .defaultFn)
        store.saveSucceeds = false
        let runtime = makeRuntime(
            hotkeyMonitor: monitor,
            shortcutStore: store
        )
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        XCTAssertTrue(runtime.startHotkeyMonitoring())

        let result = runtime.updateShortcut(candidate)

        XCTAssertEqual(result, .failed(.unavailable))
        XCTAssertEqual(runtime.shortcut, .defaultFn)
        XCTAssertEqual(store.saved, [candidate])
    }

    func testCreatesFreshCaptureAndStreamingClientForEverySession() async {
        let counts = RuntimeFactoryCounts()
        let runtime = ProductionDictationRuntime(
            dependencies: AppDependencies(
                accessTokenProvider: RuntimeTokenProvider(),
                captureFactory: {
                    counts.capture += 1
                    return RuntimeCapture()
                },
                streamingFactory: {
                    counts.streaming += 1
                    return RuntimeStream()
                },
                targetHandler: RuntimeTarget()
            )
        )

        await runtime.toggle()
        await runtime.toggle()
        await runtime.toggle()
        await runtime.toggle()

        XCTAssertEqual(counts.capture, 2)
        XCTAssertEqual(counts.streaming, 2)
        XCTAssertEqual(runtime.state, .completed)
    }

    private func makeRuntime(
        hotkeyMonitor: any FunctionKeyMonitoring = RuntimeShortcutMonitor(),
        shortcutStore: any ShortcutPreferenceStoring =
            RuntimeShortcutStore(value: .defaultFn),
        modeStore: any DictationModePreferenceStoring =
            RuntimeModeStore(value: .smart)
    ) -> ProductionDictationRuntime {
        ProductionDictationRuntime(
            dependencies: AppDependencies(
                accessTokenProvider: RuntimeTokenProvider(),
                captureFactory: { RuntimeCapture() },
                streamingFactory: { RuntimeStream() },
                targetHandler: RuntimeTarget()
            ),
            hotkeyMonitor: hotkeyMonitor,
            shortcutStore: shortcutStore,
            modeStore: modeStore
        )
    }

    func testFinalizingToggleDoesNotStartSecondSession() async {
        let counts = RuntimeFactoryCounts()
        let runtime = ProductionDictationRuntime(
            dependencies: AppDependencies(
                accessTokenProvider: RuntimeTokenProvider(),
                captureFactory: {
                    counts.capture += 1
                    return RuntimeCapture()
                },
                streamingFactory: {
                    counts.streaming += 1
                    return RuntimeStream()
                },
                targetHandler: RuntimeTarget()
            ),
            initialState: .finalizing(.empty)
        )

        await runtime.toggle()

        XCTAssertEqual(counts.capture, 0)
        XCTAssertEqual(counts.streaming, 0)
        XCTAssertEqual(runtime.state, .finalizing(.empty))
    }

    func testDesktopPreparerDoesNotDoubleProcessCloudFinalText() async throws {
        let preparer = ProductFinalTextPreparer()

        let smart = try await preparer.prepare(
            "  第一行  中间\n第二行  ",
            mode: .smart
        )
        let verbatim = try await preparer.prepare(
            "  原样  ",
            mode: .verbatim
        )

        XCTAssertEqual(smart, "  第一行  中间\n第二行  ")
        XCTAssertEqual(verbatim, "  原样  ")
    }
}
