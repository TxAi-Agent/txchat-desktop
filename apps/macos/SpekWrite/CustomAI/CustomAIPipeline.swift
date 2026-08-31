import Foundation

protocol CustomAIASRServing: Sendable {
    func transcribe(
        wavAudio: Data,
        selection: CustomAIRuntimeSelection
    ) async throws -> String
}

protocol CustomAIOptimizationServing: Sendable {
    func optimize(
        rawText: String,
        prompt: TextOptimizationPrompt,
        selection: CustomAIRuntimeSelection
    ) async throws -> String
}

enum CustomAIPipelineError: Error, Equatable, Sendable {
    case invalidState
    case invalidAudio
    case audioLimitExceeded
    case emptyASRResult
}

struct CustomAIDiagnosticError: Error, Equatable, Sendable {
    let category: DiagnosticCategory
    let stage: DiagnosticStage
    let code: DiagnosticCode

    static func reportableASRFailure(_ error: Error) -> Error {
        guard let providerError = error as? CustomAIProviderError else {
            return error
        }
        switch providerError {
        case .invalidConfiguration, .unsupportedProvider,
             .unapprovedEndpoint:
            return CustomAIDiagnosticError(
                category: .customASR,
                stage: .providerConfiguration,
                code: .providerConfigurationInvalid
            )
        case .invalidRequest:
            return CustomAIDiagnosticError(
                category: .customASR,
                stage: .providerRequest,
                code: .internalError
            )
        case .unusableAudio:
            return CustomAIDiagnosticError(
                category: .customASR,
                stage: .providerRequest,
                code: .providerProtocolViolation
            )
        case .invalidResponse, .responseTooLarge:
            return CustomAIDiagnosticError(
                category: .customASR,
                stage: .providerResponse,
                code: .providerProtocolViolation
            )
        case .httpStatus:
            return error
        }
    }

    static func configurationFailure(
        _ error: Error
    ) -> CustomAIDiagnosticError {
        let category: DiagnosticCategory
        if case let CustomAIRuntimeConfigurationError.missingRequiredField(
            serviceCategory, _, _
        ) = error {
            category = serviceCategory == .asr
                ? .customASR
                : .customOptimization
        } else {
            category = .customASR
        }
        return CustomAIDiagnosticError(
            category: category,
            stage: .providerConfiguration,
            code: .providerConfigurationInvalid
        )
    }
}

enum CustomAIWAVBuilder {
    static let sampleRate: UInt32 = 16_000
    static let channels: UInt16 = 1
    static let bitsPerSample: UInt16 = 16

    static func build(pcm16Mono pcm: Data) throws -> Data {
        guard !pcm.isEmpty,
              pcm.count.isMultiple(of: 2),
              pcm.count <= Int(UInt32.max) - 36 else {
            throw CustomAIPipelineError.invalidAudio
        }
        let byteRate = sampleRate * UInt32(channels) *
            UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        var result = Data()
        result.reserveCapacity(44 + pcm.count)
        result.appendASCII("RIFF")
        result.appendLittleEndian(UInt32(36 + pcm.count))
        result.appendASCII("WAVE")
        result.appendASCII("fmt ")
        result.appendLittleEndian(UInt32(16))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(channels)
        result.appendLittleEndian(sampleRate)
        result.appendLittleEndian(byteRate)
        result.appendLittleEndian(blockAlign)
        result.appendLittleEndian(bitsPerSample)
        result.appendASCII("data")
        result.appendLittleEndian(UInt32(pcm.count))
        result.append(pcm)
        return result
    }
}

actor CustomAIStreamingClient: DictationStreamingServing {
    typealias PromptLoader = @Sendable () throws -> TextOptimizationPrompt

    private enum State {
        case idle
        case started
        case finishing
        case finished
        case cancelled
    }

    private let configuration: CustomAIRuntimeConfiguration
    private let asr: any CustomAIASRServing
    private let optimizer: any CustomAIOptimizationServing
    private let promptLoader: PromptLoader
    private let maximumPCMBytes: Int
    private var state = State.idle
    private var mode = RealtimeSessionMode.smart
    private var onOrganizing: OrganizingHandler = {}
    private var pcm = Data()
    private var operation: Task<DictationStreamingResult, Error>?

    init(
        configuration: CustomAIRuntimeConfiguration,
        asr: any CustomAIASRServing,
        optimizer: any CustomAIOptimizationServing,
        promptLoader: @escaping PromptLoader = {
            try BuiltInTextOptimizationPrompt.loadCurrent()
        },
        maximumPCMBytes: Int = 9_600_000
    ) {
        self.configuration = configuration
        self.asr = asr
        self.optimizer = optimizer
        self.promptLoader = promptLoader
        self.maximumPCMBytes = maximumPCMBytes
        pcm.reserveCapacity(min(maximumPCMBytes, 1_048_576))
    }

    func start(
        accessToken: String,
        onPartial: @escaping StreamingDictationClient.PartialHandler
    ) async throws {
        try await start(
            accessToken: accessToken,
            mode: .verbatim,
            onPartial: onPartial,
            onOrganizing: {}
        )
    }

    func start(
        accessToken: String,
        mode: RealtimeSessionMode,
        onPartial: @escaping StreamingDictationClient.PartialHandler,
        onOrganizing: @escaping OrganizingHandler
    ) async throws {
        _ = accessToken
        _ = onPartial
        guard state == .idle else {
            throw CustomAIPipelineError.invalidState
        }
        self.mode = mode
        self.onOrganizing = onOrganizing
        state = .started
    }

    func send(audio: Data) async throws {
        guard state == .started,
              !audio.isEmpty,
              audio.count.isMultiple(of: 2),
              audio.count <= CoreRecordingLimits.maximumFrameBytes else {
            throw CustomAIPipelineError.invalidAudio
        }
        guard pcm.count <= maximumPCMBytes - audio.count else {
            throw CustomAIPipelineError.audioLimitExceeded
        }
        pcm.append(audio)
    }

    func finish() async throws -> String {
        (try await finishResult()).text
    }

    func finishResult() async throws -> DictationStreamingResult {
        guard state == .started, !pcm.isEmpty else {
            throw CustomAIPipelineError.invalidState
        }
        state = .finishing
        let wav = try CustomAIWAVBuilder.build(pcm16Mono: pcm)
        pcm.removeAll(keepingCapacity: false)
        let mode = self.mode
        let configuration = self.configuration
        let asr = self.asr
        let optimizer = self.optimizer
        let promptLoader = self.promptLoader
        let onOrganizing = self.onOrganizing
        let task = Task<DictationStreamingResult, Error> {
            let raw: String
            do {
                raw = try await asr.transcribe(
                    wavAudio: wav,
                    selection: configuration.asr
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw CustomAIDiagnosticError.reportableASRFailure(error)
            }
            try Task.checkCancellation()
            guard !raw.isEmpty else {
                throw CustomAIDiagnosticError(
                    category: .customASR,
                    stage: .providerResponse,
                    code: .providerProtocolViolation
                )
            }
            guard mode == .smart else {
                return DictationStreamingResult(
                    text: raw,
                    mode: .verbatim
                )
            }
            await onOrganizing()
            do {
                let prompt = try promptLoader()
                let optimized = try await optimizer.optimize(
                    rawText: raw,
                    prompt: prompt,
                    selection: configuration.optimization
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !optimized.isEmpty else {
                    return DictationStreamingResult(
                        text: raw,
                        mode: .verbatimFallback,
                        fallbackReason: .textOptimizationEmptyResult
                    )
                }
                return DictationStreamingResult(
                    text: optimized,
                    mode: .smart
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return DictationStreamingResult(
                    text: raw,
                    mode: .verbatimFallback,
                    fallbackReason: .textOptimizationProviderFailed
                )
            }
        }
        operation = task
        do {
            let result = try await task.value
            guard state == .finishing else {
                throw CancellationError()
            }
            state = .finished
            operation = nil
            return result
        } catch {
            operation = nil
            if state == .finishing {
                state = .finished
            }
            throw error
        }
    }

    func cancel() async {
        operation?.cancel()
        operation = nil
        pcm.removeAll(keepingCapacity: false)
        state = .cancelled
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
