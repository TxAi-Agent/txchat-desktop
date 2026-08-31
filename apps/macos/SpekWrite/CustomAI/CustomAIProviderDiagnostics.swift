import Foundation

enum CustomAIProviderStage: String, Equatable, Sendable {
    case asr
    case optimization
}

struct CustomAIProviderFailure: Error, Equatable, Sendable {
    let stage: CustomAIProviderStage
    let category: CustomAITestFailureCategory
    let httpStatus: Int?
    let providerCode: String?
    let requestID: String?

    static func make(
        stage: CustomAIProviderStage,
        category: CustomAITestFailureCategory,
        httpStatus: Int?,
        providerCode: String?,
        requestID: String?
    ) -> CustomAIProviderFailure? {
        guard httpStatus.map({ (100...599).contains($0) }) ?? true else {
            return nil
        }
        return .init(
            stage: stage,
            category: category,
            httpStatus: httpStatus,
            providerCode: providerCode.flatMap(sanitizedProviderCode),
            requestID: requestID.flatMap(sanitizedIdentifier)
        )
    }

    static func sanitizedProviderCode(_ value: String) -> String? {
        guard value.utf8.count <= 64,
              let sanitized = sanitizedIdentifier(value) else {
            return nil
        }
        let lowercase = sanitized.lowercased()
        let forbiddenPrefixes = ["sk-", "ltai", "bearer", "ak-"]
        guard !forbiddenPrefixes.contains(where: lowercase.hasPrefix) else {
            return nil
        }
        return sanitized
    }

    static func sanitizedIdentifier(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.count <= 128 else {
            return nil
        }
        let allowed = CharacterSet(
            charactersIn:
                "abcdefghijklmnopqrstuvwxyz" +
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                "0123456789-_.:"
        )
        guard value.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return value
    }
}

enum CustomAIProviderFailureParser {
    static func failure(
        stage: CustomAIProviderStage,
        providerID: String,
        response: CustomAIHTTPResponse,
        providerCode: String? = nil,
        category: CustomAITestFailureCategory? = nil
    ) -> CustomAIProviderFailure {
        let object = (try? JSONSerialization.jsonObject(with: response.body))
            as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let extractedCode = providerCode ?? code(
            stage: stage,
            providerID: providerID,
            response: response,
            object: object,
            error: error
        )
        let requestID = string(object?["request_id"])
            ?? header("x-request-id", response: response)
            ?? header("request-id", response: response)
            ?? header("x-tt-logid", response: response)
        return CustomAIProviderFailure.make(
            stage: stage,
            category: category ?? failureCategory(
                status: response.statusCode,
                providerCode: extractedCode
            ),
            httpStatus: response.statusCode,
            providerCode: extractedCode,
            requestID: requestID
        ) ?? .init(
            stage: stage,
            category: .incompatibleResponse,
            httpStatus: nil,
            providerCode: nil,
            requestID: nil
        )
    }

    private static func code(
        stage: CustomAIProviderStage,
        providerID: String,
        response: CustomAIHTTPResponse,
        object: [String: Any]?,
        error: [String: Any]?
    ) -> String? {
        if stage == .asr,
           providerID == CustomAIASRProviderID.volcengine.rawValue {
            return header("x-api-status-code", response: response)
        }
        if stage == .asr,
           providerID == CustomAIASRProviderID.alibabaBailian.rawValue {
            return string(object?["code"])
        }
        return string(error?["code"]) ?? string(error?["type"])
    }

    private static func failureCategory(
        status: Int,
        providerCode: String?
    ) -> CustomAITestFailureCategory {
        let code = providerCode?.lowercased() ?? ""
        if status == 401 || code == "45000010" {
            return .authentication
        }
        if status == 403 || status == 404 {
            return .permissionOrModel
        }
        if code == "20000003" {
            return .audioSample
        }
        if code.hasPrefix("450") {
            return .invalidRequest
        }
        if code.hasPrefix("550") {
            return .network
        }
        if code.contains("invalidapikey") ||
            code.contains("invalid_api_key") ||
            code.contains("unauthorized") ||
            code.contains("authentication") {
            return .authentication
        }
        if code.contains("rate_limit") ||
            code.contains("ratelimit") ||
            code.contains("too_many_requests") {
            return .rateLimit
        }
        if code.contains("permission") ||
            code.contains("accessdenied") ||
            code.contains("model_not_found") {
            return .permissionOrModel
        }
        switch status {
        case 429:
            return .rateLimit
        case 400..<500:
            return .invalidRequest
        case 500...599:
            return .network
        default:
            return .incompatibleResponse
        }
    }

    private static func header(
        _ name: String,
        response: CustomAIHTTPResponse
    ) -> String? {
        response.headers.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Int:
            return String(value)
        default:
            return nil
        }
    }
}

struct CustomAITestStageFailure: Error, Equatable, Sendable {
    let stage: CustomAIProviderStage
    let category: CustomAITestFailureCategory
    let providerFailure: CustomAIProviderFailure?
}

enum CustomAITestFailureClassifier {
    static func failure(
        _ error: Error,
        stage: CustomAIProviderStage
    ) -> CustomAITestStageFailure {
        if let staged = error as? CustomAITestStageFailure {
            return staged
        }
        if let provider = error as? CustomAIProviderFailure {
            return .init(
                stage: provider.stage,
                category: provider.category,
                providerFailure: provider
            )
        }
        let classification: CustomAITestFailureCategory
        if error is CoreAudioCaptureError ||
            error as? CustomAIPipelineError == .invalidAudio {
            classification = .microphone
        } else if error is URLError {
            classification = .network
        } else if error is CustomAIRuntimeConfigurationError {
            classification = .invalidRequest
        } else if let providerError = error as? CustomAIProviderError {
            classification = category(for: providerError)
        } else {
            classification = .incompatibleResponse
        }
        return .init(
            stage: stage,
            category: classification,
            providerFailure: nil
        )
    }

    private static func category(
        for error: CustomAIProviderError
    ) -> CustomAITestFailureCategory {
        switch error {
        case .invalidConfiguration, .unsupportedProvider,
             .unapprovedEndpoint:
            return .permissionOrModel
        case .invalidRequest:
            return .invalidRequest
        case .unusableAudio:
            return .audioSample
        case .invalidResponse, .responseTooLarge:
            return .incompatibleResponse
        case .httpStatus(let status):
            switch status {
            case 401: return .authentication
            case 403, 404: return .permissionOrModel
            case 429: return .rateLimit
            case 400..<500: return .invalidRequest
            default: return .network
            }
        }
    }
}
