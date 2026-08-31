import AppKit
import ApplicationServices
import Foundation
import OSLog

enum CoreInsertionDiagnosticEvent: String, Equatable, Sendable {
    case captureAuthorizationFailed = "capture_authorization_failed"
    case captureSecureInput = "capture_secure_input"
    case captureFrontmostInvalid = "capture_frontmost_invalid"
    case captureOwnProcess = "capture_own_process"
    case captureFocusedProcessChanged = "capture_focused_process_changed"
    case captureFocusedElementUnavailable =
        "capture_focused_element_unavailable"
    case captureTargetUnsupported = "capture_target_unsupported"
    case captureSystemPasteCapabilityAccepted =
        "capture_system_paste_capability_accepted"
    case captureSucceeded = "capture_succeeded"
    case captureWindowFallbackSucceeded = "capture_window_fallback_succeeded"
    case accessibilityPreparationStarted =
        "accessibility_preparation_started"
    case insertionEmptyText = "insertion_empty_text"
    case insertionTargetMissing = "insertion_target_missing"
    case insertionTargetIdentityMismatch = "insertion_target_identity_mismatch"
    case insertionSecureInput = "insertion_secure_input"
    case insertionFrontmostChanged = "insertion_frontmost_changed"
    case insertionFocusedProcessChanged = "insertion_focused_process_changed"
    case insertionCurrentTargetUnsupported = "insertion_current_target_unsupported"
    case insertionTransactionBusy = "insertion_transaction_busy"
    case directAXSucceeded = "direct_ax_succeeded"
    case pasteFallbackStarted = "paste_fallback_started"
    case pasteboardSnapshotFailed = "pasteboard_snapshot_failed"
    case pasteboardWriteFailed = "pasteboard_write_failed"
    case pasteEventFailed = "paste_event_failed"
    case pasteAccepted = "paste_accepted"

    var stage: CoreInsertionDiagnosticStage {
        switch self {
        case .captureAuthorizationFailed, .captureSecureInput,
             .insertionSecureInput:
            return .securityGate
        case .captureFrontmostInvalid, .captureOwnProcess,
             .captureFocusedProcessChanged,
             .captureFocusedElementUnavailable,
             .captureTargetUnsupported,
             .captureSystemPasteCapabilityAccepted,
             .captureSucceeded, .captureWindowFallbackSucceeded,
             .accessibilityPreparationStarted:
            return .focusedTargetCapture
        case .insertionEmptyText, .insertionTargetMissing,
             .insertionTargetIdentityMismatch,
             .insertionFrontmostChanged,
             .insertionFocusedProcessChanged,
             .insertionCurrentTargetUnsupported:
            return .targetContinuity
        case .insertionTransactionBusy, .pasteboardSnapshotFailed,
             .pasteboardWriteFailed:
            return .clipboardTransaction
        case .directAXSucceeded, .pasteFallbackStarted,
             .pasteEventFailed, .pasteAccepted:
            return .eventDelivery
        }
    }
}

enum CoreInsertionDiagnosticStage: String, Equatable, Sendable {
    case securityGate = "security_gate"
    case focusedTargetCapture = "focused_target_capture"
    case targetContinuity = "target_continuity"
    case clipboardTransaction = "clipboard_transaction"
    case eventDelivery = "event_delivery"
}

@MainActor
protocol CoreInsertionDiagnosticRecording: AnyObject {
    func record(_ event: CoreInsertionDiagnosticEvent)
}

@MainActor
final class SystemCoreInsertionDiagnosticRecorder:
    CoreInsertionDiagnosticRecording
{
    private let logger = Logger(
        subsystem: "org.example.txchat.TxChat",
        category: "text-insertion"
    )

    func record(_ event: CoreInsertionDiagnosticEvent) {
        logger.notice(
            "stage=\(event.stage.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public)"
        )
    }
}

struct PasteboardSnapshot: Equatable {
    struct Item: Equatable {
        let values: [String: Data]
    }

    let items: [Item]
}

@MainActor
protocol PasteboardAccessing: AnyObject {
    var pasteboardItems: [NSPasteboardItem]? { get }
    var changeCount: Int { get }

    @discardableResult
    func clearContents() -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardAccessing {}

@MainActor
protocol PasteboardTransactionServing: AnyObject {
    func snapshot() -> PasteboardSnapshot?
    func writeTransientText(
        _ text: String,
        preserving snapshot: PasteboardSnapshot
    ) -> Int?
    func restore(
        _ snapshot: PasteboardSnapshot,
        ifOwned changeCount: Int
    ) -> Bool
}

@MainActor
protocol PasteCommandPosting: AnyObject {
    func postCommandV() -> Bool
}

@MainActor
protocol PasteRestoreScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    )
}

@MainActor
final class SystemPasteboardTransaction: PasteboardTransactionServing {
    private static let transient = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    private let pasteboard: any PasteboardAccessing

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    init(access: any PasteboardAccessing) {
        pasteboard = access
    }

    func snapshot() -> PasteboardSnapshot? {
        let sourceItems = pasteboard.pasteboardItems ?? []
        var items: [PasteboardSnapshot.Item] = []
        items.reserveCapacity(sourceItems.count)
        for source in sourceItems {
            var values: [String: Data] = [:]
            for type in source.types {
                guard let data = source.data(forType: type) else {
                    return nil
                }
                values[type.rawValue] = data
            }
            items.append(.init(values: values))
        }
        return PasteboardSnapshot(items: items)
    }

    func writeTransientText(
        _ text: String,
        preserving snapshot: PasteboardSnapshot
    ) -> Int? {
        guard !text.isEmpty, let restoredItems = items(for: snapshot) else {
            return nil
        }
        let item = NSPasteboardItem()
        guard
            item.setString(text, forType: .string),
            item.setData(Data(), forType: Self.transient)
        else {
            return nil
        }
        let clearedChangeCount = pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            _ = restore(
                restoredItems,
                ifOwned: clearedChangeCount
            )
            return nil
        }
        guard pasteboard.changeCount == clearedChangeCount else {
            return nil
        }
        return clearedChangeCount
    }

    func restore(
        _ snapshot: PasteboardSnapshot,
        ifOwned changeCount: Int
    ) -> Bool {
        guard let restoredItems = items(for: snapshot) else {
            return false
        }
        return restore(restoredItems, ifOwned: changeCount)
    }

    private func items(
        for snapshot: PasteboardSnapshot
    ) -> [NSPasteboardItem]? {
        var restoredItems: [NSPasteboardItem] = []
        restoredItems.reserveCapacity(snapshot.items.count)
        for source in snapshot.items {
            let item = NSPasteboardItem()
            for (rawType, data) in source.values {
                guard item.setData(
                    data,
                    forType: NSPasteboard.PasteboardType(rawType)
                ) else {
                    return nil
                }
            }
            restoredItems.append(item)
        }
        return restoredItems
    }

    private func restore(
        _ restoredItems: [NSPasteboardItem],
        ifOwned changeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == changeCount else {
            return false
        }
        pasteboard.clearContents()
        return restoredItems.isEmpty || pasteboard.writeObjects(restoredItems)
    }
}

@MainActor
final class SystemPasteCommandPoster: PasteCommandPosting {
    func postCommandV() -> Bool {
        guard
            let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 9,
                keyDown: true
            ),
            let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 9,
                keyDown: false
            )
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor
final class MainQueuePasteRestoreScheduler: PasteRestoreScheduling {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(Int64(max(0, delay) * 1_000))
            )
            action()
        }
    }
}

@MainActor
final class TransientPasteInserter {
    private static let restoreDelay: TimeInterval = 0.8

    private let pasteboard: any PasteboardTransactionServing
    private let poster: any PasteCommandPosting
    private let scheduler: any PasteRestoreScheduling
    private let diagnostics: any CoreInsertionDiagnosticRecording
    private var activeTransactionIdentifier: UUID?

    init(
        pasteboard: any PasteboardTransactionServing =
            SystemPasteboardTransaction(),
        poster: any PasteCommandPosting = SystemPasteCommandPoster(),
        scheduler: any PasteRestoreScheduling =
            MainQueuePasteRestoreScheduler(),
        diagnostics: any CoreInsertionDiagnosticRecording =
            SystemCoreInsertionDiagnosticRecorder()
    ) {
        self.pasteboard = pasteboard
        self.poster = poster
        self.scheduler = scheduler
        self.diagnostics = diagnostics
    }

    func insert(_ text: String, into processIdentifier: pid_t) -> Bool {
        guard !text.isEmpty, processIdentifier > 0 else {
            diagnostics.record(.insertionEmptyText)
            return false
        }
        guard activeTransactionIdentifier == nil else {
            diagnostics.record(.insertionTransactionBusy)
            return false
        }
        guard let snapshot = pasteboard.snapshot() else {
            diagnostics.record(.pasteboardSnapshotFailed)
            return false
        }
        guard let ownedChangeCount = pasteboard.writeTransientText(
            text,
            preserving: snapshot
        ) else {
            diagnostics.record(.pasteboardWriteFailed)
            return false
        }
        let transactionIdentifier = UUID()
        activeTransactionIdentifier = transactionIdentifier
        guard poster.postCommandV() else {
            diagnostics.record(.pasteEventFailed)
            _ = pasteboard.restore(snapshot, ifOwned: ownedChangeCount)
            activeTransactionIdentifier = nil
            return false
        }
        diagnostics.record(.pasteAccepted)
        scheduler.schedule(after: Self.restoreDelay) { [weak self] in
            guard let self,
                  activeTransactionIdentifier == transactionIdentifier else {
                return
            }
            _ = pasteboard.restore(snapshot, ifOwned: ownedChangeCount)
            activeTransactionIdentifier = nil
        }
        return true
    }
}
