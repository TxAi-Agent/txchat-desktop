import XCTest
@testable import SpekWrite

@MainActor
final class PublicLocalRuntimeTests: XCTestCase {
    func testValidDebugConfigurationSelectsInMemoryPublicLocalRuntime() {
        let runtime = ProductRuntime.bootstrap(
            info: [:],
            environment: [
                "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1",
                "TXCHAT_PUBLIC_LOCAL_PORT": "41873",
            ]
        )
#if DEBUG
        XCTAssertTrue(runtime.dependenciesAreInMemory)
#else
        XCTAssertFalse(runtime.dependenciesAreInMemory)
#endif
    }

    func testMissingOrInvalidLocalConfigurationRemainsUnavailable() {
        let missing = ProductRuntime.bootstrap(info: [:], environment: [:])
        XCTAssertFalse(missing.dependenciesAreInMemory)

        let invalid = ProductRuntime.bootstrap(
            info: [:],
            environment: [
                "TXCHAT_PUBLIC_LOCAL_DEVELOPMENT": "1",
                "TXCHAT_PUBLIC_LOCAL_PORT": "1023",
            ]
        )
        XCTAssertFalse(invalid.dependenciesAreInMemory)
    }
}
