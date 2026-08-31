import Foundation

enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case application
    case authentication
    case dictation
    case insertion
    case customASR = "custom_asr"
    case customOptimization = "custom_optimization"
}

enum DiagnosticStage: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case sessionRestore = "session_restore"
    case sessionInstall = "session_install"
    case sessionDelete = "session_delete"
    case capturePreflight = "capture_preflight"
    case captureStart = "capture_start"
    case streamStart = "stream_start"
    case audioPump = "audio_pump"
    case streamFinish = "stream_finish"
    case finalPreparation = "final_preparation"
    case targetCapture = "target_capture"
    case clipboardTransaction = "clipboard_transaction"
    case eventDelivery = "event_delivery"
    case providerConfiguration = "provider_configuration"
    case providerTest = "provider_test"
    case providerRequest = "provider_request"
    case providerResponse = "provider_response"
}

enum DiagnosticCode: String, Codable, CaseIterable, Sendable {
    case abnormalExit = "ABNORMAL_EXIT"
    case localStateReadFailed = "LOCAL_STATE_READ_FAILED"
    case localStateWriteFailed = "LOCAL_STATE_WRITE_FAILED"
    case localStateDeleteFailed = "LOCAL_STATE_DELETE_FAILED"
    case protocolViolation = "PROTOCOL_VIOLATION"
    case audioConversionFailed = "AUDIO_CONVERSION_FAILED"
    case audioBufferOverflow = "AUDIO_BUFFER_OVERFLOW"
    case captureInternalFailure = "CAPTURE_INTERNAL_FAILURE"
    case insertionTransactionBusy = "INSERTION_TRANSACTION_BUSY"
    case pasteboardSnapshotFailed = "PASTEBOARD_SNAPSHOT_FAILED"
    case pasteboardWriteFailed = "PASTEBOARD_WRITE_FAILED"
    case pasteEventFailed = "PASTE_EVENT_FAILED"
    case providerConfigurationInvalid = "PROVIDER_CONFIGURATION_INVALID"
    case providerProtocolViolation = "PROVIDER_PROTOCOL_VIOLATION"
    case internalError = "INTERNAL_ERROR"
}

enum DiagnosticPermissionState: String, Codable, CaseIterable, Sendable {
    case authorized
    case denied
    case notDetermined = "not_determined"
    case restricted
    case unknown
}

enum DiagnosticServiceMode: String, Codable, CaseIterable, Sendable {
    case txchatCloud = "txchat_cloud"
    case custom
}

enum DiagnosticLocale: String, Codable, CaseIterable, Sendable {
    case zhHans = "zh-Hans"
    case en
}

enum DiagnosticArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64
    case x86_64
    case unknown
}

struct DiagnosticTimestamp: RawRepresentable, Codable, Equatable,
    Hashable, Sendable
{
    let rawValue: String

    init?(rawValue: String) {
        guard Self.isCanonical(rawValue) else {
            return nil
        }
        self.rawValue = rawValue
    }

    init(date: Date) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        rawValue = formatter.string(from: date)
    }

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter.date(from: rawValue)
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard Self.isCanonical(value) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Diagnostic timestamp is not canonical UTC milliseconds."
                )
            )
        }
        rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        guard Self.isCanonical(rawValue) else {
            throw EncodingError.invalidValue(
                rawValue,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Diagnostic timestamp is not canonical UTC milliseconds."
                )
            )
        }
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isCanonical(_ value: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        guard let date = formatter.date(from: value) else { return false }
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date) == value
    }
}

struct DiagnosticConsent: Codable, Equatable, Sendable {
    let promptVersion: Int
    let confirmedAt: DiagnosticTimestamp
}

struct DiagnosticApp: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let locale: DiagnosticLocale
    let architecture: DiagnosticArchitecture
}

struct DiagnosticSystem: Codable, Equatable, Sendable {
    let macOSVersion: String
    let microphone: DiagnosticPermissionState
    let accessibility: DiagnosticPermissionState
}

struct DiagnosticService: Codable, Equatable, Sendable {
    let mode: DiagnosticServiceMode
}

struct DiagnosticIncident: Codable, Equatable, Sendable {
    let category: DiagnosticCategory
    let taskId: UUID?
    let stage: DiagnosticStage
    let code: DiagnosticCode
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    let occurredAt: DiagnosticTimestamp
    let category: DiagnosticCategory
    let taskId: UUID?
    let stage: DiagnosticStage
    let code: DiagnosticCode
    let durationMs: Int?
    let httpStatus: Int?
}

struct DiagnosticReportEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let reportId: UUID
    let installationId: UUID
    let consent: DiagnosticConsent
    let occurredAt: DiagnosticTimestamp
    let app: DiagnosticApp
    let system: DiagnosticSystem
    let service: DiagnosticService
    let incident: DiagnosticIncident
    let events: [DiagnosticEvent]
}

enum DiagnosticEnvelopeValidationError: Error, Equatable, Sendable {
    case schemaVersion
    case promptVersion
    case appVersion
    case build
    case macOSVersion
    case eventCount
    case duration
    case httpStatus
    case timestamp
    case timeOrdering
    case incidentExpired
    case encodedTooLarge
}

enum DiagnosticEnvelopeValidator {
    private static let maximumEncodedBytes = 65_536
    private static let maximumClockSkew: TimeInterval = 5 * 60
    private static let retention: TimeInterval = 7 * 86_400

    static func validate(
        _ report: DiagnosticReportEnvelope,
        now: Date
    ) throws {
        let encoded: Data
        do {
            encoded = try DiagnosticJSONCodec.encode(report)
        } catch {
            throw DiagnosticEnvelopeValidationError.timestamp
        }
        guard encoded.count <= maximumEncodedBytes else {
            throw DiagnosticEnvelopeValidationError.encodedTooLarge
        }
        guard report.schemaVersion == 1 else {
            throw DiagnosticEnvelopeValidationError.schemaVersion
        }
        guard report.consent.promptVersion == 1 else {
            throw DiagnosticEnvelopeValidationError.promptVersion
        }
        guard isNumericDottedVersion(report.app.version) else {
            throw DiagnosticEnvelopeValidationError.appVersion
        }
        guard isASCIIInteger(report.app.build, maximumLength: 18) else {
            throw DiagnosticEnvelopeValidationError.build
        }
        guard isNumericDottedVersion(report.system.macOSVersion) else {
            throw DiagnosticEnvelopeValidationError.macOSVersion
        }
        guard report.events.count <= 20 else {
            throw DiagnosticEnvelopeValidationError.eventCount
        }

        let occurredAt = try date(report.occurredAt)
        let confirmedAt = try date(report.consent.confirmedAt)
        guard occurredAt <= confirmedAt,
              confirmedAt <= now.addingTimeInterval(maximumClockSkew) else {
            throw DiagnosticEnvelopeValidationError.timeOrdering
        }
        guard occurredAt >= now.addingTimeInterval(-retention) else {
            throw DiagnosticEnvelopeValidationError.incidentExpired
        }

        for event in report.events {
            let eventDate = try date(event.occurredAt)
            guard eventDate <= confirmedAt else {
                throw DiagnosticEnvelopeValidationError.timeOrdering
            }
            if let duration = event.durationMs,
               !(0...3_600_000).contains(duration) {
                throw DiagnosticEnvelopeValidationError.duration
            }
            if let status = event.httpStatus,
               !(100...599).contains(status) {
                throw DiagnosticEnvelopeValidationError.httpStatus
            }
        }
    }

    private static func date(_ timestamp: DiagnosticTimestamp) throws -> Date {
        guard DiagnosticTimestamp(rawValue: timestamp.rawValue) == timestamp,
              let value = timestamp.date else {
            throw DiagnosticEnvelopeValidationError.timestamp
        }
        return value
    }

    private static func isNumericDottedVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(segments.count) else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.utf8.allSatisfy {
                (48...57).contains($0)
            }
        }
    }

    private static func isASCIIInteger(
        _ value: String,
        maximumLength: Int
    ) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumLength &&
            value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

struct DiagnosticReportSuccess: Codable, Equatable, Sendable {
    let diagnosticNumber: String
    let reportId: UUID
    let receivedAt: DiagnosticTimestamp
}

enum DiagnosticJSONCodec {
    enum ValidationError: Error, Equatable {
        case invalidShape
        case additionalProperty(String)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        if type == DiagnosticReportEnvelope.self {
            try validateReportShape(data)
        } else if type == DiagnosticReportSuccess.self {
            try validateObject(
                try jsonObject(data),
                keys: ["diagnosticNumber", "reportId", "receivedAt"]
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func validateReportShape(_ data: Data) throws {
        let report = try jsonObject(data)
        try validateObject(
            report,
            keys: [
                "schemaVersion", "reportId", "installationId", "consent",
                "occurredAt", "app", "system", "service", "incident",
                "events",
            ]
        )
        let dictionary = try dictionary(report)
        try validateObject(
            dictionary["consent"],
            keys: ["promptVersion", "confirmedAt"]
        )
        try validateObject(
            dictionary["app"],
            keys: ["version", "build", "locale", "architecture"]
        )
        try validateObject(
            dictionary["system"],
            keys: ["macOSVersion", "microphone", "accessibility"]
        )
        try validateObject(dictionary["service"], keys: ["mode"])
        try validateObject(
            dictionary["incident"],
            keys: ["category", "taskId", "stage", "code"]
        )
        guard let events = dictionary["events"] as? [Any], events.count <= 20 else {
            throw ValidationError.invalidShape
        }
        for event in events {
            try validateObject(
                event,
                keys: [
                    "occurredAt", "category", "taskId", "stage", "code",
                    "durationMs", "httpStatus",
                ]
            )
        }
    }

    private static func jsonObject(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private static func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw ValidationError.invalidShape
        }
        return value
    }

    private static func validateObject(
        _ value: Any?,
        keys: Set<String>
    ) throws {
        let value = try dictionary(value)
        if let unexpected = Set(value.keys).subtracting(keys).sorted().first {
            throw ValidationError.additionalProperty(unexpected)
        }
    }
}

enum DiagnosticFailureSignal: Hashable, Sendable {
    case abnormalExit
    case protocolViolation(
        category: DiagnosticCategory,
        stage: DiagnosticStage
    )
    case audioConversionFailed
    case audioBufferOverflow
    case captureInternalFailure
    case localStateReadFailed
    case localStateWriteFailed
    case localStateDeleteFailed
    case insertionTransactionBusy
    case pasteboardSnapshotFailed
    case pasteboardWriteFailed
    case pasteEventFailed
    case providerConfigurationInvalid
    case providerProtocolViolation
    case providerInternalFailure
    case networkUnavailable
    case requestTimeout
    case serviceUnavailable
    case rateLimited
    case invalidOTP
    case authenticationFailed
    case permissionDenied
    case nearSpeechNotDetected
    case targetMissing
    case windowChanged
    case userCancelled
    case maximumDurationReached
    case asrFailed
    case optimizationFailedWithRawFallback
}

enum DiagnosticClassifier {
    static func incident(
        for signal: DiagnosticFailureSignal,
        taskId: UUID? = nil
    ) -> DiagnosticIncident? {
        let classification: (
            DiagnosticCategory,
            DiagnosticStage,
            DiagnosticCode
        )
        switch signal {
        case .abnormalExit:
            classification = (.application, .lifecycle, .abnormalExit)
        case .protocolViolation(let category, let stage):
            classification = (category, stage, .protocolViolation)
        case .audioConversionFailed:
            classification = (.dictation, .audioPump, .audioConversionFailed)
        case .audioBufferOverflow:
            classification = (.dictation, .audioPump, .audioBufferOverflow)
        case .captureInternalFailure:
            classification = (.dictation, .captureStart, .captureInternalFailure)
        case .localStateReadFailed:
            classification = (.authentication, .sessionRestore, .localStateReadFailed)
        case .localStateWriteFailed:
            classification = (.authentication, .sessionInstall, .localStateWriteFailed)
        case .localStateDeleteFailed:
            classification = (.authentication, .sessionDelete, .localStateDeleteFailed)
        case .insertionTransactionBusy:
            classification = (.insertion, .clipboardTransaction, .insertionTransactionBusy)
        case .pasteboardSnapshotFailed:
            classification = (.insertion, .clipboardTransaction, .pasteboardSnapshotFailed)
        case .pasteboardWriteFailed:
            classification = (.insertion, .clipboardTransaction, .pasteboardWriteFailed)
        case .pasteEventFailed:
            classification = (.insertion, .eventDelivery, .pasteEventFailed)

        case .providerConfigurationInvalid:
            classification = (.customASR, .providerConfiguration, .providerConfigurationInvalid)
        case .providerProtocolViolation:
            classification = (.customASR, .providerResponse, .providerProtocolViolation)
        case .providerInternalFailure:
            classification = (.customOptimization, .providerRequest, .internalError)
        case .networkUnavailable, .requestTimeout, .serviceUnavailable,
             .rateLimited, .invalidOTP, .authenticationFailed,
             .permissionDenied, .nearSpeechNotDetected, .targetMissing,
             .windowChanged, .userCancelled, .maximumDurationReached,
             .asrFailed, .optimizationFailedWithRawFallback:
            return nil
        }
        return DiagnosticIncident(
            category: classification.0,
            taskId: taskId,
            stage: classification.1,
            code: classification.2
        )
    }
}
