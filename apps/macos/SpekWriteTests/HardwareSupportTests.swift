import XCTest
@testable import SpekWrite

final class HardwareSupportTests: XCTestCase {
    func testAppleSiliconSupportsLocalInference() {
        XCTAssertEqual(HardwareSupport(architecture: "arm64").localInference, .supported)
    }

    func testIntelRequiresCloudFallbackConsent() {
        XCTAssertEqual(HardwareSupport(architecture: "x86_64").localInference, .cloudFallbackOnly)
    }

    func testUnknownArchitectureFailsClosed() {
        XCTAssertEqual(HardwareSupport(architecture: "riscv64").localInference, .unsupported)
    }
}
