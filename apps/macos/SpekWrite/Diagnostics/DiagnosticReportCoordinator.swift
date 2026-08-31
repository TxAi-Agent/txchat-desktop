import Combine
import Foundation

protocol DiagnosticReportCaching: Sendable {
    func saveIfAbsent(_ report: DiagnosticReportEnvelope) async throws
    func load() async throws -> DiagnosticReportEnvelope?
    func delete() async throws
    func purgeOnLaunch() async throws
}

extension DiagnosticReportCache: DiagnosticReportCaching {}

@MainActor
protocol DiagnosticReportBuilding: Sendable {
    func build(
        incident: DiagnosticIncident,
        occurredAt: Date,
        confirmedAt: Date
    ) async throws -> DiagnosticReportEnvelope
}

enum DiagnosticReportPresentation: Equatable, Sendable {
    case prompt
    case sending
    case sent(String)
    case failed(DiagnosticReportFailureReason)
}

enum DiagnosticReportFailureReason: Equatable, Sendable {
    case invalidRequest
    case conflict
    case tooLarge
    case rateLimited(retryAfterSeconds: Int?)
    case unavailable
    case protocolViolation
    case localPreparation

    init(serviceError: DiagnosticReportServiceError) {
        self = switch serviceError {
        case .invalidRequest: .invalidRequest
        case .conflict: .conflict
        case .tooLarge: .tooLarge
        case .rateLimited(let seconds):
            .rateLimited(retryAfterSeconds: seconds)
        case .unavailable: .unavailable
        case .protocolViolation: .protocolViolation
        }
    }
}

@MainActor
final class DiagnosticReportCoordinator: ObservableObject {
    typealias PresentationHandler = @MainActor (
        DiagnosticReportPresentation?
    ) -> Void

    @Published private(set) var presentation: DiagnosticReportPresentation? {
        didSet { presentationHandler(presentation) }
    }
    private(set) var currentIncident: DiagnosticIncident?
    private(set) var queuedIncident: DiagnosticIncident?

    private let service: any DiagnosticReportServing
    private let cache: any DiagnosticReportCaching
    private let builder: any DiagnosticReportBuilding
    private let now: @Sendable () -> Date
    private var currentOccurredAt: Date?
    private var queuedOccurredAt: Date?
    private var consentedEnvelope: DiagnosticReportEnvelope?
    private var discardInFlight = false
    private var presentationHandler: PresentationHandler = { _ in }

    init(
        service: any DiagnosticReportServing,
        cache: any DiagnosticReportCaching,
        builder: any DiagnosticReportBuilding,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.cache = cache
        self.builder = builder
        self.now = now
    }

    func setPresentationHandler(_ handler: @escaping PresentationHandler) {
        presentationHandler = handler
        handler(presentation)
    }

    @discardableResult
    func prepareForLaunch() async -> Bool {
        do {
            try await cache.purgeOnLaunch()
            return true
        } catch {
            return false
        }
    }

    func enqueue(incident: DiagnosticIncident, occurredAt: Date) {
        if currentIncident == nil {
            currentIncident = incident
            currentOccurredAt = occurredAt
            presentation = .prompt
        } else if queuedIncident == nil {
            queuedIncident = incident
            queuedOccurredAt = occurredAt
        }
    }

    @discardableResult
    func discard() async -> Bool {
        switch presentation {
        case .prompt, .failed:
            break
        case .sending, .sent, nil:
            return false
        }
        guard !discardInFlight else { return false }
        discardInFlight = true
        defer { discardInFlight = false }
        do {
            try await cache.delete()
        } catch {
            return false
        }
        finishCurrent(presentNext: true)
        return true
    }

    func send() async {
        guard
            !discardInFlight,
            presentation == .prompt,
            let currentIncident,
            let currentOccurredAt
        else {
            return
        }
        let confirmedAt = now()
        if currentOccurredAt < confirmedAt.addingTimeInterval(-7 * 86_400) {
            finishCurrent(presentNext: true)
            return
        }
        presentation = .sending
        do {
            let envelope = try await builder.build(
                incident: currentIncident,
                occurredAt: currentOccurredAt,
                confirmedAt: confirmedAt
            )
            try await cache.saveIfAbsent(envelope)
            consentedEnvelope = envelope
            await submit(envelope)
        } catch {
            presentation = .failed(.localPreparation)
        }
    }

    func retry() async {
        guard !discardInFlight, case .failed = presentation else { return }
        let envelope: DiagnosticReportEnvelope?
        if let consentedEnvelope {
            envelope = consentedEnvelope
        } else {
            envelope = try? await cache.load()
        }
        guard let envelope else {
            presentation = .failed(.localPreparation)
            return
        }
        guard let occurredAt = envelope.occurredAt.date else {
            presentation = .failed(.localPreparation)
            return
        }
        if occurredAt < now().addingTimeInterval(-7 * 86_400) {
            do {
                try await cache.delete()
                finishCurrent(presentNext: true)
            } catch {
                presentation = .failed(.localPreparation)
            }
            return
        }
        consentedEnvelope = envelope
        await submit(envelope)
    }

    func done() {
        guard case .sent = presentation else { return }
        finishCurrent(presentNext: true)
    }

    private func submit(_ envelope: DiagnosticReportEnvelope) async {
        presentation = .sending
        do {
            let success = try await service.submit(envelope)
            guard success.reportId == envelope.reportId else {
                throw DiagnosticReportServiceError.protocolViolation
            }
            try await cache.delete()
            consentedEnvelope = nil
            presentation = .sent(success.diagnosticNumber)
        } catch is CancellationError {
            presentation = .failed(.unavailable)
        } catch let error as DiagnosticReportServiceError {
            presentation = .failed(.init(serviceError: error))
        } catch {
            presentation = .failed(.unavailable)
        }
    }

    private func finishCurrent(presentNext: Bool) {
        currentIncident = nil
        currentOccurredAt = nil
        consentedEnvelope = nil
        presentation = nil
        guard presentNext, let queuedIncident else { return }
        let occurredAt = queuedOccurredAt ?? now()
        self.queuedIncident = nil
        queuedOccurredAt = nil
        enqueue(incident: queuedIncident, occurredAt: occurredAt)
    }
}
