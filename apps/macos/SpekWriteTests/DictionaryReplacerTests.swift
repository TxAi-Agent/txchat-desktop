import XCTest
@testable import SpekWrite

final class DictionaryReplacerTests: XCTestCase {
    func testReplacesOnlyEnabledExactMatches() {
        let replacer = DictionaryReplacer(entries: [
            .init(wrong: "Txchat", correct: "TxChat", isEnabled: true),
            .init(wrong: "disabled", correct: "changed", isEnabled: false),
            .init(wrong: "abc", correct: "ABC", isEnabled: true),
            .init(wrong: "ＡＢＣ", correct: "full-width", isEnabled: true),
            .init(wrong: "即时通讯", correct: "即时通信", isEnabled: true),
        ])

        XCTAssertEqual(
            replacer.replace("Txchat txchat disabled abc ＡＢＣ 即时通讯。"),
            "TxChat txchat disabled ABC full-width 即时通信。"
        )
        XCTAssertEqual(replacer.replace(" abc\tabc\nabc "), " ABC\tABC\nABC ")
    }

    func testLongestMatchWinsAtEachOriginalPosition() {
        let entries = [
            TxChatDictionaryEntry(wrong: "听见", correct: "short"),
            TxChatDictionaryEntry(wrong: "听见单", correct: "long"),
            TxChatDictionaryEntry(wrong: "见单", correct: "suffix"),
        ]

        XCTAssertEqual(
            DictionaryReplacer(entries: entries).replace("听见单听见"),
            "longshort"
        )
        XCTAssertEqual(
            DictionaryReplacer(entries: entries.reversed()).replace("听见单听见"),
            "longshort"
        )
    }

    func testReplacementOutputIsNeverRescannedInSameCall() {
        let replacer = DictionaryReplacer(entries: [
            .init(wrong: "a", correct: "b"),
            .init(wrong: "b", correct: "c"),
        ])

        XCTAssertEqual(replacer.replace("a b"), "b c")
    }

    func testMatchingIsUnicodeScalarExactAndHandlesGraphemeClusters() {
        let composed = "é"
        let decomposed = "e\u{301}"
        let replacer = DictionaryReplacer(entries: [
            .init(wrong: composed, correct: "COMPOSED"),
            .init(wrong: "👨‍👩‍👧‍👦", correct: "family"),
            .init(wrong: "，", correct: ","),
        ])

        XCTAssertEqual(
            Array(replacer.replace(decomposed).utf8),
            Array(decomposed.utf8)
        )
        XCTAssertEqual(
            replacer.replace("é👨‍👩‍👧‍👦，"),
            "COMPOSEDfamily,"
        )
    }

    func testNoMatchAndEmptyDictionaryPreserveOriginalScalars() {
        let original = "原文 TxChat 👩🏽‍💻\n"

        XCTAssertEqual(DictionaryReplacer(entries: []).replace(original), original)
        XCTAssertEqual(
            DictionaryReplacer(entries: [
                .init(wrong: "missing", correct: "unused"),
            ]).replace(original),
            original
        )
    }

    func testRepeatedApplicationIsStableForNonconflictingCorrections() {
        let replacer = DictionaryReplacer(entries: [
            .init(wrong: "Txchat", correct: "TxChat"),
            .init(wrong: "即时通讯", correct: "即时通信"),
        ])
        let once = replacer.replace("Txchat 提供即时通讯。")

        XCTAssertEqual(replacer.replace(once), once)
    }

    func testOneThousandRulesProcessRepresentativeLongTextPromptly() {
        let entries = (0..<1_000).map {
            TxChatDictionaryEntry(
                wrong: "incorrect-term-\($0)",
                correct: "correct-term-\($0)"
            )
        }
        let replacer = DictionaryReplacer(entries: entries)
        let input = Array(
            repeating: "incorrect-term-999 filler incorrect-term-500。",
            count: 1_000
        ).joined(separator: " ")
        let clock = ContinuousClock()

        let start = clock.now
        let output = replacer.replace(input)
        let elapsed = start.duration(to: clock.now)

        XCTAssertTrue(output.contains("correct-term-999"))
        XCTAssertTrue(output.contains("correct-term-500"))
        XCTAssertFalse(output.contains("incorrect-term-"))
        XCTAssertLessThan(elapsed, .seconds(2))
    }
}
