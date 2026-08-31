import Foundation
import XCTest
@testable import SpekWrite

@MainActor
final class DictionarySettingsCoordinatorTests: XCTestCase {
    func testLoadAppliesDocumentAndShowsWeakPartialSuccessNotice() async {
        let service = DictionarySettingsServiceStub(
            document: document(
                [.init(wrong: "old", correct: "new")],
                skipped: 2
            )
        )
        let coordinator = DictionarySettingsCoordinator(service: service)

        await coordinator.load()

        XCTAssertEqual(
            coordinator.entries,
            [.init(wrong: "old", correct: "new")]
        )
        XCTAssertEqual(coordinator.notice, .partialReload(skippedLineCount: 2))
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertFalse(coordinator.isDirty)
    }

    func testAddValidEntryAtTopAndRejectDuplicateInline() async {
        let coordinator = makeLoadedCoordinator(entries: [
            .init(wrong: "existing", correct: "已有"),
        ])
        await coordinator.load()

        coordinator.presentAddEditor()
        coordinator.updateEditorWrong("existing")
        coordinator.updateEditorCorrect("duplicate")
        coordinator.confirmEditor()

        XCTAssertEqual(coordinator.editor?.validationError, .duplicateWrong)
        XCTAssertEqual(coordinator.entries.count, 1)

        coordinator.updateEditorWrong("new")
        coordinator.updateEditorCorrect("新增")
        coordinator.confirmEditor()

        XCTAssertNil(coordinator.editor)
        XCTAssertEqual(coordinator.entries.map(\.wrong), ["new", "existing"])
        XCTAssertTrue(coordinator.isDirty)
    }

    func testUnchangedTextFieldWritebackPreservesInlineValidation() async {
        let coordinator = makeLoadedCoordinator(entries: [
            .init(wrong: "existing", correct: "已有"),
        ])
        await coordinator.load()
        coordinator.presentAddEditor()
        coordinator.updateEditorWrong("existing")
        coordinator.updateEditorCorrect("duplicate")
        coordinator.confirmEditor()

        coordinator.updateEditorWrong("existing")
        coordinator.updateEditorCorrect("duplicate")

        XCTAssertEqual(coordinator.editor?.validationError, .duplicateWrong)
    }

    func testEditorValidatesEmptyEqualAndOneHundredCharacterLimit() async {
        let coordinator = makeLoadedCoordinator(entries: [])
        await coordinator.load()
        coordinator.presentAddEditor()

        coordinator.confirmEditor()
        XCTAssertEqual(coordinator.editor?.validationError, .wrongEmpty)
        coordinator.updateEditorWrong("same")
        coordinator.confirmEditor()
        XCTAssertEqual(coordinator.editor?.validationError, .correctEmpty)
        coordinator.updateEditorCorrect("same")
        coordinator.confirmEditor()
        XCTAssertEqual(coordinator.editor?.validationError, .valuesEqual)
        coordinator.updateEditorWrong(String(repeating: "a", count: 101))
        coordinator.updateEditorCorrect("valid")
        coordinator.confirmEditor()
        XCTAssertEqual(coordinator.editor?.validationError, .fieldTooLong)
    }

    func testEditUpdatesInPlaceAndSupportsTwoStepDeletion() async {
        let coordinator = makeLoadedCoordinator(entries: [
            .init(wrong: "one", correct: "一"),
            .init(wrong: "two", correct: "二"),
        ])
        await coordinator.load()
        coordinator.presentEditEditor(at: 1)
        coordinator.updateEditorCorrect("贰")
        coordinator.confirmEditor()
        XCTAssertEqual(coordinator.entries[1].correct, "贰")

        coordinator.presentEditEditor(at: 0)
        coordinator.requestEditorDeletion()
        XCTAssertEqual(coordinator.editor?.isDeleteConfirmationPresented, true)
        coordinator.confirmEditorDeletion()

        XCTAssertNil(coordinator.editor)
        XCTAssertEqual(coordinator.entries.map(\.wrong), ["two"])
    }

    func testCardDeletionRequiresConfirmationAndToggleIsDraftOnly() async {
        let coordinator = makeLoadedCoordinator(entries: [
            .init(wrong: "one", correct: "一"),
        ])
        await coordinator.load()

        coordinator.setEnabled(false, at: 0)
        coordinator.requestCardDeletion(at: 0)
        XCTAssertEqual(coordinator.pendingCardDeletionIndex, 0)
        coordinator.cancelCardDeletion()
        XCTAssertEqual(coordinator.entries[0].isEnabled, false)
        XCTAssertNil(coordinator.pendingCardDeletionIndex)

        coordinator.requestCardDeletion(at: 0)
        coordinator.confirmCardDeletion()
        XCTAssertTrue(coordinator.entries.isEmpty)
    }

    func testCancelRestoresLastPersistedDraftAndCloses() async {
        let coordinator = makeLoadedCoordinator(entries: [
            .init(wrong: "saved", correct: "已保存"),
        ])
        var closeCount = 0
        coordinator.setCloseHandler { closeCount += 1 }
        await coordinator.load()
        coordinator.presentAddEditor()
        coordinator.updateEditorWrong("draft")
        coordinator.updateEditorCorrect("草稿")
        coordinator.confirmEditor()

        coordinator.cancel()

        XCTAssertEqual(coordinator.entries.map(\.wrong), ["saved"])
        XCTAssertFalse(coordinator.isDirty)
        XCTAssertEqual(closeCount, 1)
    }

    func testSavePersistsDraftUpdatesBaselineAndCloses() async {
        let service = DictionarySettingsServiceStub(document: .empty)
        let coordinator = DictionarySettingsCoordinator(service: service)
        var closeCount = 0
        coordinator.setCloseHandler { closeCount += 1 }
        await coordinator.load()
        coordinator.presentAddEditor()
        coordinator.updateEditorWrong("draft")
        coordinator.updateEditorCorrect("saved")
        coordinator.confirmEditor()

        await coordinator.save()

        let saved = await service.savedEntries
        XCTAssertEqual(saved, [[.init(wrong: "draft", correct: "saved")]])
        XCTAssertFalse(coordinator.isDirty)
        XCTAssertEqual(closeCount, 1)
    }

    func testReloadReplacesDraftWithExternalDocument() async {
        let service = DictionarySettingsServiceStub(document: document([
            .init(wrong: "initial", correct: "初始"),
        ]))
        let coordinator = DictionarySettingsCoordinator(service: service)
        await coordinator.load()
        coordinator.setEnabled(false, at: 0)
        await service.setDocument(document([
            .init(wrong: "external", correct: "外部"),
        ]))

        await coordinator.reload()

        XCTAssertEqual(coordinator.entries.map(\.wrong), ["external"])
        XCTAssertFalse(coordinator.isDirty)
    }

    func testOpenFileEnsuresTemplateThenRevealsExactFile() async {
        let service = DictionarySettingsServiceStub(document: .empty)
        let revealer = DictionaryFileRevealerSpy()
        let coordinator = DictionarySettingsCoordinator(
            service: service,
            fileRevealer: revealer
        )

        await coordinator.openFile()

        let ensureCallCount = await service.ensureCallCount
        XCTAssertEqual(ensureCallCount, 1)
        XCTAssertEqual(revealer.revealedURLs, [service.fileURL])
    }

    func testLoadReloadSaveAndOpenFailuresRemainRecoverable() async {
        let service = DictionarySettingsServiceStub(document: .empty)
        let coordinator = DictionarySettingsCoordinator(service: service)
        await service.setLoadError(DictionaryStoreError.readFailed)
        await coordinator.load()
        XCTAssertEqual(coordinator.notice, .loadFailed)

        await coordinator.reload()
        XCTAssertEqual(coordinator.notice, .reloadFailed)
        await service.setLoadError(nil)
        await coordinator.load()
        coordinator.presentAddEditor()
        coordinator.updateEditorWrong("draft")
        coordinator.updateEditorCorrect("value")
        coordinator.confirmEditor()
        await service.setSaveError(DictionaryStoreError.writeFailed)
        await coordinator.save()
        XCTAssertEqual(coordinator.notice, .saveFailed)
        XCTAssertTrue(coordinator.isDirty)
        await service.setEnsureError(DictionaryStoreError.writeFailed)
        await coordinator.openFile()
        XCTAssertEqual(coordinator.notice, .openFileFailed)
    }

    private func makeLoadedCoordinator(
        entries: [TxChatDictionaryEntry]
    ) -> DictionarySettingsCoordinator {
        DictionarySettingsCoordinator(
            service: DictionarySettingsServiceStub(
                document: document(entries)
            )
        )
    }

    private func document(
        _ entries: [TxChatDictionaryEntry],
        skipped: Int = 0
    ) -> TxChatDictionaryDocument {
        TxChatDictionaryDocument(
            schemaVersion: 1,
            entries: entries,
            skippedLineCount: skipped
        )
    }
}

private actor DictionarySettingsServiceStub: DictionarySettingsServicing {
    nonisolated let fileURL = URL(fileURLWithPath: "/test/TxChat-Dictionary.md")
    private var document: TxChatDictionaryDocument
    private var loadError: Error?
    private var saveError: Error?
    private var ensureError: Error?
    private(set) var savedEntries: [[TxChatDictionaryEntry]] = []
    private(set) var ensureCallCount = 0

    init(document: TxChatDictionaryDocument) {
        self.document = document
    }

    func loadForEditing() throws -> TxChatDictionaryDocument {
        if let loadError { throw loadError }
        return document
    }

    func reload() throws -> TxChatDictionaryDocument {
        if let loadError { throw loadError }
        return document
    }

    func save(
        _ entries: [TxChatDictionaryEntry]
    ) throws -> TxChatDictionaryDocument {
        if let saveError { throw saveError }
        savedEntries.append(entries)
        document = TxChatDictionaryDocument(
            schemaVersion: 1,
            entries: entries,
            skippedLineCount: 0
        )
        return document
    }

    func ensureFileExists() throws -> URL {
        ensureCallCount += 1
        if let ensureError { throw ensureError }
        return fileURL
    }

    func setDocument(_ document: TxChatDictionaryDocument) {
        self.document = document
    }

    func setLoadError(_ error: Error?) { loadError = error }
    func setSaveError(_ error: Error?) { saveError = error }
    func setEnsureError(_ error: Error?) { ensureError = error }
}

@MainActor
private final class DictionaryFileRevealerSpy: DictionaryFileRevealing {
    private(set) var revealedURLs: [URL] = []

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}
