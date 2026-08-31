import Foundation

struct CustomAIHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

protocol CustomAIHTTPTransporting: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> CustomAIHTTPResponse
}

enum CustomAIProviderError: Error, Equatable, Sendable {
    case invalidConfiguration
    case unsupportedProvider
    case invalidRequest
    case unusableAudio
    case invalidResponse
    case responseTooLarge
    case unapprovedEndpoint
    case httpStatus(Int)
}

struct CustomAIDisabledHTTPTransport: CustomAIHTTPTransporting {
    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> CustomAIHTTPResponse {
        _ = request
        _ = maximumResponseBytes
        throw CustomAIProviderError.unsupportedProvider
    }
}

protocol CustomAIVolcengineStreamingASRTransporting: Sendable {
    func transcribe(
        wavAudio: Data,
        selection: CustomAIRuntimeSelection
    ) async throws -> String
}

struct CustomAIDisabledVolcengineStreamingASRTransport:
    CustomAIVolcengineStreamingASRTransporting
{
    func transcribe(
        wavAudio: Data,
        selection: CustomAIRuntimeSelection
    ) async throws -> String {
        _ = wavAudio
        _ = selection
        throw CustomAIProviderError.unsupportedProvider
    }
}

struct CustomAIProviderService: CustomAIASRServing,
    CustomAIOptimizationServing
{
    private let http: any CustomAIHTTPTransporting
    private let volcengine: any CustomAIVolcengineStreamingASRTransporting

    init(
        http: any CustomAIHTTPTransporting = CustomAIDisabledHTTPTransport(),
        volcengine: any CustomAIVolcengineStreamingASRTransporting =
            CustomAIDisabledVolcengineStreamingASRTransport()
    ) {
        self.http = http
        self.volcengine = volcengine
    }

    func transcribe(
        wavAudio: Data,
        selection: CustomAIRuntimeSelection
    ) async throws -> String {
        _ = wavAudio
        _ = selection
        throw CustomAIProviderError.unsupportedProvider
    }

    func optimize(
        rawText: String,
        prompt: TextOptimizationPrompt,
        selection: CustomAIRuntimeSelection
    ) async throws -> String {
        _ = rawText
        _ = prompt
        _ = selection
        throw CustomAIProviderError.unsupportedProvider
    }
}
