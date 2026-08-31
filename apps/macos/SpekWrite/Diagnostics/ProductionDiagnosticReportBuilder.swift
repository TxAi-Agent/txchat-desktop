import ApplicationServices
import AVFoundation
import Foundation

@MainActor
final class ProductionDiagnosticReportBuilder: DiagnosticReportBuilding {
    struct Snapshot: Equatable, Sendable {
        let installationID: UUID
        let appVersion: String
        let appBuild: String
        let locale: DiagnosticLocale
        let architecture: DiagnosticArchitecture
        let macOSVersion: String
        let microphone: DiagnosticPermissionState
        let accessibility: DiagnosticPermissionState
        let serviceMode: DiagnosticServiceMode
    }

    typealias SnapshotProvider = @MainActor @Sendable () throws -> Snapshot

    private let events: DiagnosticEventStore
    private let snapshot: SnapshotProvider
    private let reportID: @Sendable () -> UUID

    init(
        events: DiagnosticEventStore,
        snapshot: @escaping SnapshotProvider,
        reportID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.events = events
        self.snapshot = snapshot
        self.reportID = reportID
    }

    func build(
        incident: DiagnosticIncident,
        occurredAt: Date,
        confirmedAt: Date
    ) async throws -> DiagnosticReportEnvelope {
        let snapshot = try snapshot()
        let recent = try await events.recent(confirmedAt: confirmedAt)
        return DiagnosticReportEnvelope(
            schemaVersion: 1,
            reportId: reportID(),
            installationId: snapshot.installationID,
            consent: DiagnosticConsent(
                promptVersion: 1,
                confirmedAt: DiagnosticTimestamp(date: confirmedAt)
            ),
            occurredAt: DiagnosticTimestamp(date: occurredAt),
            app: DiagnosticApp(
                version: snapshot.appVersion,
                build: snapshot.appBuild,
                locale: snapshot.locale,
                architecture: snapshot.architecture
            ),
            system: DiagnosticSystem(
                macOSVersion: snapshot.macOSVersion,
                microphone: snapshot.microphone,
                accessibility: snapshot.accessibility
            ),
            service: DiagnosticService(mode: snapshot.serviceMode),
            incident: incident,
            events: recent
        )
    }
}

@MainActor
final class ProductionDiagnosticSnapshotProvider {
    enum Error: Swift.Error {
        case unavailable
    }

    private let installationID: () -> UUID
    private let bundleInfo: () -> [String: Any]
    private let operatingSystemVersion: () -> OperatingSystemVersion
    private let architecture: () -> String
    private let microphone: () -> DiagnosticPermissionState
    private let accessibility: () -> DiagnosticPermissionState
    private let language: () -> TxChatLanguage

    init(
        installationID: @escaping () -> UUID,
        bundleInfo: @escaping () -> [String: Any],
        operatingSystemVersion: @escaping () -> OperatingSystemVersion,
        architecture: @escaping () -> String,
        microphone: @escaping () -> DiagnosticPermissionState,
        accessibility: @escaping () -> DiagnosticPermissionState,
        language: @escaping () -> TxChatLanguage
    ) {
        self.installationID = installationID
        self.bundleInfo = bundleInfo
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
        self.microphone = microphone
        self.accessibility = accessibility
        self.language = language
    }

    static func production(
        language: @escaping () -> TxChatLanguage
    ) -> ProductionDiagnosticSnapshotProvider {
        let sessionID = UUID()
        return ProductionDiagnosticSnapshotProvider(
            installationID: { sessionID },
            bundleInfo: { Bundle.main.infoDictionary ?? [:] },
            operatingSystemVersion: {
                ProcessInfo.processInfo.operatingSystemVersion
            },
            architecture: { HardwareSupport.current.architecture },
            microphone: { microphonePermission() },
            accessibility: {
                AXIsProcessTrusted() ? .authorized : .denied
            },
            language: language
        )
    }

    func snapshot() throws -> ProductionDiagnosticReportBuilder.Snapshot {
        let info = bundleInfo()
        guard
            let appVersion = info["CFBundleShortVersionString"] as? String,
            !appVersion.isEmpty,
            let appBuild = info["CFBundleVersion"] as? String,
            !appBuild.isEmpty
        else {
            throw Error.unavailable
        }
        let system = operatingSystemVersion()
        let architecture: DiagnosticArchitecture = switch architecture() {
        case "arm64": .arm64
        case "x86_64": .x86_64
        default: .unknown
        }
        return ProductionDiagnosticReportBuilder.Snapshot(
            installationID: installationID(),
            appVersion: appVersion,
            appBuild: appBuild,
            locale: language() == .simplifiedChinese ? .zhHans : .en,
            architecture: architecture,
            macOSVersion:
                "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            microphone: microphone(),
            accessibility: accessibility(),
            serviceMode: .custom
        )
    }

    private static func microphonePermission() -> DiagnosticPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }
}
