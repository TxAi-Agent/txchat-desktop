import Foundation
import XCTest
@testable import SpekWrite

final class ProductConfigurationTests: XCTestCase {
    func testAcceptsOnlyHTTPSAndWSSProductionOrigins() throws {
        let value = try ProductConfiguration(
            apiBaseURL: try XCTUnwrap(URL(string: "https://example.invalid")),
            realtimeBaseURL: try XCTUnwrap(URL(string: "wss://example.invalid"))
        )

        XCTAssertEqual(value.apiBaseURL.scheme, "https")
        XCTAssertEqual(value.realtimeBaseURL.scheme, "wss")
        XCTAssertThrowsError(
            try ProductConfiguration(
                apiBaseURL: try XCTUnwrap(URL(string: "http://example.invalid")),
                realtimeBaseURL: try XCTUnwrap(URL(string: "wss://example.invalid"))
            )
        )
    }

    func testBuildsPublicLocalLoopbackOriginsFromOnlyAValidatedPort() throws {
#if DEBUG
        let configuration = try XCTUnwrap(
            PublicLocalDevelopmentConfiguration.load(environment: [
                "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1",
                "TXCHAT_PUBLIC_LOCAL_PORT": "41873",
            ])
        )

        XCTAssertEqual(
            configuration.apiBaseURL.absoluteString,
            "http://127.0.0.1:41873"
        )
        XCTAssertEqual(
            configuration.realtimeBaseURL.absoluteString,
            "ws://127.0.0.1:41873"
        )
#else
        XCTAssertNil(
            PublicLocalDevelopmentConfiguration.load(environment: [
                "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1",
                "TXCHAT_PUBLIC_LOCAL_PORT": "41873",
            ])
        )
#endif
    }

    func testRejectsDisabledMalformedPrivilegedAndOverflowPorts() {
        for environment in [
            [:],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "0", "TXCHAT_PUBLIC_LOCAL_PORT": "41873"],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1"],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1", "TXCHAT_PUBLIC_LOCAL_PORT": ""],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1", "TXCHAT_PUBLIC_LOCAL_PORT": " 41873"],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1", "TXCHAT_PUBLIC_LOCAL_PORT": "+41873"],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1", "TXCHAT_PUBLIC_LOCAL_PORT": "1023"],
            ["TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1", "TXCHAT_PUBLIC_LOCAL_PORT": "65536"],
        ] {
            XCTAssertNil(
                PublicLocalDevelopmentConfiguration.load(environment: environment)
            )
        }
    }

    func testRejectsAnyAdditionalPublicLocalEnvironmentField() {
        let disallowedSuffixes = [
            "URL",
            "HOST",
            "CREDENTIAL",
            "TOKEN",
            "SECRET",
            "PASSWORD",
            "ENDPOINT",
        ]
        for suffix in disallowedSuffixes {
            var environment = [
                "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1",
                "TXCHAT_PUBLIC_LOCAL_PORT": "41873",
            ]
            environment["TXCHAT_PUBLIC_LOCAL_\(suffix)"] = "synthetic"
            XCTAssertNil(
                PublicLocalDevelopmentConfiguration.load(environment: environment)
            )
        }
    }
}
