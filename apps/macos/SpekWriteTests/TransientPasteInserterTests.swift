import AppKit
import Foundation
import XCTest
@testable import SpekWrite

@MainActor
private final class PasteboardTransactionFake:
    PasteboardTransactionServing
{
    var snapshotValue: PasteboardSnapshot? = PasteboardSnapshot(items: [])
    var transientChangeCount: Int? = 11
    var restoreResult = true
    private(set) var writtenTexts: [String] = []
    private(set) var restoreCalls: [(PasteboardSnapshot, Int)] = []

    func snapshot() -> PasteboardSnapshot? { snapshotValue }

    func writeTransientText(
        _ text: String,
        preserving snapshot: PasteboardSnapshot
    ) -> Int? {
        _ = snapshot
        writtenTexts.append(text)
        return transientChangeCount
    }

    func restore(
        _ snapshot: PasteboardSnapshot,
        ifOwned changeCount: Int
    ) -> Bool {
        restoreCalls.append((snapshot, changeCount))
        return restoreResult
    }
}

@MainActor
private final class PasteboardAccessFake: PasteboardAccessing {
    var pasteboardItems: [NSPasteboardItem]?
    private(set) var changeCount = 1
    var writeResults: [Bool] = []
    var externallyReplaceAfterWrite = false
    private(set) var clearCallCount = 0

    @discardableResult
    func clearContents() -> Int {
        clearCallCount += 1
        changeCount += 1
        pasteboardItems = []
        return changeCount
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        let result = writeResults.isEmpty ? true : writeResults.removeFirst()
        if result {
            pasteboardItems = objects.compactMap { $0 as? NSPasteboardItem }
        }
        if externallyReplaceAfterWrite {
            let external = NSPasteboardItem()
            _ = external.setString("external", forType: .string)
            pasteboardItems = [external]
            changeCount += 1
        }
        return result
    }
}

@MainActor
private final class PasteCommandPosterFake: PasteCommandPosting {
    var result = true
    private(set) var callCount = 0

    func postCommandV() -> Bool {
        callCount += 1
        return result
    }
}

@MainActor
private final class TextPasteCommandCapabilityQueryFake:
    CoreTextPasteCommandCapabilityQuerying
{
    var result = true
    private(set) var processIdentifierCalls: [[pid_t]] = []

    func isPlainTextPasteCommandEnabled(
        processIdentifiers: [pid_t]
    ) -> Bool {
        processIdentifierCalls.append(processIdentifiers)
        return result
    }
}

@MainActor
private final class PasteRestoreSchedulerFake: PasteRestoreScheduling {
    private(set) var delays: [TimeInterval] = []
    private var actions: [@MainActor @Sendable () -> Void] = []

    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        delays.append(delay)
        actions.append(action)
    }

    func runScheduledActions() {
        let pending = actions
        actions.removeAll()
        pending.forEach { $0() }
    }
}

@MainActor
private final class InsertionDiagnosticRecorderFake:
    CoreInsertionDiagnosticRecording
{
    private(set) var events: [CoreInsertionDiagnosticEvent] = []

    func record(_ event: CoreInsertionDiagnosticEvent) {
        events.append(event)
    }
}

@MainActor
final class TransientPasteInserterTests: XCTestCase {
    func testTextPasteCapabilityProbeRestoresClipboardBeforeAccepting() {
        let pasteboard = PasteboardTransactionFake()
        let query = TextPasteCommandCapabilityQueryFake()
        let probe = CoreTextPasteCapabilityProbe(
            pasteboard: pasteboard,
            query: query
        )

        XCTAssertTrue(
            probe.canPastePlainText(processIdentifiers: [42, 84])
        )
        XCTAssertEqual(query.processIdentifierCalls, [[42, 84]])
        XCTAssertEqual(pasteboard.writtenTexts.count, 1)
        XCTAssertFalse(pasteboard.writtenTexts[0].isEmpty)
        XCTAssertEqual(pasteboard.restoreCalls.count, 1)
        XCTAssertEqual(pasteboard.restoreCalls[0].1, 11)
    }

    func testTextPasteCapabilityProbeFailsClosedOnEveryTransactionFailure() {
        let query = TextPasteCommandCapabilityQueryFake()

        let missingSnapshot = PasteboardTransactionFake()
        missingSnapshot.snapshotValue = nil
        XCTAssertFalse(
            CoreTextPasteCapabilityProbe(
                pasteboard: missingSnapshot,
                query: query
            ).canPastePlainText(processIdentifiers: [42])
        )
        XCTAssertTrue(query.processIdentifierCalls.isEmpty)

        let failedWrite = PasteboardTransactionFake()
        failedWrite.transientChangeCount = nil
        XCTAssertFalse(
            CoreTextPasteCapabilityProbe(
                pasteboard: failedWrite,
                query: query
            ).canPastePlainText(processIdentifiers: [42])
        )
        XCTAssertTrue(query.processIdentifierCalls.isEmpty)

        let disabledCommand = PasteboardTransactionFake()
        query.result = false
        XCTAssertFalse(
            CoreTextPasteCapabilityProbe(
                pasteboard: disabledCommand,
                query: query
            ).canPastePlainText(processIdentifiers: [42])
        )
        XCTAssertEqual(disabledCommand.restoreCalls.count, 1)

        let failedRestore = PasteboardTransactionFake()
        failedRestore.restoreResult = false
        query.result = true
        XCTAssertFalse(
            CoreTextPasteCapabilityProbe(
                pasteboard: failedRestore,
                query: query
            ).canPastePlainText(processIdentifiers: [42])
        )
        XCTAssertEqual(failedRestore.restoreCalls.count, 1)
    }

    func testSystemTransactionWritesValidTransientTextTypes() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "org.example.txchat.tests.\(UUID().uuidString)"
            )
        )
        let transaction = SystemPasteboardTransaction(pasteboard: pasteboard)
        let snapshot = transaction.snapshot()!

        XCTAssertNotNil(
            transaction.writeTransientText(
                "dictated",
                preserving: snapshot
            )
        )
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "dictated"
        )
        XCTAssertTrue(
            pasteboard.types?.contains(
                NSPasteboard.PasteboardType(
                    "org.nspasteboard.TransientType"
                )
            ) == true
        )
    }

    func testSystemTransactionRoundTripsEveryItemAndType() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "org.example.txchat.tests.\(UUID().uuidString)"
            )
        )
        let first = NSPasteboardItem()
        XCTAssertTrue(first.setString("before", forType: .string))
        XCTAssertTrue(
            first.setData(
                Data("<b>before</b>".utf8),
                forType: .html
            )
        )
        let second = NSPasteboardItem()
        let customType = NSPasteboard.PasteboardType(
            "org.example.txchat.tests.binary"
        )
        XCTAssertTrue(second.setData(Data([0, 1, 2, 3]), forType: customType))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let transaction = SystemPasteboardTransaction(pasteboard: pasteboard)
        let snapshot = transaction.snapshot()!

        let owned = transaction.writeTransientText(
            "dictated",
            preserving: snapshot
        )!
        XCTAssertTrue(transaction.restore(snapshot, ifOwned: owned))

        XCTAssertEqual(transaction.snapshot(), snapshot)
    }

    func testSystemTransactionRejectsUnrestorableSnapshotBeforeClearing() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "org.example.txchat.tests.\(UUID().uuidString)"
            )
        )
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("before", forType: .string))
        let transaction = SystemPasteboardTransaction(pasteboard: pasteboard)
        let invalid = PasteboardSnapshot(items: [
            .init(values: ["NSStringPboardType": Data("before".utf8)]),
        ])

        XCTAssertNil(
            transaction.writeTransientText(
                "dictated",
                preserving: invalid
            )
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testFailedTransientWriteImmediatelyRestoresTheOriginalSnapshot() {
        let originalItem = NSPasteboardItem()
        XCTAssertTrue(originalItem.setString("before", forType: .string))
        let pasteboard = PasteboardAccessFake()
        pasteboard.pasteboardItems = [originalItem]
        pasteboard.writeResults = [false, true]
        let transaction = SystemPasteboardTransaction(access: pasteboard)
        let snapshot = transaction.snapshot()!

        XCTAssertNil(
            transaction.writeTransientText(
                "dictated",
                preserving: snapshot
            )
        )

        XCTAssertEqual(transaction.snapshot(), snapshot)
        XCTAssertEqual(pasteboard.clearCallCount, 2)
    }

    func testFailedTransientWriteNeverRestoresOverAConcurrentOwner() {
        let original = NSPasteboardItem()
        XCTAssertTrue(original.setString("before", forType: .string))
        let pasteboard = PasteboardAccessFake()
        pasteboard.pasteboardItems = [original]
        pasteboard.writeResults = [false]
        pasteboard.externallyReplaceAfterWrite = true
        let transaction = SystemPasteboardTransaction(access: pasteboard)
        let snapshot = transaction.snapshot()!

        XCTAssertNil(
            transaction.writeTransientText(
                "dictated",
                preserving: snapshot
            )
        )

        XCTAssertEqual(
            pasteboard.pasteboardItems?.first?.string(forType: .string),
            "external"
        )
        XCTAssertEqual(pasteboard.clearCallCount, 1)
    }

    func testSuccessfulTransientWriteNeverClaimsAConcurrentOwner() {
        let original = NSPasteboardItem()
        XCTAssertTrue(original.setString("before", forType: .string))
        let pasteboard = PasteboardAccessFake()
        pasteboard.pasteboardItems = [original]
        pasteboard.writeResults = [true]
        pasteboard.externallyReplaceAfterWrite = true
        let transaction = SystemPasteboardTransaction(access: pasteboard)
        let snapshot = transaction.snapshot()!

        XCTAssertNil(
            transaction.writeTransientText(
                "dictated",
                preserving: snapshot
            )
        )
        XCTAssertEqual(
            pasteboard.pasteboardItems?.first?.string(forType: .string),
            "external"
        )
    }

    func testSuccessfulPastePostsThroughTheForegroundEventStreamAndRestoresOwnedSnapshot() {
        let pasteboard = PasteboardTransactionFake()
        pasteboard.snapshotValue = PasteboardSnapshot(items: [
            .init(values: [
                "public.html": Data("<b>before</b>".utf8),
                "public.utf8-plain-text": Data("before".utf8),
            ]),
        ])
        let poster = PasteCommandPosterFake()
        let scheduler = PasteRestoreSchedulerFake()
        let diagnostics = InsertionDiagnosticRecorderFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: scheduler,
            diagnostics: diagnostics
        )

        XCTAssertTrue(inserter.insert("dictated", into: 42))
        XCTAssertEqual(pasteboard.writtenTexts, ["dictated"])
        XCTAssertEqual(poster.callCount, 1)
        XCTAssertEqual(pasteboard.restoreCalls.count, 0)
        XCTAssertEqual(scheduler.delays, [0.8])
        XCTAssertEqual(diagnostics.events, [.pasteAccepted])

        scheduler.runScheduledActions()

        XCTAssertEqual(pasteboard.restoreCalls.count, 1)
        XCTAssertEqual(pasteboard.restoreCalls.first?.1, 11)
        XCTAssertEqual(
            pasteboard.restoreCalls.first?.0,
            pasteboard.snapshotValue
        )
    }

    func testFailedEventRestoresImmediately() {
        let pasteboard = PasteboardTransactionFake()
        let poster = PasteCommandPosterFake()
        poster.result = false
        let scheduler = PasteRestoreSchedulerFake()
        let diagnostics = InsertionDiagnosticRecorderFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: scheduler,
            diagnostics: diagnostics
        )

        XCTAssertFalse(inserter.insert("dictated", into: 42))
        XCTAssertEqual(pasteboard.restoreCalls.count, 1)
        XCTAssertTrue(scheduler.delays.isEmpty)
        XCTAssertEqual(diagnostics.events, [.pasteEventFailed])
    }

    func testOverlappingPasteIsRejectedUntilTheOwnedRestoreFinishes() {
        let pasteboard = PasteboardTransactionFake()
        let poster = PasteCommandPosterFake()
        let scheduler = PasteRestoreSchedulerFake()
        let diagnostics = InsertionDiagnosticRecorderFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: scheduler,
            diagnostics: diagnostics
        )

        XCTAssertTrue(inserter.insert("first", into: 42))
        XCTAssertFalse(inserter.insert("second", into: 42))
        XCTAssertEqual(pasteboard.writtenTexts, ["first"])
        XCTAssertEqual(poster.callCount, 1)

        scheduler.runScheduledActions()

        XCTAssertTrue(inserter.insert("third", into: 42))
        XCTAssertEqual(pasteboard.writtenTexts, ["first", "third"])
        XCTAssertEqual(poster.callCount, 2)
    }

    func testExternalPasteboardChangeSkipsRestoreAndReleasesTransaction() {
        let pasteboard = PasteboardTransactionFake()
        pasteboard.restoreResult = false
        let poster = PasteCommandPosterFake()
        let scheduler = PasteRestoreSchedulerFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: scheduler
        )

        XCTAssertTrue(inserter.insert("first", into: 42))
        scheduler.runScheduledActions()
        XCTAssertEqual(pasteboard.restoreCalls.count, 1)

        XCTAssertTrue(inserter.insert("second", into: 42))
        XCTAssertEqual(pasteboard.writtenTexts, ["first", "second"])
    }

    func testSnapshotOrTransientWriteFailureNeverPostsPaste() {
        let pasteboard = PasteboardTransactionFake()
        let poster = PasteCommandPosterFake()
        let diagnostics = InsertionDiagnosticRecorderFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: PasteRestoreSchedulerFake(),
            diagnostics: diagnostics
        )

        pasteboard.snapshotValue = nil
        XCTAssertFalse(inserter.insert("dictated", into: 42))
        XCTAssertEqual(diagnostics.events, [.pasteboardSnapshotFailed])
        pasteboard.snapshotValue = PasteboardSnapshot(items: [])
        pasteboard.transientChangeCount = nil
        XCTAssertFalse(inserter.insert("dictated", into: 42))
        XCTAssertEqual(
            diagnostics.events,
            [.pasteboardSnapshotFailed, .pasteboardWriteFailed]
        )
        XCTAssertEqual(poster.callCount, 0)
    }

    func testEmptyTextNeverTouchesPasteboard() {
        let pasteboard = PasteboardTransactionFake()
        let poster = PasteCommandPosterFake()
        let inserter = TransientPasteInserter(
            pasteboard: pasteboard,
            poster: poster,
            scheduler: PasteRestoreSchedulerFake()
        )

        XCTAssertFalse(inserter.insert("", into: 42))
        XCTAssertTrue(pasteboard.writtenTexts.isEmpty)
        XCTAssertEqual(poster.callCount, 0)
    }
}
