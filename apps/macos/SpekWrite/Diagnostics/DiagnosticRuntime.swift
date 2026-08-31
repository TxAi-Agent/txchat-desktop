import Foundation

@MainActor
final class DiagnosticRuntime: DiagnosticIncidentRecording {
    private let coordinator: DiagnosticReportCoordinator
    private let events: any DiagnosticEventStoring
    private let lifecycle: any DiagnosticLifecycleStoring
    private let windowController: DiagnosticReportWindowController
    private var prepareTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var isTerminating = false
    private var didBeginRun = false
    private var didTerminate = false

    init(
        coordinator: DiagnosticReportCoordinator,
        events: any DiagnosticEventStoring,
        lifecycle: any DiagnosticLifecycleStoring,
        windowController: DiagnosticReportWindowController
    ) {
        self.coordinator = coordinator
        self.events = events
        self.lifecycle = lifecycle
        self.windowController = windowController
        coordinator.setPresentationHandler { [weak self] presentation in
            self?.present(presentation)
        }
    }

    static func production(
        configuration: ProductConfiguration,
        productCoordinator: ProductCoordinator
    ) -> DiagnosticRuntime {
        let events = DiagnosticEventStore()
        let cache = DiagnosticReportCache()
        let builder = ProductionDiagnosticReportBuilder(
            events: events,
            snapshot: { [weak productCoordinator] in
                let provider = ProductionDiagnosticSnapshotProvider.production(
                    language: {
                        productCoordinator?.language ?? .productDefault
                    }
                )
                return try provider.snapshot()
            }
        )
        let reportCoordinator = DiagnosticReportCoordinator(
            service: OpenAPIDiagnosticReportService(
                serverURL: configuration.apiBaseURL
            ),
            cache: cache,
            builder: builder
        )
        let windowController = DiagnosticReportWindowController(
            languageProvider: { [weak productCoordinator] in
                productCoordinator?.language ?? .productDefault
            },
            actions: DiagnosticReportControllerActions(
                notNow: { [weak reportCoordinator] in
                    await reportCoordinator?.discard() ?? false
                },
                send: { [weak reportCoordinator] in
                    Task { @MainActor in
                        await reportCoordinator?.send()
                    }
                },
                retry: { [weak reportCoordinator] in
                    Task { @MainActor in
                        await reportCoordinator?.retry()
                    }
                },
                done: { [weak reportCoordinator] in
                    reportCoordinator?.done()
                }
            )
        )
        return DiagnosticRuntime(
            coordinator: reportCoordinator,
            events: events,
            lifecycle: DiagnosticLifecycleStore(),
            windowController: windowController
        )
    }

    func prepareForLaunch() async {
        guard !isTerminating, !didTerminate else { return }
        if let prepareTask {
            await prepareTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPrepareForLaunch()
        }
        prepareTask = task
        await task.value
    }

    func terminate() async {
        if let terminationTask {
            await terminationTask.value
            return
        }
        guard !didTerminate else { return }
        isTerminating = true
        let preparing = prepareTask
        preparing?.cancel()
        let task = Task { @MainActor [weak self, preparing] in
            await preparing?.value
            guard let self else { return }
            await self.finishTermination()
        }
        terminationTask = task
        await task.value
    }

    private func performPrepareForLaunch() async {
        guard !isTerminating, !Task.isCancelled else { return }
        if !(await coordinator.prepareForLaunch()) {
            if !isTerminating, !Task.isCancelled {
                recordLocalFailure(.localStateDeleteFailed)
            }
        }
        guard !isTerminating, !Task.isCancelled else { return }
        do {
            let previousRunWasUnclean = try await lifecycle.beginRun()
            didBeginRun = true
            guard !isTerminating, !Task.isCancelled else { return }
            if previousRunWasUnclean {
                record(
                    DiagnosticIncident(
                        category: .application,
                        taskId: nil,
                        stage: .lifecycle,
                        code: .abnormalExit
                    )
                )
            }
        } catch let error as DiagnosticLifecycleStoreError {
            guard !isTerminating, !Task.isCancelled else { return }
            switch error {
            case .readFailed:
                recordLocalFailure(.localStateReadFailed)
            case .writeFailed:
                recordLocalFailure(.localStateWriteFailed)
            case .deleteFailed:
                recordLocalFailure(.localStateDeleteFailed)
            }
        } catch {
            if !isTerminating, !Task.isCancelled {
                recordLocalFailure(.localStateReadFailed)
            }
        }
    }

    private func finishTermination() async {
        guard !didTerminate else { return }
        didTerminate = true
        guard didBeginRun else { return }
        do {
            try await lifecycle.endRun()
        } catch let error as DiagnosticLifecycleStoreError {
            switch error {
            case .readFailed:
                recordLocalFailure(.localStateReadFailed)
            case .writeFailed:
                recordLocalFailure(.localStateWriteFailed)
            case .deleteFailed:
                recordLocalFailure(.localStateDeleteFailed)
            }
        } catch {
            recordLocalFailure(.localStateDeleteFailed)
        }
    }

    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date,
        durationMs: Int?,
        httpStatus: Int?
    ) {
        coordinator.enqueue(incident: incident, occurredAt: occurredAt)
        let event = DiagnosticEvent(
            occurredAt: DiagnosticTimestamp(date: occurredAt),
            category: incident.category,
            taskId: incident.taskId,
            stage: incident.stage,
            code: incident.code,
            durationMs: durationMs,
            httpStatus: httpStatus
        )
        Task { [weak self] in
            do {
                try await self?.events.append(event)
            } catch {
                self?.recordLocalFailure(.localStateWriteFailed)
            }
        }
    }

    private func recordLocalFailure(_ code: DiagnosticCode) {
        coordinator.enqueue(
            incident: DiagnosticIncident(
                category: .application,
                taskId: nil,
                stage: .lifecycle,
                code: code
            ),
            occurredAt: Date()
        )
    }

    private func present(
        _ presentation: DiagnosticReportPresentation?
    ) {
        let viewState: DiagnosticReportViewState? = switch presentation {
        case .prompt:
            .prompt(
                isAbnormalExit:
                    coordinator.currentIncident?.code == .abnormalExit
            )
        case .sending: .sending
        case .sent(let number): .sent(number)
        case .failed(let reason): .failed(reason)
        case nil: nil
        }
        windowController.present(viewState)
    }
}
