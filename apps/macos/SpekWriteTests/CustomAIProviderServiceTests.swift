import Foundation
import XCTest
@testable import SpekWrite

private actor RecordingHTTPTransport: CustomAIHTTPTransporting {
    private(set) var callCount = 0

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> CustomAIHTTPResponse {
        _ = request
        _ = maximumResponseBytes
        callCount += 1
        throw CustomAIProviderError.invalidRequest
    }
}

private actor RecordingStreamingTransport:
    CustomAIVolcengineStreamingASRTransporting
{
    private(set) var callCount = 0

    func transcribe(
        wavAudio: Data,
        selection: CustomAIRuntimeSelection
    ) async throws -> String {
        _ = wavAudio
        _ = selection
        callCount += 1
        throw CustomAIProviderError.invalidRequest
    }
}

final class CustomAIProviderServiceTests: XCTestCase {
    private let httpASRSelection = CustomAIRuntimeSelection(
        providerID: CustomAIASRProviderID.alibabaBailian.rawValue,
        modelID: "fun-asr-flash-synthetic",
        values: [
            .apiKey: "synthetic-key",
            .endpointURL: "https://example.invalid/asr",
        ]
    )

    private let streamingASRSelection = CustomAIRuntimeSelection(
        providerID: CustomAIASRProviderID.volcengine.rawValue,
        modelID: "volc.seedasr.sauc.duration",
        values: [
            .apiKey: "synthetic-key",
            .endpointURL: "wss://example.invalid/asr",
        ]
    )

    private let optimizationSelection = CustomAIRuntimeSelection(
        providerID: CustomAIOptimizationProviderID.alibabaBailian.rawValue,
        modelID: "synthetic-model",
        values: [
            .apiKey: "synthetic-key",
            .endpointURL: "https://example.invalid/optimization",
        ]
    )

    func testDefaultWiringUsesDisabledProviderTransports() {
        let service = CustomAIProviderService()
        let children = Array(Mirror(reflecting: service).children)
        let http = children.first(where: { $0.label == "http" })?.value
        let streaming = children.first(where: {
            $0.label == "volcengine"
        })?.value

        XCTAssertTrue(http is CustomAIDisabledHTTPTransport)
        XCTAssertTrue(
            streaming is CustomAIDisabledVolcengineStreamingASRTransport
        )
    }

    func testHTTPASRRejectsBeforeInvokingInjectedTransports() async {
        let http = RecordingHTTPTransport()
        let streaming = RecordingStreamingTransport()
        let service = CustomAIProviderService(
            http: http,
            volcengine: streaming
        )
        do {
            _ = try await service.transcribe(
                wavAudio: Data([0, 1]),
                selection: httpASRSelection
            )
            XCTFail("Expected public provider service to fail closed")
        } catch {
            XCTAssertEqual(error as? CustomAIProviderError, .unsupportedProvider)
        }
        let httpCallCount = await http.callCount
        let streamingCallCount = await streaming.callCount
        XCTAssertEqual(httpCallCount, 0)
        XCTAssertEqual(streamingCallCount, 0)
    }

    func testStreamingASRRejectsBeforeInvokingInjectedTransports() async {
        let http = RecordingHTTPTransport()
        let streaming = RecordingStreamingTransport()
        let service = CustomAIProviderService(
            http: http,
            volcengine: streaming
        )
        do {
            _ = try await service.transcribe(
                wavAudio: Data([0, 1]),
                selection: streamingASRSelection
            )
            XCTFail("Expected public provider service to fail closed")
        } catch {
            XCTAssertEqual(error as? CustomAIProviderError, .unsupportedProvider)
        }
        let httpCallCount = await http.callCount
        let streamingCallCount = await streaming.callCount
        XCTAssertEqual(httpCallCount, 0)
        XCTAssertEqual(streamingCallCount, 0)
    }

    func testOptimizationRejectsBeforeInvokingInjectedTransports() async {
        let http = RecordingHTTPTransport()
        let streaming = RecordingStreamingTransport()
        let service = CustomAIProviderService(
            http: http,
            volcengine: streaming
        )
        let prompt = TextOptimizationPrompt(
            version: "public-test",
            sha256: String(repeating: "0", count: 64),
            utf8Bytes: 24,
            content: "Use only synthetic text."
        )
        do {
            _ = try await service.optimize(
                rawText: "synthetic text",
                prompt: prompt,
                selection: optimizationSelection
            )
            XCTFail("Expected public provider service to fail closed")
        } catch {
            XCTAssertEqual(error as? CustomAIProviderError, .unsupportedProvider)
        }
        let httpCallCount = await http.callCount
        let streamingCallCount = await streaming.callCount
        XCTAssertEqual(httpCallCount, 0)
        XCTAssertEqual(streamingCallCount, 0)
    }
}
