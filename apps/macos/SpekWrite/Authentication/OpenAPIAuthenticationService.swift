import Foundation

struct AuthenticationDiagnosticLogger: Sendable {
    enum Operation: Sendable {
        case application
        case smsChallengeRequest
    }

    static let disabled = AuthenticationDiagnosticLogger()

    static func localTextFile() -> AuthenticationDiagnosticLogger {
        .disabled
    }

    func recordApplicationLaunch() {}

    func recordPresentedFailure(
        operation: Operation,
        error: Error
    ) {
        _ = operation
        _ = error
    }
}

struct OpenAPIAuthenticationService: AuthenticationServing {
    init(
        serverURL: URL,
        diagnosticLog: AuthenticationDiagnosticLogger = .disabled
    ) {
        _ = serverURL
        _ = diagnosticLog
    }

    func requestSMSChallenge(
        phone: MainlandPhone
    ) async throws -> SMSChallenge {
        _ = phone
        throw unavailable
    }

    func verifySMSChallenge(
        challenge: SMSChallenge,
        code: SMSVerificationCode
    ) async throws -> AuthenticatedSession {
        _ = challenge
        _ = code
        throw unavailable
    }

    func requestEnrollmentCode(
        phone: MainlandPhone
    ) async throws -> EnrollmentCredential {
        _ = phone
        throw unavailable
    }

    func verifyEnrollment(
        phone: MainlandPhone,
        credential: EnrollmentCredential
    ) async throws -> AuthenticatedSession {
        _ = phone
        _ = credential
        throw unavailable
    }

    func refresh(
        refreshToken: String,
        requestID: String
    ) async throws -> RefreshedSession {
        _ = refreshToken
        _ = requestID
        throw unavailable
    }

    func currentAccount(
        accessToken: String
    ) async throws -> AccountSummary {
        _ = accessToken
        throw unavailable
    }

    func logout(accessToken: String) async throws {
        _ = accessToken
        throw unavailable
    }

    private var unavailable: AuthenticationServiceError {
        .serviceUnavailable(retryAfterSeconds: nil)
    }
}
