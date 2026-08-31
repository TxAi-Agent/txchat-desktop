import Foundation

protocol DictionaryTextReplacing: Sendable {
    func replaceFinalText(_ text: String) async throws -> String
}

struct PassthroughDictionaryTextReplacer: DictionaryTextReplacing {
    func replaceFinalText(_ text: String) async throws -> String { text }
}

actor ProductDictionaryRuntime: DictionaryTextReplacing {
    nonisolated var fileURL: URL { store.fileURL }

    private let store: any DictionaryStoring
    private let diagnostics: any DictionaryDiagnosticRecording
    private var entries: [TxChatDictionaryEntry] = []
    private var replacer = DictionaryReplacer(entries: [])
    private var hasLoadedSnapshot = false

    init(
        store: any DictionaryStoring,
        diagnostics: any DictionaryDiagnosticRecording =
            DisabledDictionaryDiagnosticRecorder()
    ) {
        self.store = store
        self.diagnostics = diagnostics
    }

    func loadForEditing() async throws -> TxChatDictionaryDocument {
        try await loadAndActivate(stage: .load)
    }

    func reload() async throws -> TxChatDictionaryDocument {
        try await loadAndActivate(stage: .reload)
    }

    func save(
        _ entries: [TxChatDictionaryEntry]
    ) async throws -> TxChatDictionaryDocument {
        do {
            try await store.save(entries)
        } catch {
            await record(error, stage: .save)
            throw error
        }
        activate(entries)
        return TxChatDictionaryDocument(
            schemaVersion: TxChatDictionaryLimits.schemaVersion,
            entries: entries,
            skippedLineCount: 0
        )
    }

    func ensureFileExists() async throws -> URL {
        do {
            return try await store.ensureFileExists()
        } catch {
            await record(error, stage: .openFile)
            throw error
        }
    }

    func replaceFinalText(_ text: String) async throws -> String {
        if !hasLoadedSnapshot {
            _ = try await loadAndActivate(stage: .prepare)
        }
        return replacer.replace(text)
    }

    func currentEntries() -> [TxChatDictionaryEntry] {
        entries
    }

    private func loadAndActivate(
        stage: DictionaryDiagnosticStage
    ) async throws -> TxChatDictionaryDocument {
        let document: TxChatDictionaryDocument
        do {
            document = try await store.load()
        } catch {
            await record(error, stage: stage)
            throw error
        }
        activate(document.entries)
        if document.skippedLineCount > 0 {
            await diagnostics.record(
                DictionaryDiagnosticEvent(
                    stage: stage,
                    category: .partialRowsSkipped,
                    skippedLineCount: document.skippedLineCount,
                    schemaVersion: document.schemaVersion
                )
            )
        }
        return document
    }

    private func activate(_ entries: [TxChatDictionaryEntry]) {
        self.entries = entries
        replacer = DictionaryReplacer(entries: entries)
        hasLoadedSnapshot = true
    }

    private func record(
        _ error: Error,
        stage: DictionaryDiagnosticStage
    ) async {
        let metadata = Self.metadata(for: error)
        await diagnostics.record(
            DictionaryDiagnosticEvent(
                stage: stage,
                category: metadata.category,
                schemaVersion: metadata.schemaVersion
            )
        )
    }

    private nonisolated static func metadata(
        for error: Error
    ) -> (category: DictionaryDiagnosticCategory, schemaVersion: Int?) {
        if let error = error as? DictionaryStoreError {
            return switch error {
            case .readFailed: (.readFailed, nil)
            case .directoryCreationFailed: (.directoryCreationFailed, nil)
            case .writeFailed: (.writeFailed, nil)
            }
        }
        if let error = error as? DictionaryMarkdownError {
            return switch error {
            case .oversizedFile: (.oversizedFile, nil)
            case .invalidUTF8: (.invalidUTF8, nil)
            case .missingSchema: (.missingSchema, nil)
            case let .unsupportedSchema(version):
                (.unsupportedSchema, version)
            case .invalidStructure: (.invalidStructure, nil)
            case .invalidEntry, .duplicateWrong, .tooManyEntries,
                    .encodingFailed:
                (.validationFailed, nil)
            }
        }
        return (.unknown, nil)
    }
}
