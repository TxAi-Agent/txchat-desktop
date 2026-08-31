import Foundation

protocol DictationAccessTokenProviding: Sendable {
    func accessToken() async throws -> String
}

protocol DictationAudioCapturing: Sendable {
    typealias AudioLevelHandler = @Sendable (Double) async -> Void

    func preflight() async throws
    func start() async throws -> AsyncThrowingStream<Data, Error>
    func start(
        onAudioLevel: @escaping AudioLevelHandler
    ) async throws -> AsyncThrowingStream<Data, Error>
    func stop() async
    func cancel() async
}

extension DictationAudioCapturing {
    func preflight() async throws {}

    func start(
        onAudioLevel: @escaping AudioLevelHandler
    ) async throws -> AsyncThrowingStream<Data, Error> {
        _ = onAudioLevel
        return try await start()
    }
}

struct DictationStreamingResult: Equatable, Sendable {
    let text: String
    let mode: RealtimeFinalResultMode?
    let fallbackReason: RealtimeFallbackReason?

    init(
        text: String,
        mode: RealtimeFinalResultMode?,
        fallbackReason: RealtimeFallbackReason? = nil
    ) {
        self.text = text
        self.mode = mode
        self.fallbackReason = fallbackReason
    }
}

protocol DictationStreamingServing: Sendable {
    typealias OrganizingHandler = @Sendable () async -> Void

    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws
    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping StreamingDictationClient.PartialHandler,
        onOrganizing: @escaping OrganizingHandler
    ) async throws
    func send(audio: Data) async throws
    func finish() async throws -> String
    func finishResult() async throws -> DictationStreamingResult
    func cancel() async
}

extension DictationStreamingServing {
    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping StreamingDictationClient.PartialHandler,
        onOrganizing: @escaping OrganizingHandler
    ) async throws {
        _ = mode
        _ = onOrganizing
        try await start(
            accessToken: accessToken,
            onPartial: onPartial
        )
    }

    func finishResult() async throws -> DictationStreamingResult {
        DictationStreamingResult(
            text: try await finish(),
            mode: nil
        )
    }
}

struct DictationTarget: Equatable, Sendable {
    let id: UUID
    let processIdentifier: Int32
}

enum DictationTargetCaptureOutcome: Equatable, Sendable {
    case captured(DictationTarget)
    case unavailable
    case blocked
}

@MainActor
protocol DictationTargetHandling: AnyObject {
    func capture() -> DictationTargetCaptureOutcome
    func insert(_ text: String, into target: DictationTarget) -> Bool
    func discard(_ target: DictationTarget)
}

protocol FinalTextPreparing: Sendable {
    func prepare(_ rawText: String, mode: DictationMode) async throws -> String
}

protocol DictationClock: Sendable {
    func sleep(for duration: Duration) async throws
}

enum AppDependencyError: Error, Equatable, Sendable {
    case invalidAccessToken
}

enum DictationBackend: Equatable, Sendable {
    case txchatCloud
    case custom
}

struct DictationStreamingSession: Sendable {
    let client: any DictationStreamingServing
    let accessToken: String
    let backend: DictationBackend
}

struct VerbatimFinalTextPreparer: FinalTextPreparing {
    func prepare(
        _ rawText: String,
        mode: DictationMode
    ) async throws -> String {
        rawText
    }
}

struct ContinuousDictationClock: DictationClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
struct AppDependencies {
    typealias CaptureFactory = () -> any DictationAudioCapturing
    typealias StreamingFactory = () -> any DictationStreamingServing
    typealias StreamingSessionFactory = @MainActor () async throws ->
        DictationStreamingSession

    let captureFactory: CaptureFactory
    let streamingSessionFactory: StreamingSessionFactory
    let targetHandler: any DictationTargetHandling
    let finalPreparer: any FinalTextPreparing
    let clock: any DictationClock
    let maximumDuration: Duration

    init(
        accessTokenProvider: any DictationAccessTokenProviding,
        captureFactory: @escaping CaptureFactory,
        streamingFactory: @escaping StreamingFactory,
        targetHandler: any DictationTargetHandling,
        finalPreparer: any FinalTextPreparing = VerbatimFinalTextPreparer(),
        clock: any DictationClock = ContinuousDictationClock(),
        maximumDuration: Duration = .seconds(
            TxChatPublicLocalContract.audioMaxDurationSeconds
        )
    ) {
        self.captureFactory = captureFactory
        self.streamingSessionFactory = {
            let token = try await Self.validatedAccessToken(
                from: accessTokenProvider
            )
            return DictationStreamingSession(
                client: streamingFactory(),
                accessToken: token,
                backend: .txchatCloud
            )
        }
        self.targetHandler = targetHandler
        self.finalPreparer = finalPreparer
        self.clock = clock
        self.maximumDuration = maximumDuration
    }

    init(
        captureFactory: @escaping CaptureFactory,
        streamingSessionFactory: @escaping StreamingSessionFactory,
        targetHandler: any DictationTargetHandling,
        finalPreparer: any FinalTextPreparing = VerbatimFinalTextPreparer(),
        clock: any DictationClock = ContinuousDictationClock(),
        maximumDuration: Duration = .seconds(
            TxChatPublicLocalContract.audioMaxDurationSeconds
        )
    ) {
        self.captureFactory = captureFactory
        self.streamingSessionFactory = streamingSessionFactory
        self.targetHandler = targetHandler
        self.finalPreparer = finalPreparer
        self.clock = clock
        self.maximumDuration = maximumDuration
    }

    nonisolated static func validatedAccessToken(
        from provider: any DictationAccessTokenProviding
    ) async throws -> String {
        let token = try await provider.accessToken()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !token.isEmpty,
            token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw AppDependencyError.invalidAccessToken
        }
        return token
    }
}

extension CoreAudioCapture: DictationAudioCapturing {}
extension StreamingDictationClient: DictationStreamingServing {}
