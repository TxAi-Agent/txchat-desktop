import Foundation
import XCTest
@testable import SpekWrite

final class DiagnosticModelsTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_776_758_400.123)

    func testReportJSONUsesExactCloudFieldWhitelist() throws {
        let report = makeReport()
        let data = try DiagnosticJSONCodec.encode(report)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            [
                "schemaVersion", "reportId", "installationId", "consent",
                "occurredAt", "app", "system", "service", "incident",
                "events",
            ]
        )
        XCTAssertLessThanOrEqual(data.count, 65_536)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Bearer"))
    }

    func testReportJSONContainsNoSensitiveOrFreeformFields() throws {
        let data = try DiagnosticJSONCodec.encode(makeReport())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let forbidden = [
            "message", "details", "provider", "url", "path", "log",
            "audio", "transcript", "finalText", "phone", "token", "account",
            "session", "credential", "authorization", "apiKey",
        ]

        func inspect(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary {
                    XCTAssertFalse(forbidden.contains(key), key)
                    inspect(nested)
                }
            } else if let array = value as? [Any] {
                array.forEach(inspect)
            }
        }
        inspect(object)
    }

    func testStrictDecoderRejectsAdditionalProperties() throws {
        let original = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: DiagnosticJSONCodec.encode(makeReport())
            ) as? [String: Any]
        )
        let targets = ["root", "consent", "app", "system", "service", "incident", "event"]
        for target in targets {
            var object = original
            switch target {
            case "root":
                object["message"] = "must never be accepted"
            case "event":
                var events = try XCTUnwrap(object["events"] as? [[String: Any]])
                events[0]["transcript"] = "must never be accepted"
                object["events"] = events
            default:
                var nested = try XCTUnwrap(object[target] as? [String: Any])
                nested["details"] = "must never be accepted"
                object[target] = nested
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(
                try DiagnosticJSONCodec.decode(
                    DiagnosticReportEnvelope.self,
                    from: data
                ),
                target
            )
        }
    }

    func testTimestampIsCanonicalMillisecondsUTC() {
        XCTAssertEqual(
            DiagnosticTimestamp(date: fixedDate).rawValue,
            "2026-04-21T08:00:00.123Z"
        )
        XCTAssertNil(DiagnosticTimestamp(rawValue: "2026-04-21T08:00:00Z"))
        XCTAssertNil(DiagnosticTimestamp(rawValue: "2026-02-30T08:00:00.123Z"))
        XCTAssertNil(DiagnosticTimestamp(rawValue: "2026-04-21T08:00:00.123+00:00"))
    }

    func testEnvelopeValidatorRejectsEverySemanticConstraint() throws {
        let now = fixedDate
        let confirmed = DiagnosticTimestamp(date: now)
        let before = DiagnosticTimestamp(date: now.addingTimeInterval(-1))
        let after = DiagnosticTimestamp(date: now.addingTimeInterval(1))
        let ordinaryEvent = DiagnosticEvent(
            occurredAt: before,
            category: .dictation,
            taskId: nil,
            stage: .audioPump,
            code: .audioConversionFailed,
            durationMs: 42,
            httpStatus: nil
        )
        let cases: [(String, DiagnosticReportEnvelope, DiagnosticEnvelopeValidationError)] = [
            ("schema", makeReport(schemaVersion: 2), .schemaVersion),
            ("prompt", makeReport(promptVersion: 2), .promptVersion),
            ("app segments", makeReport(appVersion: "1"), .appVersion),
            ("app numeric", makeReport(appVersion: "1.two"), .appVersion),
            (
                "app length",
                makeReport(appVersion: String(repeating: "1", count: 63) + ".1"),
                .appVersion
            ),
            ("mac segments", makeReport(macOSVersion: "15"), .macOSVersion),
            ("mac numeric", makeReport(macOSVersion: "15.x"), .macOSVersion),
            ("build digits", makeReport(build: "31a"), .build),
            ("build length", makeReport(build: String(repeating: "1", count: 19)), .build),
            (
                "event count",
                makeReport(events: Array(repeating: ordinaryEvent, count: 21)),
                .eventCount
            ),
            (
                "negative duration",
                makeReport(events: [event(duration: -1)]),
                .duration
            ),
            (
                "large duration",
                makeReport(events: [event(duration: 3_600_001)]),
                .duration
            ),
            ("low status", makeReport(events: [event(httpStatus: 99)]), .httpStatus),
            ("high status", makeReport(events: [event(httpStatus: 600)]), .httpStatus),
            (
                "incident after confirmation",
                makeReport(occurredAt: after, confirmedAt: confirmed),
                .timeOrdering
            ),
            (
                "confirmation too far future",
                makeReport(
                    occurredAt: confirmed,
                    confirmedAt: DiagnosticTimestamp(
                        date: now.addingTimeInterval(301)
                    )
                ),
                .timeOrdering
            ),
            (
                "incident expired",
                makeReport(
                    occurredAt: DiagnosticTimestamp(
                        date: now.addingTimeInterval(-7 * 86_400 - 1)
                    ),
                    confirmedAt: confirmed
                ),
                .incidentExpired
            ),
            (
                "event after confirmation",
                makeReport(
                    occurredAt: before,
                    confirmedAt: confirmed,
                    events: [
                        DiagnosticEvent(
                            occurredAt: after,
                            category: .dictation,
                            taskId: nil,
                            stage: .audioPump,
                            code: .audioConversionFailed,
                            durationMs: nil,
                            httpStatus: nil
                        ),
                    ]
                ),
                .timeOrdering
            ),
            (
                "encoded size",
                makeReport(appVersion: String(repeating: "1", count: 66_000)),
                .encodedTooLarge
            ),
        ]

        try DiagnosticEnvelopeValidator.validate(makeReport(), now: now)
        for (name, report, expected) in cases {
            XCTAssertThrowsError(
                try DiagnosticEnvelopeValidator.validate(report, now: now),
                name
            ) { error in
                XCTAssertEqual(error as? DiagnosticEnvelopeValidationError, expected, name)
            }
        }
    }

    func testEnvelopeValidatorAcceptsInclusiveBoundaries() throws {
        let now = fixedDate
        let occurredAt = DiagnosticTimestamp(
            date: now.addingTimeInterval(-7 * 86_400)
        )
        let confirmedAt = DiagnosticTimestamp(
            date: now.addingTimeInterval(5 * 60)
        )
        let events = (0..<20).map { index in
            DiagnosticEvent(
                occurredAt: confirmedAt,
                category: .dictation,
                taskId: nil,
                stage: .audioPump,
                code: .audioConversionFailed,
                durationMs: index.isMultiple(of: 2) ? 0 : 3_600_000,
                httpStatus: index.isMultiple(of: 2) ? 100 : 599
            )
        }
        let report = makeReport(
            appVersion: String(repeating: "1", count: 62) + ".1",
            build: String(repeating: "9", count: 18),
            macOSVersion: "1.2.3.4",
            occurredAt: occurredAt,
            confirmedAt: confirmedAt,
            events: events
        )

        XCTAssertNoThrow(
            try DiagnosticEnvelopeValidator.validate(report, now: now)
        )
    }

    func testClassifierExplicitlyExcludesExpectedBusinessFailures() {
        let excluded: [DiagnosticFailureSignal] = [
            .networkUnavailable, .requestTimeout, .serviceUnavailable,
            .rateLimited, .invalidOTP, .authenticationFailed,
            .permissionDenied, .nearSpeechNotDetected, .targetMissing,
            .windowChanged, .userCancelled, .maximumDurationReached,
            .asrFailed, .optimizationFailedWithRawFallback,
        ]

        for signal in excluded {
            XCTAssertNil(DiagnosticClassifier.incident(for: signal), "\(signal)")
        }
    }

    func testClassifierMapsEveryReportableFailureToStrictTaxonomy() {
        let expected: [DiagnosticFailureSignal: (DiagnosticCategory, DiagnosticStage, DiagnosticCode)] = [
            .abnormalExit: (.application, .lifecycle, .abnormalExit),
            .protocolViolation(
                category: .dictation,
                stage: .streamFinish
            ): (.dictation, .streamFinish, .protocolViolation),
            .audioConversionFailed: (.dictation, .audioPump, .audioConversionFailed),
            .audioBufferOverflow: (.dictation, .audioPump, .audioBufferOverflow),
            .captureInternalFailure: (.dictation, .captureStart, .captureInternalFailure),
            .localStateReadFailed: (.authentication, .sessionRestore, .localStateReadFailed),
            .localStateWriteFailed: (.authentication, .sessionInstall, .localStateWriteFailed),
            .localStateDeleteFailed: (.authentication, .sessionDelete, .localStateDeleteFailed),
            .insertionTransactionBusy: (.insertion, .clipboardTransaction, .insertionTransactionBusy),
            .pasteboardSnapshotFailed: (.insertion, .clipboardTransaction, .pasteboardSnapshotFailed),
            .pasteboardWriteFailed: (.insertion, .clipboardTransaction, .pasteboardWriteFailed),
            .pasteEventFailed: (.insertion, .eventDelivery, .pasteEventFailed),
            .providerConfigurationInvalid: (.customASR, .providerConfiguration, .providerConfigurationInvalid),
            .providerProtocolViolation: (.customASR, .providerResponse, .providerProtocolViolation),
            .providerInternalFailure: (.customOptimization, .providerRequest, .internalError),
        ]

        for (signal, tuple) in expected {
            let incident = DiagnosticClassifier.incident(for: signal)
            XCTAssertEqual(incident?.category, tuple.0, "\(signal)")
            XCTAssertEqual(incident?.stage, tuple.1, "\(signal)")
            XCTAssertEqual(incident?.code, tuple.2, "\(signal)")
        }
    }

    private func makeReport(
        schemaVersion: Int = 1,
        promptVersion: Int = 1,
        appVersion: String = "1.0.0",
        build: String = "31",
        macOSVersion: String = "15.6.1",
        occurredAt: DiagnosticTimestamp? = nil,
        confirmedAt: DiagnosticTimestamp? = nil,
        events: [DiagnosticEvent]? = nil
    ) -> DiagnosticReportEnvelope {
        let occurredAt = occurredAt ?? DiagnosticTimestamp(date: fixedDate)
        let confirmedAt = confirmedAt ?? DiagnosticTimestamp(date: fixedDate)
        return DiagnosticReportEnvelope(
            schemaVersion: schemaVersion,
            reportId: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!,
            installationId: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            consent: DiagnosticConsent(
                promptVersion: promptVersion,
                confirmedAt: confirmedAt
            ),
            occurredAt: occurredAt,
            app: DiagnosticApp(
                version: appVersion,
                build: build,
                locale: .zhHans,
                architecture: .arm64
            ),
            system: DiagnosticSystem(
                macOSVersion: macOSVersion,
                microphone: .authorized,
                accessibility: .denied
            ),
            service: DiagnosticService(mode: .txchatCloud),
            incident: DiagnosticIncident(
                category: .dictation,
                taskId: UUID(uuidString: "99999999-8888-4777-8666-555555555555"),
                stage: .audioPump,
                code: .audioConversionFailed
            ),
            events: events ?? [
                DiagnosticEvent(
                    occurredAt: occurredAt,
                    category: .dictation,
                    taskId: nil,
                    stage: .audioPump,
                    code: .audioConversionFailed,
                    durationMs: 42,
                    httpStatus: nil
                ),
            ]
        )
    }

    private func event(
        duration: Int? = nil,
        httpStatus: Int? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            occurredAt: DiagnosticTimestamp(date: fixedDate),
            category: .dictation,
            taskId: nil,
            stage: .audioPump,
            code: .audioConversionFailed,
            durationMs: duration,
            httpStatus: httpStatus
        )
    }
}
