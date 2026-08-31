import OSLog

enum DictionaryDiagnosticStage: String, Equatable, Sendable {
    case load
    case reload
    case save
    case prepare
    case openFile
}

enum DictionaryDiagnosticCategory: String, Equatable, Sendable {
    case partialRowsSkipped
    case readFailed
    case directoryCreationFailed
    case writeFailed
    case oversizedFile
    case invalidUTF8
    case missingSchema
    case unsupportedSchema
    case invalidStructure
    case validationFailed
    case unknown
}

struct DictionaryDiagnosticEvent: Equatable, Sendable {
    let stage: DictionaryDiagnosticStage
    let category: DictionaryDiagnosticCategory
    let skippedLineCount: Int?
    let schemaVersion: Int?

    init(
        stage: DictionaryDiagnosticStage,
        category: DictionaryDiagnosticCategory,
        skippedLineCount: Int? = nil,
        schemaVersion: Int? = nil
    ) {
        self.stage = stage
        self.category = category
        self.skippedLineCount = skippedLineCount
        self.schemaVersion = schemaVersion
    }
}

protocol DictionaryDiagnosticRecording: Sendable {
    func record(_ event: DictionaryDiagnosticEvent) async
}

struct DisabledDictionaryDiagnosticRecorder: DictionaryDiagnosticRecording {
    func record(_ event: DictionaryDiagnosticEvent) async {
        _ = event
    }
}

struct SystemDictionaryDiagnosticRecorder: DictionaryDiagnosticRecording {
    private let logger = Logger(
        subsystem: "org.example.txchat",
        category: "dictionary"
    )

    func record(_ event: DictionaryDiagnosticEvent) async {
        let skippedLineCount = event.skippedLineCount.map(String.init) ?? "none"
        let schemaVersion = event.schemaVersion.map(String.init) ?? "none"
        logger.error(
            "stage=\(event.stage.rawValue, privacy: .public) category=\(event.category.rawValue, privacy: .public) skipped=\(skippedLineCount, privacy: .public) schema=\(schemaVersion, privacy: .public)"
        )
    }
}
