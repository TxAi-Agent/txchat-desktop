import Foundation
import XCTest
@testable import SpekWrite

private actor DiagnosticServiceFake: DiagnosticReportServing {
    enum Failure: Error { case requested }
    private(set) var reports: [DiagnosticReportEnvelope] = []
    var shouldFail = false

    func submit(
        _ report: DiagnosticReportEnvelope
    ) async throws -> DiagnosticReportSuccess {
        reports.append(report)
        if shouldFail { throw Failure.requested }
        return DiagnosticReportSuccess(
            diagnosticNumber: "TX-23456789",
            reportId: report.reportId,
            receivedAt: DiagnosticTimestamp(date: DiagnosticTestFixture.occurredAt)
        )
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }
}

private actor DiagnosticTypedFailureService: DiagnosticReportServing {
    let error: DiagnosticReportServiceError

    init(error: DiagnosticReportServiceError) {
        self.error = error
    }

    func submit(
        _ report: DiagnosticReportEnvelope
    ) async throws -> DiagnosticReportSuccess {
        _ = report
        throw error
    }
}

private actor DiagnosticCacheFake: DiagnosticReportCaching {
    enum Failure: Error { case deleteRequested, purgeRequested }

    private(set) var value: DiagnosticReportEnvelope?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0
    private(set) var purgeCount = 0
    private var deleteDelay: Duration?
    private var shouldFailDelete = false
    private var shouldFailPurge = false

    func saveIfAbsent(_ report: DiagnosticReportEnvelope) async throws {
        saveCount += 1
        if value == nil { value = report }
    }

    func load() async throws -> DiagnosticReportEnvelope? { value }

    func delete() async throws {
        deleteCount += 1
        if let deleteDelay {
            try await Task.sleep(for: deleteDelay)
        }
        if shouldFailDelete {
            throw Failure.deleteRequested
        }
        value = nil
    }

    func purgeOnLaunch() async throws {
        purgeCount += 1
        if shouldFailPurge {
            throw Failure.purgeRequested
        }
        value = nil
    }

    func setDeleteDelay(_ value: Duration?) {
        deleteDelay = value
    }

    func setShouldFailDelete(_ value: Bool) {
        shouldFailDelete = value
    }

    func setShouldFailPurge(_ value: Bool) {
        shouldFailPurge = value
    }
}

private struct DiagnosticBuilderFake: DiagnosticReportBuilding {
    let reportID: UUID

    func build(
        incident: DiagnosticIncident,
        occurredAt: Date,
        confirmedAt: Date
    ) async throws -> DiagnosticReportEnvelope {
        _ = incident
        _ = occurredAt
        _ = confirmedAt
        return DiagnosticTestFixture.report(reportID: reportID)
    }
}

private final class DiagnosticNowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func read() -> Date {
        lock.withLock { value }
    }

    func set(_ value: Date) {
        lock.withLock { self.value = value }
    }
}

@MainActor
final class DiagnosticReportCoordinatorTests: XCTestCase {
    func testServiceFailuresRemainDistinctForRecoveryCopy() async {
        let cases: [(DiagnosticReportServiceError, DiagnosticReportFailureReason)] = [
            (.invalidRequest, .invalidRequest),
            (.conflict, .conflict),
            (.tooLarge, .tooLarge),
            (.rateLimited(retryAfterSeconds: 45), .rateLimited(retryAfterSeconds: 45)),
            (.unavailable, .unavailable),
            (.protocolViolation, .protocolViolation),
        ]

        for (error, reason) in cases {
            let coordinator = makeCoordinator(
                service: DiagnosticTypedFailureService(error: error),
                cache: DiagnosticCacheFake()
            )
            coordinator.enqueue(incident: incident(), occurredAt: Date())

            await coordinator.send()

            XCTAssertEqual(coordinator.presentation, .failed(reason))
        }
    }

    func testPromptDiscardPerformsZeroNetworkAndPersistNoConsent() async {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(service: service, cache: cache)

        coordinator.enqueue(incident: incident(), occurredAt: Date())
        XCTAssertEqual(coordinator.presentation, .prompt)
        await coordinator.discard()

        XCTAssertNil(coordinator.presentation)
        let reportCount = await service.reports.count
        let saveCount = await cache.saveCount
        let deleteCount = await cache.deleteCount
        XCTAssertEqual(reportCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(deleteCount, 1)
    }

    func testSendPersistsOnlyAfterConsentAndSuccessDeletesCache() async {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(service: service, cache: cache)

        coordinator.enqueue(incident: incident(), occurredAt: Date())
        await coordinator.send()

        XCTAssertEqual(coordinator.presentation, .sent("TX-23456789"))
        let reportCount = await service.reports.count
        let saveCount = await cache.saveCount
        let deleteCount = await cache.deleteCount
        let cached = await cache.value
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertNil(cached)
    }

    func testFailureKeepsImmutableEnvelopeAndRetryUsesExactSameBody() async {
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(service: service, cache: cache)

        coordinator.enqueue(incident: incident(), occurredAt: Date())
        await coordinator.send()
        XCTAssertEqual(coordinator.presentation, .failed(.unavailable))
        let cached = await cache.value

        await service.setShouldFail(false)
        await coordinator.retry()

        let reports = await service.reports
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0], reports[1])
        XCTAssertEqual(reports[0], cached)
        let saveCount = await cache.saveCount
        XCTAssertEqual(saveCount, 1)
    }

    func testLaunchPurgesFailedPriorRunWithoutAutomaticRetry() async {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        try? await cache.saveIfAbsent(DiagnosticTestFixture.report())
        let coordinator = makeCoordinator(service: service, cache: cache)

        await coordinator.prepareForLaunch()

        let purgeCount = await cache.purgeCount
        let cached = await cache.value
        let reports = await service.reports
        XCTAssertEqual(purgeCount, 1)
        XCTAssertNil(cached)
        XCTAssertTrue(reports.isEmpty)
    }

    func testLaunchPurgeFailureKeepsResidualAndReportsFailure() async {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let residual = DiagnosticTestFixture.report()
        try? await cache.saveIfAbsent(residual)
        await cache.setShouldFailPurge(true)
        let coordinator = makeCoordinator(service: service, cache: cache)

        let prepared = await coordinator.prepareForLaunch()

        XCTAssertFalse(prepared)
        let cached = await cache.value
        let reports = await service.reports
        XCTAssertEqual(cached, residual)
        XCTAssertTrue(reports.isEmpty)
    }

    func testOnlyOneQueuedIncidentIsPresentedAtATime() {
        let coordinator = makeCoordinator(
            service: DiagnosticServiceFake(),
            cache: DiagnosticCacheFake()
        )
        let first = incident()
        let second = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )

        coordinator.enqueue(incident: first, occurredAt: Date())
        coordinator.enqueue(incident: second, occurredAt: Date())

        XCTAssertEqual(coordinator.currentIncident, first)
        XCTAssertEqual(coordinator.queuedIncident, second)
    }

    func testDoubleSendAndDoubleRetryPerformOneRequestPerState() async {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(service: service, cache: cache)
        coordinator.enqueue(incident: incident(), occurredAt: Date())

        async let firstSend: Void = coordinator.send()
        async let secondSend: Void = coordinator.send()
        _ = await (firstSend, secondSend)
        let afterDoubleSend = await service.reports.count
        XCTAssertEqual(afterDoubleSend, 1)

        coordinator.done()
        coordinator.enqueue(incident: incident(), occurredAt: Date())
        await service.setShouldFail(true)
        await coordinator.send()
        await service.setShouldFail(false)

        async let firstRetry: Void = coordinator.retry()
        async let secondRetry: Void = coordinator.retry()
        _ = await (firstRetry, secondRetry)
        let afterDoubleRetry = await service.reports.count
        XCTAssertEqual(afterDoubleRetry, 3)
    }

    func testFailureCloseAwaitsDeleteBeforePresentingAndSavingNextIncident()
        async
    {
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        await cache.setDeleteDelay(.milliseconds(50))
        let coordinator = makeCoordinator(service: service, cache: cache)
        coordinator.enqueue(incident: incident(), occurredAt: Date())
        await coordinator.send()
        let second = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )

        let closing = Task { await coordinator.discard() }
        await Task.yield()
        coordinator.enqueue(incident: second, occurredAt: Date())
        await closing.value

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, second)
        await service.setShouldFail(false)
        await coordinator.send()
        let reportCount = await service.reports.count
        XCTAssertEqual(reportCount, 2)
    }

    func testPromptDiscardWaitsForDeleteBeforePromotingQueuedIncident() async {
        let cache = DiagnosticCacheFake()
        await cache.setDeleteDelay(.milliseconds(50))
        let coordinator = makeCoordinator(
            service: DiagnosticServiceFake(),
            cache: cache
        )
        let first = incident()
        let second = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )
        coordinator.enqueue(incident: first, occurredAt: Date())
        coordinator.enqueue(incident: second, occurredAt: Date())

        let discarding = Task { await coordinator.discard() }
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, first)
        XCTAssertEqual(coordinator.queuedIncident, second)

        await discarding.value

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, second)
        XCTAssertNil(coordinator.queuedIncident)
    }

    func testPromptDiscardInFlightRejectsSendWithoutNetworkOrEarlyPromotion()
        async
    {
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        await cache.setDeleteDelay(.milliseconds(80))
        let coordinator = makeCoordinator(service: service, cache: cache)
        let first = incident()
        let next = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )
        coordinator.enqueue(incident: first, occurredAt: Date())
        coordinator.enqueue(incident: next, occurredAt: Date())

        let discarding = Task { await coordinator.discard() }
        try? await Task.sleep(for: .milliseconds(10))
        await coordinator.send()

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, first)
        XCTAssertEqual(coordinator.queuedIncident, next)
        let reportsDuringDelete = await service.reports
        XCTAssertTrue(reportsDuringDelete.isEmpty)

        await discarding.value
        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, next)
        let reportsAfterDelete = await service.reports
        XCTAssertTrue(reportsAfterDelete.isEmpty)
    }

    func testFailedDiscardInFlightRejectsRetryAndOldResultCannotOverwriteQueue()
        async
    {
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(service: service, cache: cache)
        let first = incident()
        let next = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )
        coordinator.enqueue(incident: first, occurredAt: Date())
        await coordinator.send()
        coordinator.enqueue(incident: next, occurredAt: Date())
        await cache.setDeleteDelay(.milliseconds(80))
        await service.setShouldFail(false)

        let discarding = Task { await coordinator.discard() }
        try? await Task.sleep(for: .milliseconds(10))
        await coordinator.retry()

        XCTAssertEqual(coordinator.presentation, .failed(.unavailable))
        XCTAssertEqual(coordinator.currentIncident, first)
        XCTAssertEqual(coordinator.queuedIncident, next)
        let reportsDuringDelete = await service.reports
        XCTAssertEqual(reportsDuringDelete.count, 1)

        await discarding.value
        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, next)
        let reportsAfterDelete = await service.reports
        XCTAssertEqual(reportsAfterDelete.count, 1)
    }

    func testPromptAndFailureDiscardDeletionFailuresKeepCurrentAndQueue()
        async
    {
        for beginsFailed in [false, true] {
            let service = DiagnosticServiceFake()
            let cache = DiagnosticCacheFake()
            await cache.setShouldFailDelete(true)
            let coordinator = makeCoordinator(service: service, cache: cache)
            let first = incident()
            let second = DiagnosticIncident(
                category: .dictation,
                taskId: UUID(),
                stage: .audioPump,
                code: .audioBufferOverflow
            )
            coordinator.enqueue(incident: first, occurredAt: Date())
            if beginsFailed {
                await service.setShouldFail(true)
                await coordinator.send()
            }
            coordinator.enqueue(incident: second, occurredAt: Date())
            let expectedPresentation = coordinator.presentation

            await coordinator.discard()

            XCTAssertEqual(coordinator.presentation, expectedPresentation)
            XCTAssertEqual(coordinator.currentIncident, first)
            XCTAssertEqual(coordinator.queuedIncident, second)
            let reports = await service.reports
            XCTAssertEqual(reports.count, beginsFailed ? 1 : 0)
        }
    }

    func testExpiredPromptFinishesWithoutCacheOrNetworkAndPromotesQueue()
        async
    {
        let now = DiagnosticTestFixture.occurredAt
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(
            service: service,
            cache: cache,
            now: { now }
        )
        let expired = incident()
        let next = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )
        coordinator.enqueue(
            incident: expired,
            occurredAt: now.addingTimeInterval(-7 * 86_400 - 0.001)
        )
        coordinator.enqueue(incident: next, occurredAt: now)

        await coordinator.send()

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, next)
        XCTAssertNil(coordinator.queuedIncident)
        let reportCount = await service.reports.count
        let saveCount = await cache.saveCount
        let deleteCount = await cache.deleteCount
        let purgeCount = await cache.purgeCount
        XCTAssertEqual(reportCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertEqual(purgeCount, 0)
    }

    func testExactlySevenDayOldPromptCanSend() async {
        let now = DiagnosticTestFixture.occurredAt
        let service = DiagnosticServiceFake()
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(
            service: service,
            cache: cache,
            now: { now }
        )
        coordinator.enqueue(
            incident: incident(),
            occurredAt: now.addingTimeInterval(-7 * 86_400)
        )

        await coordinator.send()

        XCTAssertEqual(coordinator.presentation, .sent("TX-23456789"))
        let reportCount = await service.reports.count
        let saveCount = await cache.saveCount
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(saveCount, 1)
    }

    func testFailedEnvelopeThatExpiresBeforeRetryIsDeletedWithoutNetwork()
        async
    {
        let clock = DiagnosticNowBox(DiagnosticTestFixture.occurredAt)
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(
            service: service,
            cache: cache,
            now: clock.read
        )
        coordinator.enqueue(
            incident: incident(),
            occurredAt: DiagnosticTestFixture.occurredAt
        )
        await coordinator.send()
        XCTAssertEqual(coordinator.presentation, .failed(.unavailable))
        let next = DiagnosticIncident(
            category: .dictation,
            taskId: UUID(),
            stage: .audioPump,
            code: .audioBufferOverflow
        )
        coordinator.enqueue(incident: next, occurredAt: clock.read())
        clock.set(
            DiagnosticTestFixture.occurredAt.addingTimeInterval(
                7 * 86_400 + 0.001
            )
        )

        await coordinator.retry()

        XCTAssertEqual(coordinator.presentation, .prompt)
        XCTAssertEqual(coordinator.currentIncident, next)
        let reports = await service.reports
        let deleteCount = await cache.deleteCount
        let cached = await cache.value
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertNil(cached)
    }

    func testExactlySevenDayOldFailedEnvelopeCanRetry() async {
        let clock = DiagnosticNowBox(DiagnosticTestFixture.occurredAt)
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(
            service: service,
            cache: cache,
            now: clock.read
        )
        coordinator.enqueue(
            incident: incident(),
            occurredAt: DiagnosticTestFixture.occurredAt
        )
        await coordinator.send()
        clock.set(
            DiagnosticTestFixture.occurredAt.addingTimeInterval(7 * 86_400)
        )
        await service.setShouldFail(false)

        await coordinator.retry()

        XCTAssertEqual(coordinator.presentation, .sent("TX-23456789"))
        let reports = await service.reports
        XCTAssertEqual(reports.count, 2)
    }

    func testExpiredFailedEnvelopeDeletionFailureRemainsDiscardable()
        async
    {
        let clock = DiagnosticNowBox(DiagnosticTestFixture.occurredAt)
        let service = DiagnosticServiceFake()
        await service.setShouldFail(true)
        let cache = DiagnosticCacheFake()
        let coordinator = makeCoordinator(
            service: service,
            cache: cache,
            now: clock.read
        )
        coordinator.enqueue(incident: incident(), occurredAt: clock.read())
        await coordinator.send()
        await cache.setShouldFailDelete(true)
        clock.set(
            DiagnosticTestFixture.occurredAt.addingTimeInterval(
                7 * 86_400 + 1
            )
        )

        await coordinator.retry()

        XCTAssertEqual(coordinator.presentation, .failed(.localPreparation))
        let reportsAfterRetry = await service.reports
        XCTAssertEqual(reportsAfterRetry.count, 1)
        await cache.setShouldFailDelete(false)
        let discarded = await coordinator.discard()
        XCTAssertTrue(discarded)
        XCTAssertNil(coordinator.presentation)
    }

    private func makeCoordinator(
        service: any DiagnosticReportServing,
        cache: any DiagnosticReportCaching,
        now: @escaping @Sendable () -> Date = {
            DiagnosticTestFixture.occurredAt
        }
    ) -> DiagnosticReportCoordinator {
        DiagnosticReportCoordinator(
            service: service,
            cache: cache,
            builder: DiagnosticBuilderFake(reportID: UUID()),
            now: now
        )
    }

    private func incident() -> DiagnosticIncident {
        DiagnosticIncident(
            category: .application,
            taskId: nil,
            stage: .lifecycle,
            code: .abnormalExit
        )
    }
}
