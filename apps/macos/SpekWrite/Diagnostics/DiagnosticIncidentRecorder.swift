import Foundation

@MainActor
protocol DiagnosticIncidentRecording: AnyObject {
    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date,
        durationMs: Int?,
        httpStatus: Int?
    )
}

extension DiagnosticIncidentRecording {
    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date = Date()
    ) {
        record(
            incident,
            occurredAt: occurredAt,
            durationMs: nil,
            httpStatus: nil
        )
    }
}

@MainActor
final class DisabledDiagnosticIncidentRecorder: DiagnosticIncidentRecording {
    static let shared = DisabledDiagnosticIncidentRecorder()

    private init() {}

    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date,
        durationMs: Int?,
        httpStatus: Int?
    ) {
        _ = incident
        _ = occurredAt
        _ = durationMs
        _ = httpStatus
    }
}

@MainActor
final class ProductDiagnosticRelay: DiagnosticIncidentRecording,
    CoreInsertionDiagnosticRecording
{
    weak var target: DiagnosticIncidentRecording?
    private let systemInsertionRecorder =
        SystemCoreInsertionDiagnosticRecorder()

    func record(
        _ incident: DiagnosticIncident,
        occurredAt: Date,
        durationMs: Int?,
        httpStatus: Int?
    ) {
        target?.record(
            incident,
            occurredAt: occurredAt,
            durationMs: durationMs,
            httpStatus: httpStatus
        )
    }

    func record(_ event: CoreInsertionDiagnosticEvent) {
        systemInsertionRecorder.record(event)
        let code: DiagnosticCode
        let stage: DiagnosticStage
        switch event {
        case .insertionTransactionBusy:
            code = .insertionTransactionBusy
            stage = .clipboardTransaction
        case .pasteboardSnapshotFailed:
            code = .pasteboardSnapshotFailed
            stage = .clipboardTransaction
        case .pasteboardWriteFailed:
            code = .pasteboardWriteFailed
            stage = .clipboardTransaction
        case .pasteEventFailed:
            code = .pasteEventFailed
            stage = .eventDelivery
        default:
            return
        }
        record(
            DiagnosticIncident(
                category: .insertion,
                taskId: nil,
                stage: stage,
                code: code
            )
        )
    }
}
