import Foundation

protocol DiagnosticReportServing: Sendable {
    func submit(
        _ report: DiagnosticReportEnvelope
    ) async throws -> DiagnosticReportSuccess
}

enum DiagnosticReportServiceError: Error, Equatable, Sendable {
    case invalidRequest
    case conflict
    case tooLarge
    case rateLimited(retryAfterSeconds: Int?)
    case unavailable
    case protocolViolation
}

struct OpenAPIDiagnosticReportService: DiagnosticReportServing {
    init(serverURL: URL) {
        _ = serverURL
    }

    func submit(
        _ report: DiagnosticReportEnvelope
    ) async throws -> DiagnosticReportSuccess {
        _ = report
        throw DiagnosticReportServiceError.unavailable
    }
}
