import Darwin
import Foundation
import XCTest
@testable import SpekWrite

final class DiagnosticStoreTests: XCTestCase {
    func testEventStoreIsContentFreeBoundedAndPurgesOlderThanSevenDays()
        async throws
    {
        let root = temporaryRoot()
        let now = Date(timeIntervalSince1970: 1_776_758_400)
        let store = DiagnosticEventStore(
            directoryURL: root,
            capacity: 3,
            now: { now }
        )
        try await store.append(event(at: now.addingTimeInterval(-8 * 86_400)))
        for offset in 0..<4 {
            try await store.append(
                event(at: now.addingTimeInterval(Double(offset)))
            )
        }

        let recent = try await store.recent(confirmedAt: now.addingTimeInterval(10))
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.durationMs), [1, 2, 3])
        XCTAssertLessThanOrEqual(recent.count, 20)
        assertSecurePermissions(root: root, fileName: "events.json")
    }

    func testEventStoreRejectsSymlinkFile() async throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let target = root.appendingPathComponent("outside.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data()))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("events.json"),
            withDestinationURL: target
        )
        let store = DiagnosticEventStore(directoryURL: root)

        await XCTAssertThrowsErrorAsync {
            try await store.append(self.event(at: Date()))
        }
    }

    func testEveryStoreRejectsSymlinkedDiagnosticsDirectory() async throws {
        let container = temporaryRoot()
        let outside = temporaryRoot()
        try FileManager.default.createDirectory(
            at: container,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let linkedDirectory = container.appendingPathComponent("Diagnostics")
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory,
            withDestinationURL: outside
        )

        let eventStore = DiagnosticEventStore(directoryURL: linkedDirectory)
        await XCTAssertThrowsErrorAsync {
            try await eventStore.append(self.event(at: Date()))
        }

        let cache = DiagnosticReportCache(
            directoryURL: linkedDirectory,
            now: { Date(timeIntervalSince1970: 1_776_758_400) }
        )
        await XCTAssertThrowsErrorAsync {
            try await cache.saveIfAbsent(self.report(reportID: UUID()))
        }

        let lifecycle = DiagnosticLifecycleStore(
            directoryURL: linkedDirectory
        )
        do {
            _ = try await lifecycle.beginRun()
            XCTFail("expected lifecycle directory symlink rejection")
        } catch let error as DiagnosticLifecycleStoreError {
            XCTAssertEqual(error, .writeFailed)
        }
    }

    func testCacheAndLifecycleRejectSymlinkFiles() async throws {
        let cacheRoot = temporaryRoot()
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        let cacheTarget = cacheRoot.appendingPathComponent("outside.json")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: cacheTarget.path,
                contents: Data("{}".utf8)
            )
        )
        try FileManager.default.createSymbolicLink(
            at: cacheRoot.appendingPathComponent("consented-report.json"),
            withDestinationURL: cacheTarget
        )
        let cache = DiagnosticReportCache(directoryURL: cacheRoot)
        await XCTAssertThrowsErrorAsync {
            _ = try await cache.load()
        }

        let lifecycleRoot = temporaryRoot()
        try FileManager.default.createDirectory(
            at: lifecycleRoot,
            withIntermediateDirectories: true
        )
        let lifecycleTarget = lifecycleRoot.appendingPathComponent(
            "outside.json"
        )
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: lifecycleTarget.path,
                contents: Data("{}".utf8)
            )
        )
        try FileManager.default.createSymbolicLink(
            at: lifecycleRoot.appendingPathComponent("running.json"),
            withDestinationURL: lifecycleTarget
        )
        let lifecycle = DiagnosticLifecycleStore(directoryURL: lifecycleRoot)
        do {
            _ = try await lifecycle.beginRun()
            XCTFail("expected lifecycle marker symlink rejection")
        } catch let error as DiagnosticLifecycleStoreError {
            XCTAssertEqual(error, .readFailed)
        }
    }

    func testOversizedAndCorruptFilesFailClosedForEveryStore() async throws {
        let oversizedEventsRoot = try populatedRoot(
            fileName: "events.json",
            data: Data(repeating: 0, count: 1_048_577)
        )
        let oversizedEvents = DiagnosticEventStore(
            directoryURL: oversizedEventsRoot
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await oversizedEvents.recent(confirmedAt: Date())
        }

        let corruptEventsRoot = try populatedRoot(
            fileName: "events.json",
            data: Data("{".utf8)
        )
        let corruptEvents = DiagnosticEventStore(
            directoryURL: corruptEventsRoot
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await corruptEvents.recent(confirmedAt: Date())
        }

        for data in [
            Data(repeating: 0, count: 65_537),
            Data("{".utf8),
        ] {
            let root = try populatedRoot(
                fileName: "consented-report.json",
                data: data
            )
            let cache = DiagnosticReportCache(directoryURL: root)
            await XCTAssertThrowsErrorAsync {
                _ = try await cache.load()
            }
        }

        for data in [
            Data(repeating: 0, count: 513),
            Data("{".utf8),
        ] {
            let root = try populatedRoot(
                fileName: "running.json",
                data: data
            )
            let lifecycle = DiagnosticLifecycleStore(directoryURL: root)
            do {
                _ = try await lifecycle.beginRun()
                XCTFail("expected invalid lifecycle marker rejection")
            } catch let error as DiagnosticLifecycleStoreError {
                XCTAssertEqual(error, .readFailed)
            }
        }
    }

    func testLifecycleMarkerReportsPreviousUncleanRunAndClearsOnTermination()
        async throws
    {
        let root = temporaryRoot()
        let store = DiagnosticLifecycleStore(directoryURL: root)

        let firstRunWasUnclean = try await store.beginRun()
        let secondRunWasUnclean = try await store.beginRun()
        XCTAssertFalse(firstRunWasUnclean)
        XCTAssertTrue(secondRunWasUnclean)
        try await store.endRun()
        let thirdRunWasUnclean = try await store.beginRun()
        XCTAssertFalse(thirdRunWasUnclean)
        try await store.endRun()
        assertSecurePermissions(root: root, fileName: nil)
    }

    func testLifecycleDeleteFailureLeavesCleanEvidenceAndDoesNotBecomeAbnormalExit()
        async throws
    {
        let root = temporaryRoot()
        let failingDeleteStore = DiagnosticLifecycleStore(
            directoryURL: root,
            deleteFile: { url in
                if url.lastPathComponent == "running.json" {
                    throw DiagnosticLocalStoreError.unsafePath
                }
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        )
        let firstLaunchWasUnclean = try await failingDeleteStore.beginRun()
        XCTAssertFalse(firstLaunchWasUnclean)
        do {
            try await failingDeleteStore.endRun()
            XCTFail("expected lifecycle delete failure")
        } catch let error as DiagnosticLifecycleStoreError {
            XCTAssertEqual(error, .deleteFailed)
        }

        let nextLaunch = DiagnosticLifecycleStore(directoryURL: root)
        let nextLaunchWasUnclean = try await nextLaunch.beginRun()
        XCTAssertFalse(
            nextLaunchWasUnclean,
            "a clean termination with failed marker deletion must not be reported as abnormal exit"
        )
        try await nextLaunch.endRun()
    }

    func testConsentedCacheIsImmutableUntilDeletedAndPurgedOnNextLaunch()
        async throws
    {
        let root = temporaryRoot()
        let cache = DiagnosticReportCache(
            directoryURL: root,
            now: { Date(timeIntervalSince1970: 1_776_758_400) }
        )
        let first = report(reportID: UUID())
        let second = report(reportID: UUID())

        try await cache.saveIfAbsent(first)
        try await cache.saveIfAbsent(second)
        let cached = try await cache.load()
        XCTAssertEqual(cached, first)
        assertSecurePermissions(root: root, fileName: "consented-report.json")

        try await cache.purgeOnLaunch()
        let purged = try await cache.load()
        XCTAssertNil(purged)
    }

    func testCacheRejectsInvalidEnvelopeBeforeCreatingStorage() async {
        let root = temporaryRoot()
        let now = Date(timeIntervalSince1970: 1_776_758_400)
        let cache = DiagnosticReportCache(directoryURL: root, now: { now })
        let invalid = report(
            reportID: UUID(),
            schemaVersion: 2
        )

        await XCTAssertThrowsErrorAsync {
            try await cache.saveIfAbsent(invalid)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSecureReadUsesOpenedDescriptorAfterPathBecomesSymlink()
        throws
    {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appendingPathComponent("events.json")
        let outside = temporaryRoot().appendingPathExtension("json")
        try Data("opened descriptor".utf8).write(to: file)
        try Data("outside secret".utf8).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let data = try DiagnosticSecureFile.read(
            from: file,
            maximumBytes: 1_024,
            hooks: DiagnosticSecureFileHooks(
                afterOpenForRead: {
                    try FileManager.default.removeItem(at: file)
                    try FileManager.default.createSymbolicLink(
                        at: file,
                        withDestinationURL: outside
                    )
                }
            )
        )

        XCTAssertEqual(data, Data("opened descriptor".utf8))
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside secret".utf8))
    }

    func testSecureWriteUsesDirectoryDescriptorAfterParentReplacement()
        throws
    {
        let root = temporaryRoot()
        let movedRoot = root.appendingPathExtension("opened")
        let outsideRoot = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outsideRoot,
            withIntermediateDirectories: true
        )
        let destination = root.appendingPathComponent("events.json")
        let outsideDestination = outsideRoot.appendingPathComponent("events.json")
        try Data("old".utf8).write(to: destination)
        try Data("outside".utf8).write(to: outsideDestination)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o640)],
            ofItemAtPath: outsideDestination.path
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: movedRoot)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        try DiagnosticSecureFile.write(
            Data("replacement".utf8),
            to: destination,
            hooks: DiagnosticSecureFileHooks(
                beforeRename: {
                    try FileManager.default.moveItem(at: root, to: movedRoot)
                    try FileManager.default.createSymbolicLink(
                        at: root,
                        withDestinationURL: outsideRoot
                    )
                }
            )
        )

        XCTAssertEqual(
            try Data(contentsOf: movedRoot.appendingPathComponent("events.json")),
            Data("replacement".utf8)
        )
        XCTAssertEqual(try Data(contentsOf: outsideDestination), Data("outside".utf8))
        XCTAssertEqual(fileMode(outsideDestination), 0o640)
        XCTAssertEqual(
            fileMode(movedRoot.appendingPathComponent("events.json")),
            0o600
        )
    }

    func testSecureWriteReplacesDestinationSymlinkWithoutTouchingTarget()
        throws
    {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let destination = root.appendingPathComponent("events.json")
        let outside = temporaryRoot().appendingPathExtension("json")
        try Data("old".utf8).write(to: destination)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o640)],
            ofItemAtPath: outside.path
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try DiagnosticSecureFile.write(
            Data("replacement".utf8),
            to: destination,
            hooks: DiagnosticSecureFileHooks(
                beforeRename: {
                    try FileManager.default.removeItem(at: destination)
                    try FileManager.default.createSymbolicLink(
                        at: destination,
                        withDestinationURL: outside
                    )
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
        XCTAssertEqual(fileMode(destination), 0o600)
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
        XCTAssertEqual(fileMode(outside), 0o640)
    }

    func testSecureDeleteUnlinksReplacementSymlinkWithoutTouchingTarget()
        throws
    {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appendingPathComponent("consented-report.json")
        let outside = temporaryRoot().appendingPathExtension("json")
        try Data("cached".utf8).write(to: file)
        try Data("outside".utf8).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try DiagnosticSecureFile.delete(
            file,
            hooks: DiagnosticSecureFileHooks(
                beforeUnlink: {
                    try FileManager.default.removeItem(at: file)
                    try FileManager.default.createSymbolicLink(
                        at: file,
                        withDestinationURL: outside
                    )
                }
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
    }

    func testSecureWritePropagatesDirectorySyncFailure() throws {
        let root = temporaryRoot()
        let file = root.appendingPathComponent("events.json")
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try DiagnosticSecureFile.write(
                Data("durable".utf8),
                to: file,
                hooks: DiagnosticSecureFileHooks(
                    beforeDirectorySync: { descriptor in
                        _ = Darwin.close(descriptor)
                    }
                )
            )
        ) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EBADF))
        }
    }

    func testSecureDeletePropagatesDirectorySyncFailure() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appendingPathComponent("events.json")
        try Data("durable".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try DiagnosticSecureFile.delete(
                file,
                hooks: DiagnosticSecureFileHooks(
                    beforeDirectorySync: { descriptor in
                        _ = Darwin.close(descriptor)
                    }
                )
            )
        ) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EBADF))
        }
    }

    private func event(at date: Date) -> DiagnosticEvent {
        DiagnosticEvent(
            occurredAt: DiagnosticTimestamp(date: date),
            category: .dictation,
            taskId: nil,
            stage: .audioPump,
            code: .audioConversionFailed,
            durationMs: Int(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 4)),
            httpStatus: nil
        )
    }

    private func report(
        reportID: UUID,
        schemaVersion: Int = 1
    ) -> DiagnosticReportEnvelope {
        let timestamp = DiagnosticTimestamp(date: Date(timeIntervalSince1970: 1_776_758_400))
        return DiagnosticReportEnvelope(
            schemaVersion: schemaVersion,
            reportId: reportID,
            installationId: UUID(),
            consent: DiagnosticConsent(promptVersion: 1, confirmedAt: timestamp),
            occurredAt: timestamp,
            app: DiagnosticApp(version: "1.0.0", build: "31", locale: .zhHans, architecture: .arm64),
            system: DiagnosticSystem(macOSVersion: "15.6", microphone: .authorized, accessibility: .authorized),
            service: DiagnosticService(mode: .txchatCloud),
            incident: DiagnosticIncident(category: .application, taskId: nil, stage: .lifecycle, code: .abnormalExit),
            events: []
        )
    }

    private func temporaryRoot() -> URL {
        URL(
            fileURLWithPath:
                "/private" + FileManager.default.temporaryDirectory.path,
            isDirectory: true
        )
            .appendingPathComponent("txchat-diagnostic-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func populatedRoot(
        fileName: String,
        data: Data
    ) throws -> URL {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try data.write(to: root.appendingPathComponent(fileName))
        return root
    }

    private func assertSecurePermissions(root: URL, fileName: String?) {
        let directoryMode = try? FileManager.default.attributesOfItem(
            atPath: root.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        if let fileName {
            let fileMode = try? FileManager.default.attributesOfItem(
                atPath: root.appendingPathComponent(fileName).path
            )[.posixPermissions] as? NSNumber
            XCTAssertEqual(fileMode?.intValue, 0o600)
        }
    }

    private func fileMode(_ url: URL) -> Int? {
        let mode = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? NSNumber
        return mode?.intValue
    }
}
