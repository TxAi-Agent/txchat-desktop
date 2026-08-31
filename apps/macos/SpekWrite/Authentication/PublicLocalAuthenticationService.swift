import Foundation

protocol PublicLocalSessionBootstrapping: Sendable {
    func bootstrapCredential() async throws -> StoredRefreshCredential
}

struct PublicLocalAuthenticationService:
    AuthenticationServing,
    PublicLocalSessionBootstrapping,
    Sendable
{
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) throws {
        guard Self.isValidLoopbackOrigin(baseURL) else {
            throw AuthenticationServiceError.protocolViolation
        }
        self.baseURL = baseURL
        self.session = session
    }

    func bootstrapCredential() async throws -> StoredRefreshCredential {
        let payload = try await sessionPayload(
            method: "POST",
            path: TxChatPublicLocalContract.sessionPath,
            body: try Self.jsonData([:]),
            bearerToken: nil,
            expectedStatus: 201
        )
        return StoredRefreshCredential(
            refreshToken: payload.refreshToken,
            sessionID: payload.sessionId
        )
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
        _ = requestID
        guard Self.isValidToken(refreshToken) else {
            throw AuthenticationServiceError.protocolViolation
        }
        let payload = try await sessionPayload(
            method: "POST",
            path: TxChatPublicLocalContract.refreshPath,
            body: try Self.jsonData(["refreshToken": refreshToken]),
            bearerToken: nil,
            expectedStatus: 200
        )
        return RefreshedSession(
            accessToken: payload.accessToken,
            accessExpiresInSeconds: payload.accessExpiresInSeconds,
            refreshToken: payload.refreshToken,
            refreshExpiresInSeconds: payload.refreshExpiresInSeconds,
            deviceID: payload.sessionId,
            sessionID: payload.sessionId
        )
    }

    func currentAccount(accessToken: String) async throws -> AccountSummary {
        let data = try await perform(
            method: "GET",
            path: TxChatPublicLocalContract.accountPath,
            body: nil,
            bearerToken: accessToken,
            expectedStatus: 200
        )
        guard
            let object = try Self.jsonObject(data),
            Set(object.keys) == Set(["authenticated"]),
            object["authenticated"] as? Bool == true
        else {
            throw AuthenticationServiceError.protocolViolation
        }
        return AccountSummary(maskedPhone: "", loggedIn: true)
    }

    func logout(accessToken: String) async throws {
        let data = try await perform(
            method: "POST",
            path: TxChatPublicLocalContract.logoutPath,
            body: nil,
            bearerToken: accessToken,
            expectedStatus: 204
        )
        guard data.isEmpty else {
            throw AuthenticationServiceError.protocolViolation
        }
    }

    private func sessionPayload(
        method: String,
        path: String,
        body: Data,
        bearerToken: String?,
        expectedStatus: Int
    ) async throws -> SessionPayload {
        let data = try await perform(
            method: method,
            path: path,
            body: body,
            bearerToken: bearerToken,
            expectedStatus: expectedStatus
        )
        guard
            let object = try Self.jsonObject(data),
            Set(object.keys) == Set([
                "accessToken",
                "accessExpiresInSeconds",
                "refreshToken",
                "refreshExpiresInSeconds",
                "sessionId",
            ])
        else {
            throw AuthenticationServiceError.protocolViolation
        }
        do {
            let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
            guard Self.isValidToken(payload.accessToken),
                  Self.isValidToken(payload.refreshToken),
                  payload.accessExpiresInSeconds > 0,
                  payload.refreshExpiresInSeconds > 0,
                  UUID(uuidString: payload.sessionId) != nil
            else {
                throw AuthenticationServiceError.protocolViolation
            }
            return payload
        } catch let error as AuthenticationServiceError {
            throw error
        } catch {
            throw AuthenticationServiceError.protocolViolation
        }
    }

    private func perform(
        method: String,
        path: String,
        body: Data?,
        bearerToken: String?,
        expectedStatus: Int
    ) async throws -> Data {
        if let bearerToken, !Self.isValidToken(bearerToken) {
            throw AuthenticationServiceError.protocolViolation
        }
        guard let url = endpoint(path: path) else {
            throw AuthenticationServiceError.protocolViolation
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationServiceError.protocolViolation
        }
        guard http.statusCode == expectedStatus else {
            if http.statusCode == 401 {
                throw AuthenticationServiceError.authenticationRequired
            }
            if (500...599).contains(http.statusCode) {
                throw unavailable
            }
            throw AuthenticationServiceError.protocolViolation
        }
        return data
    }

    private func endpoint(path: String) -> URL? {
        guard path.hasPrefix("/") else {
            return nil
        }
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )
        components?.path = path
        return components?.url
    }

    private static func isValidLoopbackOrigin(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }
        return components.scheme == "http" &&
            components.host == "127.0.0.1" &&
            components.port.map { (1024...65_535).contains($0) } == true &&
            components.user == nil &&
            components.password == nil &&
            components.query == nil &&
            components.fragment == nil &&
            (components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/")
    }

    private static func isValidToken(_ value: String) -> Bool {
        value.count == 43 && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) ||
                (65...90).contains(scalar.value) ||
                (97...122).contains(scalar.value) ||
                scalar == "_" || scalar == "-"
        }
    }

    private static func jsonData(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw AuthenticationServiceError.protocolViolation
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            throw AuthenticationServiceError.protocolViolation
        }
    }

    private var unavailable: AuthenticationServiceError {
        .serviceUnavailable(retryAfterSeconds: nil)
    }

    private struct SessionPayload: Decodable {
        let accessToken: String
        let accessExpiresInSeconds: Int
        let refreshToken: String
        let refreshExpiresInSeconds: Int
        let sessionId: String
    }
}
