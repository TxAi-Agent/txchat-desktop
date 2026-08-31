import Foundation
import XCTest
@testable import SpekWrite

final class PublicLocalAuthenticationServiceTests: XCTestCase {
    override func tearDown() {
        PublicLocalURLProtocol.handler = nil
        super.tearDown()
    }

    func testBootstrapRefreshAccountAndLogoutUseStrictPublicLocalRequests() async throws {
        let accessOne = String(repeating: "a", count: 43)
        let refreshOne = String(repeating: "b", count: 43)
        let accessTwo = String(repeating: "c", count: 43)
        let refreshTwo = String(repeating: "d", count: 43)
        let sessionID = UUID().uuidString.lowercased()
        let ledger = PublicLocalRequestLedger()

        PublicLocalURLProtocol.handler = { request in
            await ledger.record(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", TxChatPublicLocalContract.sessionPath):
                return (201, try Self.sessionData(
                    accessToken: accessOne,
                    refreshToken: refreshOne,
                    sessionID: sessionID
                ))
            case ("POST", TxChatPublicLocalContract.refreshPath):
                return (200, try Self.sessionData(
                    accessToken: accessTwo,
                    refreshToken: refreshTwo,
                    sessionID: sessionID
                ))
            case ("GET", TxChatPublicLocalContract.accountPath):
                return (200, try JSONSerialization.data(withJSONObject: [
                    "authenticated": true,
                ]))
            case ("POST", TxChatPublicLocalContract.logoutPath):
                return (204, Data())
            default:
                return (404, Data())
            }
        }

        let service = try PublicLocalAuthenticationService(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:41873")),
            session: Self.session()
        )
        let credential = try await service.bootstrapCredential()
        XCTAssertEqual(credential.refreshToken, refreshOne)
        XCTAssertEqual(credential.sessionID, sessionID)

        let refreshed = try await service.refresh(
            refreshToken: refreshOne,
            requestID: UUID().uuidString.lowercased()
        )
        XCTAssertEqual(refreshed.accessToken, accessTwo)
        XCTAssertEqual(refreshed.refreshToken, refreshTwo)
        XCTAssertEqual(refreshed.sessionID, sessionID)

        let account = try await service.currentAccount(accessToken: accessTwo)
        XCTAssertTrue(account.loggedIn)
        XCTAssertEqual(account.maskedPhone, "")
        try await service.logout(accessToken: accessTwo)

        let requests = await ledger.requests()
        XCTAssertEqual(
            requests.map(\.path),
            [
                TxChatPublicLocalContract.sessionPath,
                TxChatPublicLocalContract.refreshPath,
                TxChatPublicLocalContract.accountPath,
                TxChatPublicLocalContract.logoutPath,
            ]
        )
        XCTAssertTrue(requests.allSatisfy { $0.host == "127.0.0.1" })
    }

    func testRejectsNonLoopbackBaseURLAndExtraResponseFields() async throws {
        XCTAssertThrowsError(
            try PublicLocalAuthenticationService(
                baseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
                session: Self.session()
            )
        )

        PublicLocalURLProtocol.handler = { _ in
            let access = String(repeating: "a", count: 43)
            let refresh = String(repeating: "b", count: 43)
            let object: [String: Any] = [
                "accessToken": access,
                "accessExpiresInSeconds": 900,
                "refreshToken": refresh,
                "refreshExpiresInSeconds": 3600,
                "sessionId": UUID().uuidString.lowercased(),
                "unexpected": true,
            ]
            return (201, try JSONSerialization.data(withJSONObject: object))
        }
        let service = try PublicLocalAuthenticationService(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:41873")),
            session: Self.session()
        )
        do {
            _ = try await service.bootstrapCredential()
            XCTFail("Accepted a response with an additional field")
        } catch {
            XCTAssertEqual(
                error as? AuthenticationServiceError,
                .protocolViolation
            )
        }
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicLocalURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func sessionData(
        accessToken: String,
        refreshToken: String,
        sessionID: String
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "accessToken": accessToken,
            "accessExpiresInSeconds": 900,
            "refreshToken": refreshToken,
            "refreshExpiresInSeconds": 3600,
            "sessionId": sessionID,
        ])
    }
}

private actor PublicLocalRequestLedger {
    struct Request: Sendable {
        let host: String
        let path: String
    }

    private var recorded: [Request] = []

    func record(_ request: URLRequest) {
        recorded.append(Request(
            host: request.url?.host ?? "",
            path: request.url?.path ?? ""
        ))
    }

    func requests() -> [Request] {
        recorded
    }
}

private final class PublicLocalURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Task {
            do {
                let (status, data) = try await handler(request)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !data.isEmpty {
                    client?.urlProtocol(self, didLoad: data)
                }
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
