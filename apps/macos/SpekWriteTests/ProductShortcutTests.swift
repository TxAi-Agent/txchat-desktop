import Foundation
import XCTest
@testable import SpekWrite

final class ProductShortcutTests: XCTestCase {
    func testDefaultShortcutIsStandaloneFunctionKey() {
        let shortcut = ProductShortcut.defaultFn

        XCTAssertEqual(shortcut.key, .function)
        XCTAssertEqual(shortcut.keyCode, 63)
        XCTAssertEqual(shortcut.modifiers, [])
        XCTAssertEqual(shortcut.displayName, "Fn")
    }

    func testStandaloneRightOptionPreservesItsSideInDisplayName() throws {
        let shortcut = try ProductShortcut(
            key: .rightOption,
            modifiers: []
        )

        XCTAssertEqual(shortcut.keyCode, 61)
        XCTAssertEqual(shortcut.displayName, "Right Option")
    }

    func testLongCombinationUsesStableModifierOrder() throws {
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.shift, .command, .control, .option]
        )

        XCTAssertEqual(
            shortcut.modifiers,
            [.control, .option, .shift, .command]
        )
        XCTAssertEqual(
            shortcut.displayName,
            "Control + Option + Shift + Command + K"
        )
    }

    func testCodableRoundTripPreservesShortcutIdentity() throws {
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command, .option]
        )

        let encoded = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(
            ProductShortcut.self,
            from: encoded
        )

        XCTAssertEqual(decoded, shortcut)
    }

    func testRejectsUnsafeOrAmbiguousShortcutShapes() {
        assertValidationError(.emptyModifiers) {
            try ProductShortcut(
                key: .standard(keyCode: 0, displayName: "A"),
                modifiers: []
            )
        }
        assertValidationError(.shiftOnly) {
            try ProductShortcut(
                key: .standard(keyCode: 0, displayName: "A"),
                modifiers: [.shift]
            )
        }
        assertValidationError(.functionKeyCombination) {
            try ProductShortcut(
                key: .standard(keyCode: 0, displayName: "A"),
                modifiers: [.command, .function]
            )
        }
        assertValidationError(.duplicateModifiers) {
            try ProductShortcut(
                key: .standard(keyCode: 0, displayName: "A"),
                modifiers: [.command, .command]
            )
        }
    }

    func testAllowsPrimaryKeyWithSafeModifier() throws {
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 0, displayName: "A"),
            modifiers: [.command]
        )

        XCTAssertEqual(shortcut.displayName, "Command + A")
    }

    func testStoreRestoresValidShortcut() throws {
        let defaults = makeUserDefaults()
        let store = UserDefaultsShortcutStore(
            userDefaults: defaults,
            key: "shortcut"
        )
        let shortcut = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.option, .command]
        )

        XCTAssertTrue(store.saveShortcut(shortcut))

        XCTAssertEqual(store.loadShortcut(), shortcut)
    }

    func testStoreFallsBackToFnForMissingOrCorruptValue() {
        let defaults = makeUserDefaults()
        let store = UserDefaultsShortcutStore(
            userDefaults: defaults,
            key: "shortcut"
        )

        XCTAssertEqual(store.loadShortcut(), .defaultFn)

        defaults.set(Data("not-json".utf8), forKey: "shortcut")

        XCTAssertEqual(store.loadShortcut(), .defaultFn)
    }

    func testDictationModeStoreDefaultsToSmartAndRestoresLastSelection() {
        let defaults = makeUserDefaults()
        let store = UserDefaultsDictationModeStore(
            userDefaults: defaults,
            key: "dictation-mode"
        )

        XCTAssertEqual(store.loadMode(), .smart)

        defaults.set("unknown", forKey: "dictation-mode")
        XCTAssertEqual(store.loadMode(), .smart)

        XCTAssertTrue(store.saveMode(.verbatim))
        XCTAssertEqual(store.loadMode(), .verbatim)
    }

    private func assertValidationError(
        _ expected: ProductShortcut.ValidationError,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try operation(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? ProductShortcut.ValidationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ProductShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
