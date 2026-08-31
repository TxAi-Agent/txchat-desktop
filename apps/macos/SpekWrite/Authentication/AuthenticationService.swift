import Foundation

enum AuthenticationServiceError: Error, Equatable, Sendable {
    case invalidPhone
    case invalidEnrollmentCredential
    case invalidVerificationCode
    case verificationCodeInvalidOrExpired
    case verificationIncorrect(attemptsRemaining: Int)
    case smsChallengeExpired
    case smsChallengeExhausted
    case verificationRetryLimited(retryAfterSeconds: Int)
    case verificationLocked(retryAfterSeconds: Int)
    case sendCooldown(retryAfterSeconds: Int)
    case sendQuotaLimited(retryAfterSeconds: Int)
    case phoneNotAllowed
    case tooManyRequests(retryAfterSeconds: Int)
    case serviceUnavailable(retryAfterSeconds: Int?)
    case authenticationRequired
    case sessionReplaced
    case sessionReplayed
    case accountDisabled
    case protocolViolation
}

struct MainlandPhone: Equatable, Sendable {
    let e164: String

    init(_ rawValue: String) throws {
        let ignored = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "-()")
        )
        let scalars = rawValue.unicodeScalars.filter {
            !ignored.contains($0)
        }
        let compact = String(String.UnicodeScalarView(scalars))
        let national: Substring
        if compact.hasPrefix("+86") {
            national = compact.dropFirst(3)
        } else {
            national = compact[...]
        }
        guard
            national.count == 11,
            national.first == "1",
            let second = national.dropFirst().first,
            ("3"..."9").contains(second),
            national.unicodeScalars.allSatisfy(Self.isASCIIDigit)
        else {
            throw AuthenticationServiceError.invalidPhone
        }
        e164 = "+86" + national
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }

    var maskedDisplayPhone: String {
        let national = e164.dropFirst(3)
        return String(national.prefix(3)) + "****" + national.suffix(4)
    }
}

struct EnrollmentCredential: Equatable, Sendable,
    CustomStringConvertible
{
    let value: String

    init(_ value: String) throws {
        let compact = value.filter { !$0.isWhitespace }
        guard
            compact.count == 6,
            compact.unicodeScalars.allSatisfy(Self.isASCIIDigit)
        else {
            throw AuthenticationServiceError.invalidEnrollmentCredential
        }
        self.value = compact
    }

    var description: String {
        "EnrollmentCredential(redacted)"
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}

struct SMSVerificationCode: Equatable, Sendable,
    CustomStringConvertible
{
    let value: String

    init(_ value: String) throws {
        let compact = value.filter { !$0.isWhitespace }
        guard
            compact.count == 6,
            compact.unicodeScalars.allSatisfy(Self.isASCIIDigit)
        else {
            throw AuthenticationServiceError.invalidVerificationCode
        }
        self.value = compact
    }

    var description: String {
        "SMSVerificationCode(redacted)"
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}

struct SMSChallenge: Equatable, Sendable, CustomStringConvertible {
    let id: String
    let expiresInSeconds: Int
    let resendAfterSeconds: Int
    let issuedAt: Date

    init(
        id: String,
        expiresInSeconds: Int,
        resendAfterSeconds: Int,
        issuedAt: Date
    ) throws {
        guard UUID(uuidString: id) != nil,
              expiresInSeconds > 0,
              resendAfterSeconds > 0 else {
            throw AuthenticationServiceError.protocolViolation
        }
        self.id = id
        self.expiresInSeconds = expiresInSeconds
        self.resendAfterSeconds = resendAfterSeconds
        self.issuedAt = issuedAt
    }

    var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(expiresInSeconds))
    }

    var resendAvailableAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(resendAfterSeconds))
    }

    func isActive(at date: Date) -> Bool {
        date < expiresAt
    }

    var description: String {
        "SMSChallenge(expiresInSeconds: \(expiresInSeconds), " +
            "resendAfterSeconds: \(resendAfterSeconds))"
    }
}

struct AccountSummary: Equatable, Sendable {
    let maskedPhone: String
    let loggedIn: Bool
}

struct AuthenticatedSession: Equatable, Sendable,
    CustomStringConvertible
{
    let account: AccountSummary
    let accessToken: String
    let accessExpiresInSeconds: Int
    let refreshToken: String
    let refreshExpiresInSeconds: Int
    let deviceID: String
    let sessionID: String

    var description: String {
        "AuthenticatedSession(account: \(account.maskedPhone), " +
            "deviceID: \(deviceID), sessionID: \(sessionID))"
    }
}

struct RefreshedSession: Equatable, Sendable,
    CustomStringConvertible
{
    let accessToken: String
    let accessExpiresInSeconds: Int
    let refreshToken: String
    let refreshExpiresInSeconds: Int
    let deviceID: String
    let sessionID: String

    var description: String {
        "RefreshedSession(deviceID: \(deviceID), " +
            "sessionID: \(sessionID))"
    }
}

protocol AuthenticationServing: Sendable {
    func requestSMSChallenge(
        phone: MainlandPhone
    ) async throws -> SMSChallenge
    func verifySMSChallenge(
        challenge: SMSChallenge,
        code: SMSVerificationCode
    ) async throws -> AuthenticatedSession
    func requestEnrollmentCode(
        phone: MainlandPhone
    ) async throws -> EnrollmentCredential
    func verifyEnrollment(
        phone: MainlandPhone,
        credential: EnrollmentCredential
    ) async throws -> AuthenticatedSession
    func refresh(
        refreshToken: String,
        requestID: String
    ) async throws -> RefreshedSession
    func currentAccount(accessToken: String) async throws -> AccountSummary
    func logout(accessToken: String) async throws
}

extension AuthenticationServing {
    func requestSMSChallenge(
        phone: MainlandPhone
    ) async throws -> SMSChallenge {
        _ = phone
        throw AuthenticationServiceError.protocolViolation
    }

    func verifySMSChallenge(
        challenge: SMSChallenge,
        code: SMSVerificationCode
    ) async throws -> AuthenticatedSession {
        _ = challenge
        _ = code
        throw AuthenticationServiceError.protocolViolation
    }

    func requestEnrollmentCode(
        phone: MainlandPhone
    ) async throws -> EnrollmentCredential {
        _ = phone
        throw AuthenticationServiceError.protocolViolation
    }
}
