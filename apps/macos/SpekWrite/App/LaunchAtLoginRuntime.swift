import Foundation
import ServiceManagement

enum LaunchAtLoginServiceStatus: Equatable, Sendable {
    case notRegistered
    case notFound
    case enabled
    case requiresApproval
    case unavailable
}

protocol LaunchAtLoginServicing: Sendable {
    func status() async -> LaunchAtLoginServiceStatus
    func register() async throws
}

protocol LaunchAtLoginRecordStoring: Sendable {
    func containsRegistrationDecision() async -> Bool
    func recordRegistrationDecision() async throws
}

protocol LaunchAtLoginActivating: Sendable {
    func activateWhenReady() async
}

enum SystemLaunchAtLoginStatus {
    static var current: LaunchAtLoginServiceStatus {
        resolve(SMAppService.mainApp.status)
    }

    static func resolve(
        _ status: SMAppService.Status
    ) -> LaunchAtLoginServiceStatus {
        switch status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .unavailable
        }
    }
}

private final class SystemMainAppLaunchAtLoginService:
    LaunchAtLoginServicing,
    @unchecked Sendable
{
    func status() async -> LaunchAtLoginServiceStatus {
        SystemLaunchAtLoginStatus.current
    }

    func register() async throws {
        try SMAppService.mainApp.register()
    }
}

actor UserDefaultsLaunchAtLoginRecordStore: LaunchAtLoginRecordStoring {
    enum Error: Swift.Error, Equatable {
        case writeFailed
    }

    private struct Record: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let registrationWasHandled: Bool
    }

    static let defaultKey = "txchat.launch-at-login.registration.v1"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = UserDefaultsLaunchAtLoginRecordStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    static func containsRegistrationDecisionValue(
        _ storedValue: Any?
    ) -> Bool {
        storedValue != nil
    }

    func containsRegistrationDecision() async -> Bool {
        Self.containsRegistrationDecisionValue(
            userDefaults.object(forKey: key)
        )
    }

    func recordRegistrationDecision() async throws {
        let record = Record(schemaVersion: 1, registrationWasHandled: true)
        let data = try JSONEncoder().encode(record)
        userDefaults.set(data, forKey: key)
        guard userDefaults.data(forKey: key) == data else {
            throw Error.writeFailed
        }
    }
}

actor LaunchAtLoginRuntime: LaunchAtLoginActivating {
    private let service: any LaunchAtLoginServicing
    private let recordStore: any LaunchAtLoginRecordStoring
    private var handledInProcess = false

    init(
        service: any LaunchAtLoginServicing,
        recordStore: any LaunchAtLoginRecordStoring
    ) {
        self.service = service
        self.recordStore = recordStore
    }

    static func production() -> LaunchAtLoginRuntime {
        LaunchAtLoginRuntime(
            service: SystemMainAppLaunchAtLoginService(),
            recordStore: UserDefaultsLaunchAtLoginRecordStore()
        )
    }

    func activateWhenReady() async {
        guard !handledInProcess else { return }
        handledInProcess = true
        guard !(await recordStore.containsRegistrationDecision()) else {
            return
        }

        switch await service.status() {
        case .notRegistered, .notFound:
            do {
                try await service.register()
                try? await recordStore.recordRegistrationDecision()
            } catch {
                return
            }
        case .enabled, .requiresApproval:
            try? await recordStore.recordRegistrationDecision()
        case .unavailable:
            return
        }
    }
}
