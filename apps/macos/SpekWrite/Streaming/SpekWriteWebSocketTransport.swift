import Foundation

protocol RealtimeDictationTransport: Sendable {
    func connect(accessToken: String) async throws
    func send(control: RealtimeClientControl) async throws
    func send(audio: Data) async throws
    func receive() async throws -> RealtimeServerControl
    func close() async
}

actor SpekWriteWebSocketTransport: RealtimeDictationTransport {
    private static let routePath = TxChatPublicLocalContract.dictationPath

    private let baseURL: URL
    private let session: URLSession
    private let allowsInsecureLoopbackForTesting: Bool
    private var task: URLSessionWebSocketTask?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        allowsInsecureLoopbackForTesting: Bool = false
    ) {
        self.baseURL = baseURL
        self.session = session
        self.allowsInsecureLoopbackForTesting = allowsInsecureLoopbackForTesting
    }

    static func makeRequest(
        baseURL: URL,
        accessToken: String,
        allowsInsecureLoopbackForTesting: Bool
    ) throws -> URLRequest {
        guard
            let scheme = baseURL.scheme?.lowercased(),
            let host = baseURL.host,
            !host.isEmpty,
            baseURL.user == nil,
            baseURL.password == nil,
            !accessToken.isEmpty,
            accessToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw RealtimeDictationError.serviceUnavailable
        }
        let secure = scheme == "wss"
        let permittedLoopback =
            allowsInsecureLoopbackForTesting &&
            scheme == "ws" &&
            host == "127.0.0.1"
        guard secure || permittedLoopback else {
            throw RealtimeDictationError.serviceUnavailable
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = baseURL.port
        components.path = routePath
        guard let url = components.url else {
            throw RealtimeDictationError.serviceUnavailable
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 305
        )
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    func connect(accessToken: String) async throws {
        guard task == nil else {
            throw RealtimeDictationError.invalidState
        }
        let request = try Self.makeRequest(
            baseURL: baseURL,
            accessToken: accessToken,
            allowsInsecureLoopbackForTesting: allowsInsecureLoopbackForTesting
        )
        let webSocketTask = session.webSocketTask(with: request)
        webSocketTask.maximumMessageSize = RealtimeProtocolCodec.maximumMessageBytes
        task = webSocketTask
        webSocketTask.resume()
    }

    func send(control: RealtimeClientControl) async throws {
        guard let task else {
            throw RealtimeDictationError.invalidState
        }
        let data = try RealtimeProtocolCodec.encode(control)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeDictationError.protocolViolation
        }
        try await task.send(.string(text))
    }

    func send(audio: Data) async throws {
        guard let task else {
            throw RealtimeDictationError.invalidState
        }
        guard
            !audio.isEmpty,
            audio.count <= 6_400,
            audio.count.isMultiple(of: 2)
        else {
            throw RealtimeDictationError.invalidAudioFrame
        }
        try await task.send(.data(audio))
    }

    func receive() async throws -> RealtimeServerControl {
        guard let task else {
            throw RealtimeDictationError.invalidState
        }
        let message = try await task.receive()
        switch message {
        case .string(let value):
            guard let data = value.data(using: .utf8) else {
                throw RealtimeDictationError.protocolViolation
            }
            return try RealtimeProtocolCodec.decodeServer(data)
        case .data:
            throw RealtimeDictationError.protocolViolation
        @unknown default:
            throw RealtimeDictationError.protocolViolation
        }
    }

    func ping() async throws {
        guard let task else {
            throw RealtimeDictationError.invalidState
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func close() async {
        guard let task else {
            return
        }
        self.task = nil
        task.cancel(with: .normalClosure, reason: nil)
    }
}
