import XCTest
@testable import SpekWrite

final class TxChatInputDeviceProviderTests: XCTestCase {
    func testInjectedReaderBuildsStableIdentityWithoutStartingAudio() throws {
        var readDefaultCount = 0
        let provider = CoreAudioInputDeviceProvider(
            readDefaultDeviceID: {
                readDefaultCount += 1
                return 42
            },
            readUID: { deviceID in
                XCTAssertEqual(deviceID, 42)
                return "stable-test-uid"
            },
            readDisplayName: { deviceID in
                XCTAssertEqual(deviceID, 42)
                return "Test Input"
            }
        )

        XCTAssertEqual(
            try provider.currentInputDevice(),
            .init(uid: "stable-test-uid", displayName: "Test Input")
        )
        XCTAssertEqual(readDefaultCount, 1)
    }

    func testProviderFailsClosedForEmptyIdentityFields() {
        for values in [("", "Input"), ("uid", "  ")] {
            let provider = CoreAudioInputDeviceProvider(
                readDefaultDeviceID: { 42 },
                readUID: { _ in values.0 },
                readDisplayName: { _ in values.1 }
            )

            XCTAssertThrowsError(try provider.currentInputDevice()) { error in
                XCTAssertEqual(error as? TxChatInputDeviceError, .invalidIdentity)
            }
        }
    }
}
