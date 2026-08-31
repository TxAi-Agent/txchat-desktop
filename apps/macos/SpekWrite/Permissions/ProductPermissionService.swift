import AppKit
import AVFoundation
import ApplicationServices

enum ProductPermissionKind: Equatable, Sendable {
    case microphone
    case accessibility
}

protocol VoiceTestCompletionStoring: AnyObject {
    var isCompleted: Bool { get }
    @discardableResult
    func markCompleted() -> Bool
}

final class UserDefaultsVoiceTestCompletionStore:
    VoiceTestCompletionStoring
{
    static let defaultKey =
        "org.example.txchat.product.voice-test-completed"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = UserDefaultsVoiceTestCompletionStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    var isCompleted: Bool {
        userDefaults.bool(forKey: key)
    }

    @discardableResult
    func markCompleted() -> Bool {
        let previousValue = userDefaults.object(forKey: key)
        userDefaults.set(true, forKey: key)
        guard userDefaults.bool(forKey: key) else {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            return false
        }
        return true
    }
}

@MainActor
protocol ProductPermissionServing: AnyObject {
    func snapshot() async -> ProductPermissionSnapshot
    func requestMicrophone() async -> ProductPermissionSnapshot
    func requestAccessibility() async -> ProductPermissionSnapshot
    func completeVoiceTest() async -> ProductPermissionSnapshot
    func openSystemSettings(for permission: ProductPermissionKind) async
}

@MainActor
final class ProductPermissionService: ProductPermissionServing {
    private let voiceTestCompletionStore:
        any VoiceTestCompletionStoring
    private let microphoneAuthorizationReader: () -> Bool
    private let accessibilityAuthorizationReader: () -> Bool

    init(
        voiceTestCompletionStore: any VoiceTestCompletionStoring =
            UserDefaultsVoiceTestCompletionStore(),
        microphoneAuthorizationReader: @escaping () -> Bool = {
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        },
        accessibilityAuthorizationReader: @escaping () -> Bool = {
            AXIsProcessTrusted()
        }
    ) {
        self.voiceTestCompletionStore = voiceTestCompletionStore
        self.microphoneAuthorizationReader =
            microphoneAuthorizationReader
        self.accessibilityAuthorizationReader =
            accessibilityAuthorizationReader
    }

    func snapshot() async -> ProductPermissionSnapshot {
        readSnapshot()
    }

    func requestMicrophone() async -> ProductPermissionSnapshot {
        if AVCaptureDevice.authorizationStatus(for: .audio)
            == .notDetermined
        {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return readSnapshot()
    }

    func requestAccessibility() async -> ProductPermissionSnapshot {
        let options = ["AXTrustedCheckOptionPrompt": true]
            as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return readSnapshot()
    }

    func completeVoiceTest() async -> ProductPermissionSnapshot {
        _ = voiceTestCompletionStore.markCompleted()
        return readSnapshot()
    }

    func openSystemSettings(for permission: ProductPermissionKind) async {
        let anchor: String
        switch permission {
        case .microphone:
            anchor = "Privacy_Microphone"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:" +
                "com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func readSnapshot() -> ProductPermissionSnapshot {
        let microphoneReady = microphoneAuthorizationReader()
        let accessibilityReady = accessibilityAuthorizationReader()
        return ProductPermissionSnapshot(
            microphone: microphoneReady ? .ready : .needsSetup,
            accessibility: accessibilityReady ? .ready : .needsSetup,
            hotkey: accessibilityReady ? .ready : .needsSetup,
            voiceTest: voiceTestCompletionStore.isCompleted
                ? .ready
                : .needsSetup
        )
    }
}
