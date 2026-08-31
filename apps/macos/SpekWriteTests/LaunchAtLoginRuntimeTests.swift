import Foundation
import ServiceManagement
import XCTest
@testable import SpekWrite

private enum LaunchAtLoginServiceFixtureError: Error {
    case registrationFailed
}

private actor LaunchAtLoginServiceFake: LaunchAtLoginServicing {
    private let currentStatus: LaunchAtLoginServiceStatus
    private let registrationFails: Bool
    private(set) var registerCount = 0
    private let trace: LaunchAtLoginTrace?

    init(
        status: LaunchAtLoginServiceStatus,
        registrationFails: Bool = false,
        trace: LaunchAtLoginTrace? = nil
    ) {
        currentStatus = status
        self.registrationFails = registrationFails
        self.trace = trace
    }

    func status() async -> LaunchAtLoginServiceStatus {
        currentStatus
    }

    func register() async throws {
        registerCount += 1
        await trace?.append("register")
        if registrationFails {
            throw LaunchAtLoginServiceFixtureError.registrationFailed
        }
    }

    func registrations() -> Int { registerCount }
}

private actor LaunchAtLoginRecordStoreFake: LaunchAtLoginRecordStoring {
    private var hasDecision: Bool
    private(set) var writeCount = 0
    private let trace: LaunchAtLoginTrace?

    init(hasDecision: Bool = false, trace: LaunchAtLoginTrace? = nil) {
        self.hasDecision = hasDecision
        self.trace = trace
    }

    func containsRegistrationDecision() async -> Bool { hasDecision }

    func recordRegistrationDecision() async throws {
        writeCount += 1
        hasDecision = true
        await trace?.append("record")
    }

    func snapshot() -> (Bool, Int) { (hasDecision, writeCount) }
}

private actor LaunchAtLoginTrace {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] { events }
}

final class LaunchAtLoginRuntimeTests: XCTestCase {
    func testMissingRecordAndNotRegisteredRegistersBeforeRecordingOnce()
        async
    {
        let trace = LaunchAtLoginTrace()
        let service = LaunchAtLoginServiceFake(
            status: .notRegistered,
            trace: trace
        )
        let store = LaunchAtLoginRecordStoreFake(trace: trace)
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()
        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        let events = await trace.snapshot()
        XCTAssertTrue(stored.0)
        XCTAssertEqual(stored.1, 1)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(events, ["register", "record"])
    }

    func testEnabledServiceRecordsDecisionWithoutRegistering() async {
        let service = LaunchAtLoginServiceFake(status: .enabled)
        let store = LaunchAtLoginRecordStoreFake()
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        XCTAssertTrue(stored.0)
        XCTAssertEqual(stored.1, 1)
        XCTAssertEqual(registrations, 0)
    }

    func testRequiresApprovalRecordsDecisionWithoutRegisteringAgain() async {
        let service = LaunchAtLoginServiceFake(status: .requiresApproval)
        let store = LaunchAtLoginRecordStoreFake()
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        XCTAssertTrue(stored.0)
        XCTAssertEqual(stored.1, 1)
        XCTAssertEqual(registrations, 0)
    }

    func testExistingRecordAndNotRegisteredRespectsSystemDisable() async {
        let service = LaunchAtLoginServiceFake(status: .notRegistered)
        let store = LaunchAtLoginRecordStoreFake(hasDecision: true)
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        XCTAssertTrue(stored.0)
        XCTAssertEqual(stored.1, 0)
        XCTAssertEqual(registrations, 0)
    }

    func testRegistrationFailureDoesNotConsumeDecisionOrRetryInProcess()
        async
    {
        let trace = LaunchAtLoginTrace()
        let service = LaunchAtLoginServiceFake(
            status: .notRegistered,
            registrationFails: true,
            trace: trace
        )
        let store = LaunchAtLoginRecordStoreFake(trace: trace)
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()
        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        let events = await trace.snapshot()
        XCTAssertFalse(stored.0)
        XCTAssertEqual(stored.1, 0)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(events, ["register"])

        let recoveryService = LaunchAtLoginServiceFake(
            status: .notRegistered
        )
        let nextLaunchRuntime = LaunchAtLoginRuntime(
            service: recoveryService,
            recordStore: store
        )
        await nextLaunchRuntime.activateWhenReady()

        let recoveredStore = await store.snapshot()
        let recoveryRegistrations = await recoveryService.registrations()
        XCTAssertTrue(recoveredStore.0)
        XCTAssertEqual(recoveredStore.1, 1)
        XCTAssertEqual(recoveryRegistrations, 1)
    }

    func testMissingServiceRecordRegistersThenRecordsDecision() async {
        let service = LaunchAtLoginServiceFake(status: .notFound)
        let store = LaunchAtLoginRecordStoreFake()
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        XCTAssertTrue(stored.0)
        XCTAssertEqual(stored.1, 1)
        XCTAssertEqual(registrations, 1)
    }

    func testSystemMissingRecordMapsToRegistrationNeededStatus() {
        XCTAssertEqual(
            SystemLaunchAtLoginStatus.resolve(.notFound),
            .notFound
        )
    }

    func testUnavailableServiceDoesNotConsumeRegistrationDecision() async {
        let service = LaunchAtLoginServiceFake(status: .unavailable)
        let store = LaunchAtLoginRecordStoreFake()
        let runtime = LaunchAtLoginRuntime(service: service, recordStore: store)

        await runtime.activateWhenReady()

        let stored = await store.snapshot()
        let registrations = await service.registrations()
        XCTAssertFalse(stored.0)
        XCTAssertEqual(stored.1, 0)
        XCTAssertEqual(registrations, 0)
    }

    func testAnyExistingPersistedDecisionKeyFailsClosed() {
        let fixtures: [Any] = [
            Data("not-json".utf8),
            Data(
                """
                {"schemaVersion":2,"registrationWasHandled":false}
                """.utf8
            ),
            "wrong-storage-type",
        ]

        for fixture in fixtures {
            XCTAssertTrue(
                UserDefaultsLaunchAtLoginRecordStore
                    .containsRegistrationDecisionValue(fixture),
                "an existing one-shot decision key must never re-enable " +
                    "registration"
            )
        }
        XCTAssertFalse(
            UserDefaultsLaunchAtLoginRecordStore
                .containsRegistrationDecisionValue(nil)
        )
    }
}
