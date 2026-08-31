import Foundation
import XCTest
@testable import SpekWrite

final class CustomAIEndpointCatalogTests: XCTestCase {
    func testMissingEndpointFailsClosed() {
        let selection = CustomAIRuntimeSelection(
            providerID: CustomAIASRProviderID.alibabaBailian.rawValue,
            modelID: "example-model",
            values: [:]
        )

        XCTAssertThrowsError(
            try CustomAIEndpointCatalog.httpsEndpoint(for: selection)
        )
    }

    func testHTTPSAndWSSEndpointsAreInjectedWithoutNetworkAccess() throws {
        let httpsSelection = CustomAIRuntimeSelection(
            providerID: CustomAIASRProviderID.alibabaBailian.rawValue,
            modelID: "example-model",
            values: [.endpointURL: "https://example.invalid/v1/request"]
        )
        let wssSelection = CustomAIRuntimeSelection(
            providerID: CustomAIASRProviderID.volcengine.rawValue,
            modelID: "example-model",
            values: [.endpointURL: "wss://example.invalid/v1/stream"]
        )

        XCTAssertEqual(
            try CustomAIEndpointCatalog.httpsEndpoint(for: httpsSelection)
                .absoluteString,
            "https://example.invalid/v1/request"
        )
        XCTAssertEqual(
            try CustomAIEndpointCatalog.wssEndpoint(for: wssSelection)
                .absoluteString,
            "wss://example.invalid/v1/stream"
        )
    }

    func testEndpointRejectsCredentialsAndWrongScheme() {
        for rawValue in [
            "http://example.invalid/v1/request",
            "https://example.invalid/v1/request#fragment",
        ] {
            let selection = CustomAIRuntimeSelection(
                providerID: CustomAIASRProviderID.alibabaBailian.rawValue,
                modelID: "example-model",
                values: [.endpointURL: rawValue]
            )
            XCTAssertThrowsError(
                try CustomAIEndpointCatalog.httpsEndpoint(for: selection)
            )
        }
    }
}
