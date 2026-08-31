import Foundation

actor SessionManager: DictationAccessTokenProviding {
    typealias Clock = @Sendable () -> Date
    typealias RequestIDFactory = @Sendable () -> String
    typealias InvalidationHandler = @Sendable (
        AuthenticationServiceError
    ) async -> Void

    private struct ActiveSession: Sendable {
        var account: AccountSummary?
        let accessToken: String
        let accessExpiresAt: Date
        let credential: StoredRefreshCredential
    }

    private struct RefreshFlight: Sendable {
        let id: String
        let task: Task<RefreshedSession, Error>
    }

    private let service: any AuthenticationServing
    private let store: any CredentialStoring
    private let now: Clock
    private let requestID: RequestIDFactory
    private let invalidationHandler: InvalidationHandler
    private let refreshLeeway: TimeInterval

    private var currentSession: ActiveSession?
    private var storedCredential: StoredRefreshCredential?
    private var didLoadCredential = false
    private var refreshFlight: RefreshFlight?

    init(
        service: any AuthenticationServing,
        store: any CredentialStoring,
        now: @escaping Clock = Date.init,
        requestID: @escaping RequestIDFactory = {
            UUID().uuidString.lowercased()
        },
        refreshLeeway: TimeInterval = 30,
        invalidationHandler: @escaping InvalidationHandler = { _ in }
    ) {
        self.service = service
        self.store = store
        self.now = now
        self.requestID = requestID
        self.refreshLeeway = refreshLeeway
        self.invalidationHandler = invalidationHandler
    }

    func install(_ session: AuthenticatedSession) async throws {
        let credential = StoredRefreshCredential(
            refreshToken: session.refreshToken,
            sessionID: session.sessionID,
            maskedPhone: session.account.maskedPhone
        )

        // Durable replacement must succeed before the access token is served.
        try await store.replace(with: credential)
        storedCredential = credential
        didLoadCredential = true
        currentSession = ActiveSession(
            account: session.account,
            accessToken: session.accessToken,
            accessExpiresAt: expiration(
                secondsFromNow: session.accessExpiresInSeconds
            ),
            credential: credential
        )
    }

    func accessToken() async throws -> String {
        if let session = currentSession,
           session.accessExpiresAt.timeIntervalSince(now()) > refreshLeeway
        {
            return session.accessToken
        }

        let credential = try await loadCredentialIfNeeded()
        guard let credential else {
            throw AuthenticationServiceError.authenticationRequired
        }
        return try await refreshedAccessToken(using: credential)
    }

    @discardableResult
    func restore() async throws -> AccountSummary? {
        guard try await loadCredentialIfNeeded() != nil else {
            return nil
        }

        let token = try await accessToken()
        do {
            let remoteAccount = try await service.currentAccount(
                accessToken: token
            )
            let account = AccountSummary(
                maskedPhone: storedCredential?.maskedPhone ??
                    remoteAccount.maskedPhone,
                loggedIn: remoteAccount.loggedIn
            )
            if var session = currentSession,
               session.accessToken == token
            {
                session.account = account
                currentSession = session
            }
            return account
        } catch {
            try await invalidateIfRequired(error)
            throw error
        }
    }

    func account() -> AccountSummary? {
        currentSession?.account
    }

    func logout() async throws {
        let token = currentSession?.accessToken
        refreshFlight?.task.cancel()
        refreshFlight = nil

        if let token {
            // Local logout is authoritative even when the remote call fails.
            try? await service.logout(accessToken: token)
        }

        try await store.delete()
        currentSession = nil
        storedCredential = nil
        didLoadCredential = true
    }

    private func loadCredentialIfNeeded() async throws
        -> StoredRefreshCredential?
    {
        if didLoadCredential {
            return storedCredential
        }
        let value = try await store.load()
        storedCredential = value
        didLoadCredential = true
        return value
    }

    private func refreshedAccessToken(
        using credential: StoredRefreshCredential
    ) async throws -> String {
        if let flight = refreshFlight {
            return try await consume(flight)
        }

        let logicalRequestID = requestID()
        let service = service
        let store = store
        let task = Task<RefreshedSession, Error> {
            let refreshed = try await Self.refreshWithOneRetry(
                service: service,
                credential: credential,
                requestID: logicalRequestID
            )
            try Task.checkCancellation()
            try await store.replace(
                with: StoredRefreshCredential(
                    refreshToken: refreshed.refreshToken,
                    sessionID: refreshed.sessionID,
                    maskedPhone: credential.maskedPhone
                )
            )
            return refreshed
        }
        let flight = RefreshFlight(id: logicalRequestID, task: task)
        refreshFlight = flight
        return try await consume(flight)
    }

    private func consume(_ flight: RefreshFlight) async throws -> String {
        do {
            let refreshed = try await flight.task.value
            if refreshFlight?.id == flight.id {
                refreshFlight = nil
                let credential = StoredRefreshCredential(
                    refreshToken: refreshed.refreshToken,
                    sessionID: refreshed.sessionID,
                    maskedPhone: storedCredential?.maskedPhone ??
                        currentSession?.credential.maskedPhone
                )
                let previousAccount = currentSession?.account
                storedCredential = credential
                didLoadCredential = true
                currentSession = ActiveSession(
                    account: previousAccount,
                    accessToken: refreshed.accessToken,
                    accessExpiresAt: expiration(
                        secondsFromNow: refreshed.accessExpiresInSeconds
                    ),
                    credential: credential
                )
                return refreshed.accessToken
            }

            // Another waiter may already have installed this result. Never
            // resurrect it after logout or another session transition.
            if currentSession?.accessToken == refreshed.accessToken {
                return refreshed.accessToken
            }
            throw AuthenticationServiceError.authenticationRequired
        } catch {
            if refreshFlight?.id == flight.id {
                refreshFlight = nil
                try await invalidateIfRequired(error)
            }
            throw error
        }
    }

    private func invalidateIfRequired(_ error: Error) async throws {
        guard
            let authenticationError = error as? AuthenticationServiceError,
            Self.invalidatesSession(authenticationError)
        else {
            return
        }

        try await store.delete()
        currentSession = nil
        storedCredential = nil
        didLoadCredential = true
        await invalidationHandler(authenticationError)
    }

    private func expiration(secondsFromNow: Int) -> Date {
        now().addingTimeInterval(TimeInterval(max(0, secondsFromNow)))
    }

    private static func refreshWithOneRetry(
        service: any AuthenticationServing,
        credential: StoredRefreshCredential,
        requestID: String
    ) async throws -> RefreshedSession {
        do {
            return try await service.refresh(
                refreshToken: credential.refreshToken,
                requestID: requestID
            )
        } catch let error as AuthenticationServiceError {
            guard case .serviceUnavailable = error else {
                throw error
            }
            try Task.checkCancellation()
            return try await service.refresh(
                refreshToken: credential.refreshToken,
                requestID: requestID
            )
        }
    }

    private static func invalidatesSession(
        _ error: AuthenticationServiceError
    ) -> Bool {
        switch error {
        case .authenticationRequired, .sessionReplaced, .sessionReplayed,
             .accountDisabled:
            true
        case .invalidPhone,
             .invalidEnrollmentCredential, .invalidVerificationCode,
             .verificationCodeInvalidOrExpired, .verificationIncorrect,
             .smsChallengeExpired, .smsChallengeExhausted,
             .verificationRetryLimited, .verificationLocked,
             .sendCooldown, .sendQuotaLimited,
             .phoneNotAllowed,
             .tooManyRequests,
             .serviceUnavailable, .protocolViolation:
            false
        }
    }
}
