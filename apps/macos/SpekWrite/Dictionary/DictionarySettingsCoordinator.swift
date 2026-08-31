import AppKit
import Combine
import Foundation

protocol DictionarySettingsServicing: Sendable {
    var fileURL: URL { get }
    func loadForEditing() async throws -> TxChatDictionaryDocument
    func reload() async throws -> TxChatDictionaryDocument
    func save(
        _ entries: [TxChatDictionaryEntry]
    ) async throws -> TxChatDictionaryDocument
    func ensureFileExists() async throws -> URL
}

extension ProductDictionaryRuntime: DictionarySettingsServicing {}

@MainActor
protocol DictionaryFileRevealing: AnyObject {
    func reveal(_ url: URL)
}

@MainActor
final class SystemDictionaryFileRevealer: DictionaryFileRevealing {
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum DictionarySettingsNotice: Equatable, Sendable {
    case partialReload(skippedLineCount: Int)
    case loadFailed
    case reloadFailed
    case saveFailed
    case openFileFailed
}

enum DictionaryEditorValidationError: Equatable, Sendable {
    case wrongEmpty
    case correctEmpty
    case valuesEqual
    case fieldTooLong
    case duplicateWrong
    case invalidLineBreak
}

struct DictionaryEditorState: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case add
        case edit(index: Int)
    }

    let mode: Mode
    var wrong: String
    var correct: String
    var isEnabled: Bool
    var validationError: DictionaryEditorValidationError?
    var isDeleteConfirmationPresented: Bool
}

@MainActor
final class DictionarySettingsCoordinator: ObservableObject {
    typealias CloseHandler = @MainActor () -> Void

    @Published private(set) var entries: [TxChatDictionaryEntry] = []
    @Published private(set) var editor: DictionaryEditorState?
    @Published private(set) var pendingCardDeletionIndex: Int?
    @Published private(set) var notice: DictionarySettingsNotice?
    @Published private(set) var isBusy = false

    var isDirty: Bool { entries != persistedEntries }
    var isEmpty: Bool { entries.isEmpty }

    private let service: any DictionarySettingsServicing
    private let fileRevealer: any DictionaryFileRevealing
    private var persistedEntries: [TxChatDictionaryEntry] = []
    private var closeHandler: CloseHandler = {}

    init(
        service: any DictionarySettingsServicing,
        fileRevealer: any DictionaryFileRevealing =
            SystemDictionaryFileRevealer()
    ) {
        self.service = service
        self.fileRevealer = fileRevealer
    }

#if DEBUG
    init(
        visualEntries: [TxChatDictionaryEntry],
        editor: DictionaryEditorState? = nil,
        pendingCardDeletionIndex: Int? = nil,
        notice: DictionarySettingsNotice? = nil
    ) {
        service = PreviewDictionarySettingsService(entries: visualEntries)
        fileRevealer = SystemDictionaryFileRevealer()
        entries = visualEntries
        persistedEntries = visualEntries
        self.editor = editor
        self.pendingCardDeletionIndex = pendingCardDeletionIndex
        self.notice = notice
    }
#endif

    func setCloseHandler(_ handler: @escaping CloseHandler) {
        closeHandler = handler
    }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            apply(try await service.loadForEditing())
        } catch {
            notice = .loadFailed
        }
    }

    func reload() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            apply(try await service.reload())
        } catch {
            notice = .reloadFailed
        }
    }

    func save() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let document = try await service.save(entries)
            persistedEntries = document.entries
            entries = document.entries
            notice = nil
            closeHandler()
        } catch {
            notice = .saveFailed
        }
    }

    func openFile() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            fileRevealer.reveal(try await service.ensureFileExists())
        } catch {
            notice = .openFileFailed
        }
    }

    func cancel() {
        entries = persistedEntries
        editor = nil
        pendingCardDeletionIndex = nil
        notice = nil
        closeHandler()
    }

    func dismissNotice() {
        notice = nil
    }

    func presentAddEditor() {
        guard entries.count < TxChatDictionaryLimits.maximumEntryCount else {
            return
        }
        editor = DictionaryEditorState(
            mode: .add,
            wrong: "",
            correct: "",
            isEnabled: true,
            validationError: nil,
            isDeleteConfirmationPresented: false
        )
    }

    func presentEditEditor(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        editor = DictionaryEditorState(
            mode: .edit(index: index),
            wrong: entry.wrong,
            correct: entry.correct,
            isEnabled: entry.isEnabled,
            validationError: nil,
            isDeleteConfirmationPresented: false
        )
    }

    func dismissEditor() {
        editor = nil
    }

    func updateEditorWrong(_ value: String) {
        guard var editor else { return }
        guard editor.wrong != value else { return }
        editor.wrong = value
        editor.validationError = nil
        self.editor = editor
    }

    func updateEditorCorrect(_ value: String) {
        guard var editor else { return }
        guard editor.correct != value else { return }
        editor.correct = value
        editor.validationError = nil
        self.editor = editor
    }

    func updateEditorEnabled(_ value: Bool) {
        guard var editor else { return }
        editor.isEnabled = value
        self.editor = editor
    }

    func confirmEditor() {
        guard var editor else { return }
        if let validationError = validate(editor) {
            editor.validationError = validationError
            self.editor = editor
            return
        }
        let entry = TxChatDictionaryEntry(
            wrong: editor.wrong,
            correct: editor.correct,
            isEnabled: editor.isEnabled
        )
        switch editor.mode {
        case .add:
            entries.insert(entry, at: 0)
        case let .edit(index):
            guard entries.indices.contains(index) else {
                self.editor = nil
                return
            }
            entries[index] = entry
        }
        self.editor = nil
    }

    func requestEditorDeletion() {
        guard var editor, case .edit = editor.mode else { return }
        editor.isDeleteConfirmationPresented = true
        self.editor = editor
    }

    func cancelEditorDeletion() {
        guard var editor else { return }
        editor.isDeleteConfirmationPresented = false
        self.editor = editor
    }

    func confirmEditorDeletion() {
        guard let editor, case let .edit(index) = editor.mode else { return }
        if entries.indices.contains(index) {
            entries.remove(at: index)
        }
        self.editor = nil
    }

    func setEnabled(_ value: Bool, at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries[index].isEnabled = value
    }

    func requestCardDeletion(at index: Int) {
        guard entries.indices.contains(index) else { return }
        pendingCardDeletionIndex = index
    }

    func cancelCardDeletion() {
        pendingCardDeletionIndex = nil
    }

    func confirmCardDeletion() {
        guard let index = pendingCardDeletionIndex else { return }
        if entries.indices.contains(index) {
            entries.remove(at: index)
        }
        pendingCardDeletionIndex = nil
    }

    private func apply(_ document: TxChatDictionaryDocument) {
        entries = document.entries
        persistedEntries = document.entries
        editor = nil
        pendingCardDeletionIndex = nil
        notice = document.skippedLineCount > 0
            ? .partialReload(skippedLineCount: document.skippedLineCount)
            : nil
    }

    private func validate(
        _ editor: DictionaryEditorState
    ) -> DictionaryEditorValidationError? {
        if editor.wrong.isEmpty { return .wrongEmpty }
        if editor.correct.isEmpty { return .correctEmpty }
        if editor.wrong == editor.correct { return .valuesEqual }
        if editor.wrong.count > TxChatDictionaryLimits.maximumFieldLength
            || editor.correct.count > TxChatDictionaryLimits.maximumFieldLength
        {
            return .fieldTooLong
        }
        if editor.wrong.contains(where: { $0.isNewline })
            || editor.correct.contains(where: { $0.isNewline })
        {
            return .invalidLineBreak
        }
        let editedIndex: Int? = switch editor.mode {
        case .add: nil
        case let .edit(index): index
        }
        if entries.enumerated().contains(where: { index, entry in
            index != editedIndex && entry.wrong == editor.wrong
        }) {
            return .duplicateWrong
        }
        return nil
    }
}

#if DEBUG
private actor PreviewDictionarySettingsService: DictionarySettingsServicing {
    nonisolated let fileURL = URL(fileURLWithPath: "/preview/TxChat-Dictionary.md")
    private var entries: [TxChatDictionaryEntry]

    init(entries: [TxChatDictionaryEntry]) {
        self.entries = entries
    }

    func loadForEditing() -> TxChatDictionaryDocument { document }
    func reload() -> TxChatDictionaryDocument { document }
    func save(
        _ entries: [TxChatDictionaryEntry]
    ) -> TxChatDictionaryDocument {
        self.entries = entries
        return document
    }
    func ensureFileExists() -> URL { fileURL }

    private var document: TxChatDictionaryDocument {
        TxChatDictionaryDocument(
            schemaVersion: TxChatDictionaryLimits.schemaVersion,
            entries: entries,
            skippedLineCount: 0
        )
    }
}
#endif
