import Foundation
import XCTest
@testable import SpekWrite

private actor DiagnosticLifecycleFake: DiagnosticLifecycleStoring {
    let previousRunWasUnclean: Bool
    let beginFailure: DiagnosticLifecycleStoreError?
    let endFailure: DiagnosticLifecycleStoreError?
    private(set) var beginCount = 0
    private(set) var endCount = 0

    init(
        previousRunWasUnclean: Bool,
        beginFailure: DiagnosticLifecycleStoreError? = nil,
        endFailure: DiagnosticLifecycleStoreError? = nil
    ) {
        self.previousRunWasUnclean = previousRunWasUnclean
        self.beginFailure = beginFailure
        self.endFailure = endFailure
    }

    func beginRun() async throws -> Bool {
        beginCount += 1
        if let beginFailure { throw beginFailure }
        return previousRunWasUnclean
    }

    func endRun() async throws {
        endCount += 1
        if let endFailure { throw endFailure }
    }
}

private actor GatedMarkerLifecycle: DiagnosticLifecycleStoring {
    private var running = false
    private var beginCount = 0
    private var endCount = 0
    private var didReachGate = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func beginRun() async throws -> Bool {
        let previousWasUnclean = running
        beginCount += 1
        if beginCount == 1 {
            didReachGate = true
            let waiters = gateWaiters
            gateWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        running = true
        return previousWasUnclean
    }

    func endRun() async throws {
        endCount += 1
        running = false
    }

    func waitUntilPrepareIsGated() async {
        if didReachGate { return }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    func releasePrepare() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func snapshot() -> (running: Bool, begins: Int, ends: Int) {
        (running, beginCount, endCount)
    }
}

private actor DiagnosticCompletionFlag {
    private var completed = false
    func finish() { completed = true }
    func value() -> Bool { completed }
}

private actor DiagnosticEventStoreFake: DiagnosticEventStoring {
    let shouldFail: Bool
    private(set) var values: [DiagnosticEvent] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func append(_ event: DiagnosticEvent) async throws {
        if shouldFail { throw DiagnosticLocalStoreError.unsafePath }
        values.append(event)
    }
}

private actor DiagnosticRuntimeCacheFake: DiagnosticReportCaching {
    let shouldFailPurge: Bool
    private(set) var purgeCount = 0

    init(shouldFailPurge: Bool = false) {
        self.shouldFailPurge = shouldFailPurge
    }

    func saveIfAbsent(_ report: DiagnosticReportEnvelope) async throws {}
    func load() async throws -> DiagnosticReportEnvelope? { nil }
    func delete() async throws {}
    func purgeOnLaunch() async throws {
        purgeCount += 1
        if shouldFailPurge { throw DiagnosticLocalStoreError.unsafePath }
    }
}

private struct DiagnosticRuntimeServiceFake: DiagnosticReportServing {
    func submit(
        _ report: DiagnosticReportEnvelope
    ) async throws -> DiagnosticReportSuccess {
        XCTFail("prepare and prompt must not send")
        throw DiagnosticReportServiceError.unavailable
    }
}

@MainActor
private struct DiagnosticRuntimeBuilderFake: DiagnosticReportBuilding {
    func build(
        incident: DiagnosticIncident,
        occurredAt: Date,
        confirmedAt: Date
    ) async throws -> DiagnosticReportEnvelope {
        DiagnosticTestFixture.report()
    }
}

@MainActor
final class DiagnosticRuntimeTests: XCTestCase {
    func testQuitDuringPrepareWaitsThenClearsMarkerBeforeReplyAndNextLaunch()
        async
    {
        let lifecycle = GatedMarkerLifecycle()
        let (_, firstCoordinator, firstRuntime) = makeRuntimeParts(
            lifecycle: lifecycle
        )
        let preparing = Task { await firstRuntime.prepareForLaunch() }
        await lifecycle.waitUntilPrepareIsGated()
        let terminationFinished = DiagnosticCompletionFlag()
        let terminating = Task {
            await firstRuntime.terminate()
            await terminationFinished.finish()
        }
        for _ in 0..<4 { await Task.yield() }

        let didFinishBeforeRelease = await terminationFinished.value()
        XCTAssertFalse(didFinishBeforeRelease)
        XCTAssertNil(firstCoordinator.currentIncident)

        await lifecycle.releasePrepare()
        await terminating.value
        await preparing.value
        let afterTermination = await lifecycle.snapshot()
        XCTAssertFalse(afterTermination.running)
        XCTAssertEqual(afterTermination.begins, 1)
        XCTAssertEqual(afterTermination.ends, 1)

        let (_, nextCoordinator, nextRuntime) = makeRuntimeParts(
            lifecycle: lifecycle
        )
        await nextRuntime.prepareForLaunch()
        XCTAssertNil(nextCoordinator.currentIncident)
        await nextRuntime.terminate()
        let afterNextRun = await lifecycle.snapshot()
        XCTAssertFalse(afterNextRun.running)
        XCTAssertEqual(afterNextRun.begins, 2)
        XCTAssertEqual(afterNextRun.ends, 2)
    }

    func testPreviousUncleanRunPromptsOnceAfterLaunchWithoutNetwork() async {
        let lifecycle = DiagnosticLifecycleFake(previousRunWasUnclean: true)
        let events = DiagnosticEventStoreFake()
        let cache = DiagnosticRuntimeCacheFake()
        let reportCoordinator = DiagnosticReportCoordinator(
            service: DiagnosticRuntimeServiceFake(),
            cache: cache,
            builder: DiagnosticRuntimeBuilderFake()
        )
        let window = DiagnosticReportWindowController(
            languageProvider: { .simplifiedChinese },
            actions: .noOp,
            ordersWindow: false
        )
        let runtime = DiagnosticRuntime(
            coordinator: reportCoordinator,
            events: events,
            lifecycle: lifecycle,
            windowController: window
        )

        await runtime.prepareForLaunch()
        await runtime.prepareForLaunch()
        await settle()

        let beginCount = await lifecycle.beginCount
        let purgeCount = await cache.purgeCount
        let eventCount = await events.values.count
        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(purgeCount, 1)
        XCTAssertEqual(
            reportCoordinator.currentIncident,
            DiagnosticIncident(
                category: .application,
                taskId: nil,
                stage: .lifecycle,
                code: .abnormalExit
            )
        )
        XCTAssertEqual(window.presentedState, .prompt(isAbnormalExit: true))
        XCTAssertEqual(eventCount, 1)
    }

    func testNormalTerminationClearsOnlyCurrentRunMarker() async {
        let lifecycle = DiagnosticLifecycleFake(previousRunWasUnclean: false)
        let runtime = makeRuntime(lifecycle: lifecycle)

        await runtime.prepareForLaunch()
        await runtime.terminate()
        await runtime.terminate()

        let beginCount = await lifecycle.beginCount
        let endCount = await lifecycle.endCount
        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(endCount, 1)
    }

    func testReportableIncidentIsContentFreeEventAndSinglePrompt() async {
        let events = DiagnosticEventStoreFake()
        let (runtime, coordinator) = makeRuntimeWithCoordinator(
            lifecycle: DiagnosticLifecycleFake(previousRunWasUnclean: false),
            events: events
        )
        let occurredAt = Date(timeIntervalSince1970: 1_776_758_400)
        let incident = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"),
            stage: .audioPump,
            code: .audioBufferOverflow
        )

        runtime.record(
            incident,
            occurredAt: occurredAt,
            durationMs: 120,
            httpStatus: nil
        )
        await settle()

        XCTAssertEqual(coordinator.currentIncident, incident)
        let recordedEvents = await events.values
        XCTAssertEqual(
            recordedEvents,
            [
                DiagnosticEvent(
                    occurredAt: DiagnosticTimestamp(date: occurredAt),
                    category: .dictation,
                    taskId: incident.taskId,
                    stage: .audioPump,
                    code: .audioBufferOverflow,
                    durationMs: 120,
                    httpStatus: nil
                ),
            ]
        )
    }

    func testCachePurgeAndLifecycleBeginFailuresBecomeLocalStatePrompts()
        async
    {
        let cache = DiagnosticRuntimeCacheFake(shouldFailPurge: true)
        let (_, purgeCoordinator, purgeRuntime) = makeRuntimeParts(
            lifecycle: DiagnosticLifecycleFake(previousRunWasUnclean: false),
            cache: cache
        )
        await purgeRuntime.prepareForLaunch()
        XCTAssertEqual(
            purgeCoordinator.currentIncident,
            localIncident(code: .localStateDeleteFailed)
        )

        let (_, readCoordinator, readRuntime) = makeRuntimeParts(
            lifecycle: DiagnosticLifecycleFake(
                previousRunWasUnclean: false,
                beginFailure: .readFailed
            )
        )
        await readRuntime.prepareForLaunch()
        XCTAssertEqual(
            readCoordinator.currentIncident,
            localIncident(code: .localStateReadFailed)
        )
        XCTAssertNotEqual(
            readCoordinator.currentIncident?.code,
            .abnormalExit
        )
    }

    func testEventAppendAndLifecycleDeleteFailuresAreNotSilent() async {
        let events = DiagnosticEventStoreFake(shouldFail: true)
        let (runtime, coordinator) = makeRuntimeWithCoordinator(
            lifecycle: DiagnosticLifecycleFake(previousRunWasUnclean: false),
            events: events
        )
        runtime.record(
            DiagnosticIncident(
                category: .dictation,
                taskId: nil,
                stage: .audioPump,
                code: .audioBufferOverflow
            )
        )
        await settle()
        XCTAssertEqual(
            coordinator.queuedIncident,
            localIncident(code: .localStateWriteFailed)
        )

        let (_, deleteCoordinator, deleteRuntime) = makeRuntimeParts(
            lifecycle: DiagnosticLifecycleFake(
                previousRunWasUnclean: false,
                endFailure: .deleteFailed
            )
        )
        await deleteRuntime.prepareForLaunch()
        await deleteRuntime.terminate()
        XCTAssertEqual(
            deleteCoordinator.currentIncident,
            localIncident(code: .localStateDeleteFailed)
        )
    }

    private func makeRuntime(
        lifecycle: DiagnosticLifecycleFake
    ) -> DiagnosticRuntime {
        makeRuntimeWithCoordinator(lifecycle: lifecycle).0
    }

    private func makeRuntimeWithCoordinator(
        lifecycle: DiagnosticLifecycleFake,
        events: DiagnosticEventStoreFake = DiagnosticEventStoreFake()
    ) -> (DiagnosticRuntime, DiagnosticReportCoordinator) {
        let (_, coordinator, runtime) = makeRuntimeParts(
            lifecycle: lifecycle,
            events: events
        )
        return (runtime, coordinator)
    }

    private func makeRuntimeParts(
        lifecycle: any DiagnosticLifecycleStoring,
        events: DiagnosticEventStoreFake = DiagnosticEventStoreFake(),
        cache: DiagnosticRuntimeCacheFake = DiagnosticRuntimeCacheFake()
    ) -> (
        DiagnosticReportWindowController,
        DiagnosticReportCoordinator,
        DiagnosticRuntime
    ) {
        let coordinator = DiagnosticReportCoordinator(
            service: DiagnosticRuntimeServiceFake(),
            cache: cache,
            builder: DiagnosticRuntimeBuilderFake()
        )
        let window = DiagnosticReportWindowController(
            languageProvider: { .english },
            actions: .noOp,
            ordersWindow: false
        )
        let runtime = DiagnosticRuntime(
                coordinator: coordinator,
                events: events,
                lifecycle: lifecycle,
                windowController: window
            )
        return (
            window,
            coordinator,
            runtime
        )
    }

    private func localIncident(code: DiagnosticCode) -> DiagnosticIncident {
        DiagnosticIncident(
            category: .application,
            taskId: nil,
            stage: .lifecycle,
            code: code
        )
    }

    private func settle() async {
        for _ in 0..<8 { await Task.yield() }
    }
}
