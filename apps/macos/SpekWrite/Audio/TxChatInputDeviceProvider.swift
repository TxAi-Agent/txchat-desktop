import CoreAudio
import Foundation

enum TxChatInputDeviceError: Error, Equatable, Sendable {
    case unavailable
    case invalidIdentity
}

protocol TxChatInputDeviceProviding: Sendable {
    func currentInputDevice() throws -> TxChatInputDeviceIdentity
}

final class CoreAudioInputDeviceProvider: @unchecked Sendable,
    TxChatInputDeviceProviding
{
    typealias DeviceID = AudioObjectID

    private let readDefaultDeviceID: () throws -> DeviceID
    private let readUID: (DeviceID) throws -> String
    private let readDisplayName: (DeviceID) throws -> String

    convenience init() {
        self.init(
            readDefaultDeviceID: Self.systemDefaultInputDevice,
            readUID: { deviceID in
                try Self.stringProperty(
                    deviceID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                )
            },
            readDisplayName: { deviceID in
                try Self.stringProperty(
                    deviceID: deviceID,
                    selector: kAudioObjectPropertyName
                )
            }
        )
    }

    init(
        readDefaultDeviceID: @escaping () throws -> DeviceID,
        readUID: @escaping (DeviceID) throws -> String,
        readDisplayName: @escaping (DeviceID) throws -> String
    ) {
        self.readDefaultDeviceID = readDefaultDeviceID
        self.readUID = readUID
        self.readDisplayName = readDisplayName
    }

    func currentInputDevice() throws -> TxChatInputDeviceIdentity {
        let deviceID: DeviceID
        let rawUID: String
        let rawDisplayName: String
        do {
            deviceID = try readDefaultDeviceID()
            rawUID = try readUID(deviceID)
            rawDisplayName = try readDisplayName(deviceID)
        } catch {
            throw TxChatInputDeviceError.unavailable
        }
        let uid = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = rawDisplayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard deviceID != kAudioObjectUnknown,
              !uid.isEmpty,
              !displayName.isEmpty else {
            throw TxChatInputDeviceError.invalidIdentity
        }
        return TxChatInputDeviceIdentity(uid: uid, displayName: displayName)
    }

    private static func systemDefaultInputDevice() throws -> DeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<DeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw TxChatInputDeviceError.unavailable
        }
        return deviceID
    }

    private static func stringProperty(
        deviceID: DeviceID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr, let value else {
            throw TxChatInputDeviceError.unavailable
        }
        return value as String
    }
}
