import Combine
import Foundation

enum ProductShortcutEditorState: Equatable, Sendable {
    case current
    case waiting
    case captured
    case conflict
    case unavailable
    case unsupported
    case saveFailed
}

@MainActor
final class ProductShortcutEditorModel: ObservableObject {
    @Published private(set) var state: ProductShortcutEditorState
    @Published private(set) var current: ProductShortcut
    @Published private(set) var candidate: ProductShortcut?
    @Published private(set) var invalidCandidateDisplayName: String?
    @Published private(set) var invalidMessage: String?

    init(current: ProductShortcut) {
        self.current = current
        state = .current
    }

    var displayedShortcut: ProductShortcut {
        candidate ?? current
    }

    var displayedName: String {
        invalidCandidateDisplayName ?? displayedShortcut.displayName
    }

    var canSave: Bool {
        (state == .captured || state == .saveFailed) && candidate != nil
    }

    func beginCapture() {
        candidate = nil
        invalidCandidateDisplayName = nil
        invalidMessage = nil
        state = .waiting
    }

    func capture(_ shortcut: ProductShortcut) {
        candidate = shortcut
        invalidCandidateDisplayName = nil
        invalidMessage = nil
        if shortcut.key == .rightOption {
            state = .unsupported
        } else {
            state = .captured
        }
    }

    func rejectCandidate(
        displayName: String,
        message: String? = nil
    ) {
        candidate = nil
        invalidCandidateDisplayName = displayName
        invalidMessage = message
        state = .unavailable
    }

    func cancelCapture() {
        candidate = nil
        invalidCandidateDisplayName = nil
        invalidMessage = nil
        state = .current
    }

    @discardableResult
    func save(
        using update: (ProductShortcut) -> ShortcutUpdateResult
    ) -> Bool {
        guard canSave, let candidate else {
            return false
        }

        switch update(candidate) {
        case .updated:
            current = candidate
            self.candidate = nil
            invalidCandidateDisplayName = nil
            invalidMessage = nil
            state = .current
            return true
        case .failed(.conflict):
            state = .conflict
        case .failed(.unavailable):
            state = .unavailable
        case .failed(.unsupported):
            state = .unsupported
        case .saveFailed:
            state = .saveFailed
        }
        return false
    }
}
