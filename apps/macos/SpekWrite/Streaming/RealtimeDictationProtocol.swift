import Foundation

enum RealtimeSessionMode: String, Equatable, Sendable {
    case smart
    case verbatim
    case dictation
}

extension RealtimeSessionMode {
    init(_ mode: DictationMode) {
        switch mode {
        case .smart:
            self = .smart
        case .verbatim:
            self = .verbatim
        }
    }
}

enum RealtimeFinalResultMode: String, Equatable, Sendable {
    case smart
    case verbatim
    case verbatimFallback = "verbatim_fallback"
}

enum RealtimeFallbackReason: String, Equatable, Sendable {
    case textOptimizationTimeout = "text_optimization_timeout"
    case textOptimizationProviderFailed = "text_optimization_provider_failed"
    case textOptimizationEmptyResult = "text_optimization_empty_result"
    case textOptimizationFidelityRejected = "text_optimization_fidelity_rejected"
    case textOptimizationFailed = "text_optimization_failed"
}

enum RealtimeClientControl: Equatable, Sendable, Encodable {
    case start(
        RealtimeSessionMode = .dictation,
        prompt: TextOptimizationPrompt? = nil
    )
    case finish
    case cancel

    private enum CodingKeys: String, CodingKey {
        case type
        case `protocol`
        case audio
        case organizationMode
    }

    private struct Audio: Encodable {
        let encoding = "pcm_s16le"
        let sampleRate = 16_000
        let channels = 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            RealtimeProtocolCodec.protocolIdentifier,
            forKey: .protocol
        )
        switch self {
        case .start(let mode, let prompt):
            guard (mode == .smart) == (prompt != nil) else {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Smart mode requires a local prompt"
                    )
                )
            }
            let organizationMode = mode == .smart ? "smart" : "verbatim"
            try container.encode("start", forKey: .type)
            try container.encode(Audio(), forKey: .audio)
            try container.encode(organizationMode, forKey: .organizationMode)
        case .finish:
            try container.encode("finish", forKey: .type)
        case .cancel:
            try container.encode("cancel", forKey: .type)
        }
    }
}

enum RealtimeFailureCode: String, CaseIterable, Sendable {
    case invalidAudio = "invalid_audio"
    case invalidMessage = "invalid_message"
    case invalidSequence = "invalid_sequence"
    case limitExceeded = "limit_exceeded"
}

enum RealtimeServerControl: Equatable, Sendable {
    case started
    case partial(text: String)
    case organizing
    case publicLocalFinal(transcript: String, organizedText: String)
    case final(text: String)
    case finalResult(text: String, mode: RealtimeFinalResultMode)
    case finalFallback(text: String, reason: RealtimeFallbackReason)
    case failed(code: RealtimeFailureCode)
    case ended
}

enum RealtimeProtocolError: Error, Equatable, Sendable {
    case invalidMessage
}

enum RealtimeDictationError: Error, Equatable, Sendable {
    case invalidState
    case invalidAudioFrame
    case audioLimitExceeded
    case authRequired
    case sessionReplaced
    case sessionExpired
    case accountDisabled
    case tooManyRequests
    case protocolViolation
    case serviceUnavailable
    case finalTimeout
    case cancelled

    init(serverFailure: RealtimeFailureCode) {
        switch serverFailure {
        case .invalidAudio:
            self = .invalidAudioFrame
        case .invalidMessage, .invalidSequence:
            self = .protocolViolation
        case .limitExceeded:
            self = .audioLimitExceeded
        }
    }
}

enum RealtimeProtocolCodec {
    static let protocolIdentifier = TxChatPublicLocalContract.protocolIdentifier
    static let maximumMessageBytes = 65_536
    static let maximumTranscriptCodePoints = 4_096

    static func encode(_ control: RealtimeClientControl) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(control)
    }

    static func decodeServer(_ data: Data) throws -> RealtimeServerControl {
        guard !data.isEmpty, data.count <= maximumMessageBytes else {
            throw RealtimeProtocolError.invalidMessage
        }
        let candidate: Any
        do {
            candidate = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw RealtimeProtocolError.invalidMessage
        }
        guard
            let object = candidate as? [String: Any],
            object["protocol"] as? String == protocolIdentifier,
            let type = object["type"] as? String
        else {
            throw RealtimeProtocolError.invalidMessage
        }

        switch type {
        case "started":
            try requireKeys(object, exactly: ["protocol", "type"])
            return .started
        case "partial":
            try requireKeys(
                object,
                exactly: ["protocol", "type", "transcript"]
            )
            return .partial(text: try transcript(object["transcript"]))
        case "organizing":
            try requireKeys(object, exactly: ["protocol", "type"])
            return .organizing
        case "final":
            try requireKeys(
                object,
                exactly: [
                    "protocol", "type", "transcript", "organizedText",
                ]
            )
            return .publicLocalFinal(
                transcript: try transcript(object["transcript"]),
                organizedText: try transcript(object["organizedText"])
            )
        case "failed":
            try requireKeys(
                object,
                exactly: ["protocol", "type", "code"]
            )
            guard let rawCode = object["code"] as? String,
                  let code = RealtimeFailureCode(rawValue: rawCode)
            else {
                throw RealtimeProtocolError.invalidMessage
            }
            return .failed(code: code)
        case "ended":
            try requireKeys(
                object,
                exactly: ["protocol", "type", "reason"]
            )
            guard let reason = object["reason"] as? String,
                  ["cancelled", "completed", "failed"].contains(reason)
            else {
                throw RealtimeProtocolError.invalidMessage
            }
            return .ended
        default:
            throw RealtimeProtocolError.invalidMessage
        }
    }

    private static func requireKeys(
        _ object: [String: Any],
        exactly expected: Set<String>
    ) throws {
        guard Set(object.keys) == expected else {
            throw RealtimeProtocolError.invalidMessage
        }
    }

    private static func transcript(_ candidate: Any?) throws -> String {
        guard let value = candidate as? String else {
            throw RealtimeProtocolError.invalidMessage
        }
        var codePoints = 0
        for scalar in value.unicodeScalars {
            codePoints += 1
            let code = scalar.value
            let disallowed =
                (code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D) ||
                (code >= 0x7F && code <= 0x9F)
            if codePoints > maximumTranscriptCodePoints || disallowed {
                throw RealtimeProtocolError.invalidMessage
            }
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RealtimeProtocolError.invalidMessage
        }
        return value
    }
}
