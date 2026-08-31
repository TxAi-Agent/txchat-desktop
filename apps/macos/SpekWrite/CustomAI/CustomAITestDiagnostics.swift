import Foundation
import OSLog

enum CustomAITestLocalFailureReason: Equatable, Sendable {
    case invalidConfiguration
    case missingRequiredField(CustomAIFieldID)

    init?(_ error: Error) {
        guard let error = error as? CustomAIRuntimeConfigurationError else {
            return nil
        }
        switch error {
        case .invalidConfiguration:
            self = .invalidConfiguration
        case .missingRequiredField(_, _, let fieldID):
            self = .missingRequiredField(fieldID)
        }
    }

    fileprivate var diagnosticValue: String {
        switch self {
        case .invalidConfiguration:
            return "invalid-configuration"
        case .missingRequiredField(let fieldID):
            return "missing-\(fieldID.rawValue)"
        }
    }
}

struct CustomAITestDiagnosticEvent: Equatable, Sendable {
    let scope: CustomAITestScope
    let stage: CustomAIProviderStage
    let category: CustomAITestFailureCategory
    let providerID: String?
    let modelID: String?
    let httpStatus: Int?
    let providerCode: String?
    let requestID: String?
    let localReason: CustomAITestLocalFailureReason?

    init(
        scope: CustomAITestScope,
        stage: CustomAIProviderStage,
        category: CustomAITestFailureCategory,
        providerID: String?,
        modelID: String?,
        httpStatus: Int?,
        providerCode: String?,
        requestID: String?,
        localReason: CustomAITestLocalFailureReason?
    ) {
        self.scope = scope
        self.stage = stage
        self.category = category
        self.providerID = providerID.flatMap(
            CustomAIProviderFailure.sanitizedIdentifier
        )
        self.modelID = modelID.flatMap(
            CustomAIProviderFailure.sanitizedIdentifier
        )
        self.httpStatus = httpStatus.flatMap {
            (100...599).contains($0) ? $0 : nil
        }
        self.providerCode = providerCode.flatMap(
            CustomAIProviderFailure.sanitizedProviderCode
        )
        self.requestID = requestID.flatMap(
            CustomAIProviderFailure.sanitizedIdentifier
        )
        self.localReason = localReason
    }
}

protocol CustomAITestDiagnosticRecording: Sendable {
    func record(_ event: CustomAITestDiagnosticEvent) async
}

struct NullCustomAITestDiagnosticRecorder: CustomAITestDiagnosticRecording {
    func record(_ event: CustomAITestDiagnosticEvent) async {
        _ = event
    }
}

struct SystemCustomAITestDiagnosticRecorder:
    CustomAITestDiagnosticRecording
{
    private let logger = Logger(
        subsystem: "org.example.txchat",
        category: "custom-ai-test"
    )

    func record(_ event: CustomAITestDiagnosticEvent) async {
        let providerID = event.providerID ?? "-"
        let modelID = event.modelID ?? "-"
        let httpStatus = event.httpStatus.map(String.init) ?? "-"
        let providerCode = event.providerCode ?? "-"
        let requestID = event.requestID ?? "-"
        let localReason = event.localReason?.diagnosticValue ?? "-"
        logger.error(
            "scope=\(event.scope.rawValue, privacy: .public) stage=\(event.stage.rawValue, privacy: .public) category=\(event.category.diagnosticValue, privacy: .public) provider_id=\(providerID, privacy: .public) model_id=\(modelID, privacy: .public) http_status=\(httpStatus, privacy: .public) provider_code=\(providerCode, privacy: .public) request_id=\(requestID, privacy: .public) local_reason=\(localReason, privacy: .public)"
        )
    }
}

private extension CustomAITestFailureCategory {
    var diagnosticValue: String {
        switch self {
        case .microphone: "microphone"
        case .audioSample: "audio-sample"
        case .network: "network"
        case .authentication: "authentication"
        case .permissionOrModel: "permission-or-model"
        case .rateLimit: "rate-limit"
        case .invalidRequest: "invalid-request"
        case .incompatibleResponse: "incompatible-response"
        }
    }
}
