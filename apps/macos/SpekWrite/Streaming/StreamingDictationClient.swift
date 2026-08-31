import Foundation

enum StreamingDictationClientState: Equatable, Sendable {
    case idle
    case starting
    case streaming
    case finishing
    case ended
}

actor StreamingDictationClient {
    typealias PartialHandler = @Sendable (String) async -> Void
    typealias PromptLoader = @Sendable () throws -> TextOptimizationPrompt

    private static let maximumFrameBytes = 6_400
    private static let maximumAudioBytes = 9_600_000

    private let transport: any RealtimeDictationTransport
    private let promptLoader: PromptLoader
    private var totalAudioBytes = 0
    private var finalResult: DictationStreamingResult?
    private var pendingFailure: RealtimeDictationError?
    private var terminalOutcome: Result<DictationStreamingResult, Error>?
    private var terminalContinuation:
        CheckedContinuation<DictationStreamingResult, Error>?
    private var receiverTask: Task<Void, Never>?
    private var partialHandler: PartialHandler?
    private var organizingHandler: OrganizingHandler?
    private var requestedMode: RealtimeSessionMode?
    private var organizingReceived = false

    private(set) var state = StreamingDictationClientState.idle

    init(
        transport: any RealtimeDictationTransport,
        promptLoader: @escaping PromptLoader = {
            try BuiltInTextOptimizationPrompt.loadCurrent()
        }
    ) {
        self.transport = transport
        self.promptLoader = promptLoader
    }

    func start(accessToken: String) async throws {
        try await start(
            accessToken: accessToken,
            mode: .dictation,
            onPartial: { _ in }
        )
    }

    func start(
        accessToken: String,
        onPartial: @escaping PartialHandler
    ) async throws {
        try await start(
            accessToken: accessToken,
            mode: .dictation,
            onPartial: onPartial
        )
    }

    func start(
        accessToken: String,
        mode: RealtimeSessionMode
    ) async throws {
        try await start(
            accessToken: accessToken,
            mode: mode,
            onPartial: { _ in }
        )
    }

    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping PartialHandler
    ) async throws {
        try await start(
            accessToken: accessToken,
            mode: mode,
            onPartial: onPartial,
            onOrganizing: {}
        )
    }

    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping PartialHandler,
        onOrganizing: @escaping OrganizingHandler
    ) async throws {
        guard state == .idle, !accessToken.isEmpty else {
            throw RealtimeDictationError.invalidState
        }
        partialHandler = onPartial
        organizingHandler = onOrganizing
        requestedMode = mode
        organizingReceived = false
        state = .starting
        do {
            let prompt = mode == .smart ? try promptLoader() : nil
            try await transport.connect(accessToken: accessToken)
            try await transport.send(
                control: .start(mode, prompt: prompt)
            )
            let response = try await transport.receive()
            switch response {
            case .started:
                state = .streaming
                receiverTask = Task { await self.receiveLoop() }
            case .failed(let code):
                let error = RealtimeDictationError(serverFailure: code)
                state = .ended
                partialHandler = nil
                organizingHandler = nil
                await transport.close()
                throw error
            default:
                state = .ended
                partialHandler = nil
                organizingHandler = nil
                await transport.close()
                throw RealtimeDictationError.protocolViolation
            }
        } catch let error as RealtimeDictationError {
            if state != .ended {
                state = .ended
                await transport.close()
            }
            partialHandler = nil
            organizingHandler = nil
            throw error
        } catch {
            state = .ended
            partialHandler = nil
            organizingHandler = nil
            await transport.close()
            throw RealtimeDictationError.serviceUnavailable
        }
    }

    func send(audio: Data) async throws {
        guard state == .streaming else {
            throw RealtimeDictationError.invalidState
        }
        guard
            !audio.isEmpty,
            audio.count <= Self.maximumFrameBytes,
            audio.count.isMultiple(of: 2)
        else {
            throw RealtimeDictationError.invalidAudioFrame
        }
        guard totalAudioBytes + audio.count <= Self.maximumAudioBytes else {
            throw RealtimeDictationError.audioLimitExceeded
        }
        var ownedFrame = Data(audio)
        defer {
            ownedFrame.resetBytes(in: 0..<ownedFrame.count)
        }
        do {
            try await transport.send(audio: ownedFrame)
            totalAudioBytes += ownedFrame.count
        } catch let error as RealtimeDictationError {
            throw error
        } catch {
            throw RealtimeDictationError.serviceUnavailable
        }
    }

    func finish() async throws -> String {
        try await finishResult().text
    }

    func finishResult() async throws -> DictationStreamingResult {
        guard state == .streaming else {
            throw RealtimeDictationError.invalidState
        }
        state = .finishing
        do {
            try await transport.send(control: .finish)
        } catch {
            await complete(.failure(map(error)))
        }
        if let terminalOutcome {
            return try terminalOutcome.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            terminalContinuation = continuation
        }
    }

    func cancel() async {
        guard state != .ended else {
            return
        }
        if state != .idle {
            try? await transport.send(control: .cancel)
        }
        await complete(.failure(RealtimeDictationError.cancelled))
    }

    private func receiveLoop() async {
        while state == .streaming || state == .finishing {
            let message: RealtimeServerControl
            do {
                message = try await transport.receive()
            } catch {
                await complete(.failure(map(error)))
                return
            }

            switch message {
            case .partial(let text):
                guard
                    finalResult == nil,
                    pendingFailure == nil,
                    !organizingReceived
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                if let partialHandler {
                    await partialHandler(text)
                }
                continue
            case .organizing:
                guard
                    state == .finishing,
                    !organizingReceived,
                    finalResult == nil,
                    pendingFailure == nil
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                organizingReceived = true
                if requestedMode == .smart, let organizingHandler {
                    await organizingHandler()
                }
                continue
            case .publicLocalFinal(_, let organizedText):
                guard
                    state == .finishing,
                    let requestedMode,
                    finalResult == nil,
                    pendingFailure == nil,
                    requestedMode != .smart || organizingReceived
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                let resultMode: RealtimeFinalResultMode?
                switch requestedMode {
                case .smart:
                    resultMode = .smart
                case .verbatim:
                    resultMode = .verbatim
                case .dictation:
                    resultMode = nil
                }
                finalResult = DictationStreamingResult(
                    text: organizedText,
                    mode: resultMode
                )
            case .final(let text):
                guard
                    state == .finishing,
                    requestedMode == .dictation,
                    !organizingReceived,
                    finalResult == nil,
                    pendingFailure == nil
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                finalResult = DictationStreamingResult(
                    text: text,
                    mode: nil
                )
            case .finalResult(let text, let mode):
                guard
                    state == .finishing,
                    validFinalResultMode(mode),
                    finalResult == nil,
                    pendingFailure == nil
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                finalResult = DictationStreamingResult(
                    text: text,
                    mode: requestedMode == .dictation ? nil : mode
                )
            case .finalFallback(let text, let reason):
                guard
                    state == .finishing,
                    requestedMode == .smart,
                    organizingReceived,
                    finalResult == nil,
                    pendingFailure == nil
                else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                finalResult = DictationStreamingResult(
                    text: text,
                    mode: .verbatimFallback,
                    fallbackReason: reason
                )
            case .failed(let code):
                guard pendingFailure == nil, finalResult == nil else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                    return
                }
                pendingFailure = RealtimeDictationError(serverFailure: code)
            case .ended:
                if let pendingFailure {
                    await complete(.failure(pendingFailure))
                } else if let finalResult, state == .finishing {
                    await complete(.success(finalResult))
                } else {
                    await complete(
                        .failure(RealtimeDictationError.protocolViolation)
                    )
                }
                return
            case .started:
                await complete(
                    .failure(RealtimeDictationError.protocolViolation)
                )
                return
            }
        }
    }

    private func complete(
        _ outcome: Result<DictationStreamingResult, Error>
    ) async {
        guard state != .ended else {
            return
        }
        state = .ended
        partialHandler = nil
        organizingHandler = nil
        requestedMode = nil
        organizingReceived = false
        terminalOutcome = outcome
        let continuation = terminalContinuation
        terminalContinuation = nil
        receiverTask?.cancel()
        receiverTask = nil
        await transport.close()
        continuation?.resume(with: outcome)
    }

    private func validFinalResultMode(
        _ resultMode: RealtimeFinalResultMode
    ) -> Bool {
        switch requestedMode {
        case .smart:
            return organizingReceived && resultMode == .smart
        case .verbatim:
            return !organizingReceived && resultMode == .verbatim
        case .dictation:
            return !organizingReceived && resultMode == .verbatim
        case .none:
            return false
        }
    }

    private func map(_ error: Error) -> RealtimeDictationError {
        if let realtimeError = error as? RealtimeDictationError {
            return realtimeError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .serviceUnavailable
    }
}
