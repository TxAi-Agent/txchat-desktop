import Foundation

enum TxChatDictionaryLimits {
    static let schemaVersion = 1
    static let maximumEntryCount = 1_000
    static let maximumFieldLength = 100
    static let maximumFileBytes = 1_048_576
}

struct TxChatDictionaryEntry: Equatable, Hashable, Sendable, Identifiable {
    var wrong: String
    var correct: String
    var isEnabled: Bool

    var id: String { wrong }

    init(wrong: String, correct: String, isEnabled: Bool = true) {
        self.wrong = wrong
        self.correct = correct
        self.isEnabled = isEnabled
    }

    var isValid: Bool {
        !wrong.isEmpty
            && !correct.isEmpty
            && wrong != correct
            && wrong.count <= TxChatDictionaryLimits.maximumFieldLength
            && correct.count <= TxChatDictionaryLimits.maximumFieldLength
            && !wrong.contains(where: { $0.isNewline })
            && !correct.contains(where: { $0.isNewline })
    }
}

struct TxChatDictionaryDocument: Equatable, Sendable {
    let schemaVersion: Int
    let entries: [TxChatDictionaryEntry]
    let skippedLineCount: Int

    static let empty = TxChatDictionaryDocument(
        schemaVersion: TxChatDictionaryLimits.schemaVersion,
        entries: [],
        skippedLineCount: 0
    )
}

enum DictionaryMarkdownError: Error, Equatable, Sendable {
    case oversizedFile
    case invalidUTF8
    case missingSchema
    case unsupportedSchema(Int)
    case invalidStructure
    case invalidEntry(index: Int)
    case duplicateWrong(index: Int)
    case tooManyEntries
    case encodingFailed
}
