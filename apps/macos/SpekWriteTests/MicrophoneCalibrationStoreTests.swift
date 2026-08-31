import Foundation
import XCTest
@testable import SpekWrite

final class MicrophoneCalibrationStoreTests: XCTestCase {
    func testStoreReadsOnlyMatchingDeviceAndCurrentAlgorithm() async throws {
        let suiteName = "TxChatCalibrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMicrophoneCalibrationStore(defaults: defaults)
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let profile = makeProfile(device: device)

        try await store.save(profile)

        let loadedProfile = await store.profile(for: device)
        let otherDeviceProfile = await store.profile(
            for: .init(uid: "test-input-b", displayName: "Input B")
        )
        XCTAssertEqual(loadedProfile, profile)
        XCTAssertNil(otherDeviceProfile)
        let persistedData = try XCTUnwrap(
            defaults.data(forKey: store.storageKey(for: device.uid))
        )
        let persistedText = try XCTUnwrap(
            String(data: persistedData, encoding: .utf8)
        ).lowercased()
        XCTAssertFalse(persistedText.contains("pcm"))
        XCTAssertFalse(persistedText.contains("transcript"))
        XCTAssertFalse(persistedText.contains("base64"))
    }

    func testStoreRejectsOldAlgorithmAndCorruptedJSON() async throws {
        let suiteName = "TxChatCalibrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMicrophoneCalibrationStore(defaults: defaults)
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let old = TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: -50,
            speechP20DBFS: -25,
            openThresholdDBFS: -29,
            holdThresholdDBFS: -31,
            createdAt: .distantPast,
            algorithmVersion: 0
        )

        try await store.save(old)
        let oldProfile = await store.profile(for: device)
        XCTAssertNil(oldProfile)

        defaults.set(
            Data("not-json".utf8),
            forKey: store.storageKey(for: device.uid)
        )
        let corruptedProfile = await store.profile(for: device)
        XCTAssertNil(corruptedProfile)
    }

    func testStoreRejectsProfilesWithUnapprovedCalibrationMath()
        async throws
    {
        let suiteName = "TxChatCalibrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMicrophoneCalibrationStore(defaults: defaults)
        let device = TxChatInputDeviceIdentity(
            uid: "test-input-a",
            displayName: "Input A"
        )
        let corruptedProfiles = [
            TxChatDistanceGateProfile(
                device: device,
                quietP95DBFS: -50,
                speechP20DBFS: -42,
                openThresholdDBFS: -46,
                holdThresholdDBFS: -48,
                createdAt: .distantPast,
                algorithmVersion:
                    TxChatDistanceGateProfile.currentAlgorithmVersion
            ),
            TxChatDistanceGateProfile(
                device: device,
                quietP95DBFS: -50,
                speechP20DBFS: -25,
                openThresholdDBFS: -35,
                holdThresholdDBFS: -37,
                createdAt: .distantPast,
                algorithmVersion:
                    TxChatDistanceGateProfile.currentAlgorithmVersion
            ),
            TxChatDistanceGateProfile(
                device: device,
                quietP95DBFS: -121,
                speechP20DBFS: -25,
                openThresholdDBFS: -29,
                holdThresholdDBFS: -31,
                createdAt: .distantPast,
                algorithmVersion:
                    TxChatDistanceGateProfile.currentAlgorithmVersion
            ),
        ]

        for profile in corruptedProfiles {
            try await store.save(profile)
            let loaded = await store.profile(for: device)
            XCTAssertNil(loaded)
        }
    }

    private func makeProfile(
        device: TxChatInputDeviceIdentity
    ) -> TxChatDistanceGateProfile {
        TxChatDistanceGateProfile(
            device: device,
            quietP95DBFS: -50,
            speechP20DBFS: -25,
            openThresholdDBFS: -29,
            holdThresholdDBFS: -31,
            createdAt: .distantPast,
            algorithmVersion: TxChatDistanceGateProfile.currentAlgorithmVersion
        )
    }
}
