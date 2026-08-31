import Foundation
import XCTest
@testable import SpekWrite

func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

enum DiagnosticTestFixture {
    static let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)

    static func report(
        reportID: UUID = UUID(
            uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        )!
    ) -> DiagnosticReportEnvelope {
        let timestamp = DiagnosticTimestamp(date: occurredAt)
        return DiagnosticReportEnvelope(
            schemaVersion: 1,
            reportId: reportID,
            installationId: UUID(
                uuidString: "11111111-2222-4333-8444-555555555555"
            )!,
            consent: .init(promptVersion: 1, confirmedAt: timestamp),
            occurredAt: timestamp,
            app: .init(
                version: "0.0.0",
                build: "0",
                locale: .en,
                architecture: .unknown
            ),
            system: .init(
                macOSVersion: "0.0",
                microphone: .notDetermined,
                accessibility: .notDetermined
            ),
            service: .init(mode: .custom),
            incident: .init(
                category: .application,
                taskId: nil,
                stage: .lifecycle,
                code: .abnormalExit
            ),
            events: []
        )
    }
}
