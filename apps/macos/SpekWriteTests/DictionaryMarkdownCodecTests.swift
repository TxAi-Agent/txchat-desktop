import XCTest
@testable import SpekWrite

final class DictionaryMarkdownCodecTests: XCTestCase {
    private let codec = DictionaryMarkdownCodec()

    func testDecodesValidUTF8RowsAndPreservesSourceOrder() throws {
        let data = Data(
            """
            <!-- txchat-dictionary-schema: 1 -->

            | wrong | correct | enabled |
            | --- | --- | --- |
            | Txchat | TxChat | true |
            | 即时通讯 | 即时通信 | false |
            | full\\|width | full-width | true |
            """.utf8
        )

        let document = try codec.decode(data)

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.skippedLineCount, 0)
        XCTAssertEqual(
            document.entries,
            [
                .init(wrong: "Txchat", correct: "TxChat", isEnabled: true),
                .init(wrong: "即时通讯", correct: "即时通信", isEnabled: false),
                .init(wrong: "full|width", correct: "full-width", isEnabled: true),
            ]
        )
    }

    func testSkipsInvalidRowsAndKeepsFirstValidDuplicate() throws {
        let overlong = String(repeating: "字", count: 101)
        let data = Data(
            """
            <!-- txchat-dictionary-schema: 1 -->
            | wrong | correct | enabled |
            | --- | --- | --- |
            | first | corrected | true |
            | first | later | true |
            |  | empty | true |
            | same | same | true |
            | malformed | columns |
            | malformed-bool | corrected | yes |
            | \(overlong) | corrected | true |
            | final | 最终 | false |
            """.utf8
        )

        let document = try codec.decode(data)

        XCTAssertEqual(
            document.entries,
            [
                .init(wrong: "first", correct: "corrected", isEnabled: true),
                .init(wrong: "final", correct: "最终", isEnabled: false),
            ]
        )
        XCTAssertEqual(document.skippedLineCount, 6)
    }

    func testCapsValidEntriesAtOneThousandAndCountsOverflowAsSkipped() throws {
        let rows = (0..<1_002).map { "| wrong-\($0) | correct-\($0) | true |" }
        let markdown = ([
            "<!-- txchat-dictionary-schema: 1 -->",
            "| wrong | correct | enabled |",
            "| --- | --- | --- |",
        ] + rows).joined(separator: "\n")

        let document = try codec.decode(Data(markdown.utf8))

        XCTAssertEqual(document.entries.count, 1_000)
        XCTAssertEqual(document.entries.first?.wrong, "wrong-0")
        XCTAssertEqual(document.entries.last?.wrong, "wrong-999")
        XCTAssertEqual(document.skippedLineCount, 2)
    }

    func testRejectsMissingUnsupportedSchemaInvalidUTF8AndOversizedData() {
        XCTAssertThrowsError(
            try codec.decode(Data("| wrong | correct | enabled |".utf8))
        ) { error in
            XCTAssertEqual(error as? DictionaryMarkdownError, .missingSchema)
        }
        XCTAssertThrowsError(
            try codec.decode(
                Data("<!-- txchat-dictionary-schema: 2 -->".utf8)
            )
        ) { error in
            XCTAssertEqual(
                error as? DictionaryMarkdownError,
                .unsupportedSchema(2)
            )
        }
        XCTAssertThrowsError(try codec.decode(Data([0xFF, 0xFE]))) { error in
            XCTAssertEqual(error as? DictionaryMarkdownError, .invalidUTF8)
        }
        XCTAssertThrowsError(
            try codec.decode(Data(repeating: 0x61, count: 1_048_577))
        ) { error in
            XCTAssertEqual(error as? DictionaryMarkdownError, .oversizedFile)
        }
    }

    func testEncodesStableTemplateAndRoundTripsEscapedAndSpacedContent() throws {
        XCTAssertEqual(
            String(decoding: try codec.encode([]), as: UTF8.self),
            """
            <!-- txchat-dictionary-schema: 1 -->

            | wrong | correct | enabled |
            | --- | --- | --- |

            """
        )

        let entries = [
            TxChatDictionaryEntry(
                wrong: #"a\b|c"#,
                correct: #"x|y\z"#,
                isEnabled: true
            ),
            TxChatDictionaryEntry(
                wrong: " leading and trailing ",
                correct: "  exact replacement  ",
                isEnabled: false
            ),
        ]
        let encoded = try codec.encode(entries)
        let decoded = try codec.decode(encoded)

        XCTAssertEqual(decoded.entries, entries)
        XCTAssertEqual(decoded.skippedLineCount, 0)
    }

    func testEncodingRejectsInvalidAndDuplicateEntries() {
        XCTAssertThrowsError(
            try codec.encode([
                .init(wrong: "same", correct: "same", isEnabled: true),
            ])
        ) { error in
            XCTAssertEqual(
                error as? DictionaryMarkdownError,
                .invalidEntry(index: 0)
            )
        }
        XCTAssertThrowsError(
            try codec.encode([
                .init(wrong: "one", correct: "first", isEnabled: true),
                .init(wrong: "one", correct: "second", isEnabled: false),
            ])
        ) { error in
            XCTAssertEqual(
                error as? DictionaryMarkdownError,
                .duplicateWrong(index: 1)
            )
        }
    }
}
