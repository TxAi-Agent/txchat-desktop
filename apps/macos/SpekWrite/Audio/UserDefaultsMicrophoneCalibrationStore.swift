import Foundation

protocol MicrophoneCalibrationStoring: Sendable {
    func profile(
        for device: TxChatInputDeviceIdentity
    ) async -> TxChatDistanceGateProfile?
    func save(_ profile: TxChatDistanceGateProfile) async throws
    func removeProfile(for deviceUID: String) async
}

final class UserDefaultsMicrophoneCalibrationStore: @unchecked Sendable,
    MicrophoneCalibrationStoring
{
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func storageKey(for deviceUID: String) -> String {
        let encodedUID = deviceUID.utf8.map {
            String(format: "%02x", $0)
        }.joined()
        return "txchat.microphone-calibration.v\(TxChatDistanceGateProfile.currentAlgorithmVersion).\(encodedUID)"
    }

    func profile(
        for device: TxChatInputDeviceIdentity
    ) async -> TxChatDistanceGateProfile? {
        lock.withLock {
            guard let data = defaults.data(
                forKey: storageKey(for: device.uid)
            ),
            let profile = try? JSONDecoder().decode(
                TxChatDistanceGateProfile.self,
                from: data
            ),
            profile.isValid(for: device) else {
                return nil
            }
            return profile
        }
    }

    func save(_ profile: TxChatDistanceGateProfile) async throws {
        let data = try JSONEncoder().encode(profile)
        lock.withLock {
            defaults.set(
                data,
                forKey: storageKey(for: profile.device.uid)
            )
        }
    }

    func removeProfile(for deviceUID: String) async {
        lock.withLock {
            defaults.removeObject(forKey: storageKey(for: deviceUID))
        }
    }
}
