import AppKit
import XCTest
@testable import SpekWrite

@MainActor
final class ProductShortcutEditorModelTests: XCTestCase {
    func testCaptureAndSuccessfulSavePromoteCandidateToCurrent() throws {
        let model = ProductShortcutEditorModel(current: .defaultFn)
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.option, .command]
        )

        XCTAssertEqual(model.state, .current)
        XCTAssertEqual(model.displayedShortcut, .defaultFn)

        model.beginCapture()
        XCTAssertEqual(model.state, .waiting)

        model.capture(candidate)
        XCTAssertEqual(model.state, .captured)
        XCTAssertEqual(model.displayedShortcut, candidate)

        let saved = model.save { shortcut in
            XCTAssertEqual(shortcut, candidate)
            return .updated
        }

        XCTAssertTrue(saved)
        XCTAssertEqual(model.state, .current)
        XCTAssertEqual(model.current, candidate)
        XCTAssertEqual(model.displayedShortcut, candidate)
    }

    func testRegistrationAndPersistenceFailuresKeepOriginalShortcut() throws {
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 40, displayName: "K"),
            modifiers: [.command]
        )
        let cases: [(ShortcutUpdateResult, ProductShortcutEditorState)] = [
            (.failed(.conflict), .conflict),
            (.failed(.unavailable), .unavailable),
            (.failed(.unsupported), .unsupported),
            (.saveFailed, .saveFailed),
        ]

        for (result, expectedState) in cases {
            let model = ProductShortcutEditorModel(current: .defaultFn)
            model.capture(candidate)

            XCTAssertFalse(model.save { _ in result })
            XCTAssertEqual(model.state, expectedState)
            XCTAssertEqual(model.current, .defaultFn)
            XCTAssertEqual(model.displayedShortcut, candidate)
        }
    }

    func testRightOptionIsVisibleButCannotBeSaved() throws {
        let model = ProductShortcutEditorModel(current: .defaultFn)
        let rightOption = try ProductShortcut(
            key: .rightOption,
            modifiers: []
        )
        var updateCalled = false

        model.capture(rightOption)

        XCTAssertEqual(model.state, .unsupported)
        XCTAssertEqual(model.displayedShortcut.displayName, "Right Option")
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.save { _ in
            updateCalled = true
            return .updated
        })
        XCTAssertFalse(updateCalled)
        XCTAssertEqual(model.current, .defaultFn)
    }

    func testRetryAndCancelHaveDeterministicState() throws {
        let model = ProductShortcutEditorModel(current: .defaultFn)
        let candidate = try ProductShortcut(
            key: .standard(keyCode: 49, displayName: "Space"),
            modifiers: [.control, .option, .shift, .command]
        )
        model.capture(candidate)
        _ = model.save { _ in .failed(.conflict) }

        model.beginCapture()
        XCTAssertEqual(model.state, .waiting)
        XCTAssertEqual(model.displayedShortcut, .defaultFn)

        model.capture(candidate)
        model.cancelCapture()
        XCTAssertEqual(model.state, .current)
        XCTAssertEqual(model.displayedShortcut, .defaultFn)
    }

    func testEventMapperCapturesFnRightOptionAndStandardCombination() throws {
        let fn = makeKeyEvent(
            type: .flagsChanged,
            keyCode: 63,
            modifiers: [.function]
        )
        let rightOption = makeKeyEvent(
            type: .flagsChanged,
            keyCode: 61,
            modifiers: [.option]
        )
        let commandK = makeKeyEvent(
            type: .keyDown,
            keyCode: 40,
            characters: "k",
            modifiers: [.command]
        )

        XCTAssertEqual(
            try ProductShortcutEventMapper.shortcut(from: fn),
            .defaultFn
        )
        XCTAssertEqual(
            try ProductShortcutEventMapper.shortcut(from: rightOption)?.key,
            .rightOption
        )
        XCTAssertEqual(
            try ProductShortcutEventMapper.shortcut(from: commandK)?
                .displayName,
            "Command + K"
        )
    }

    func testEventMapperIgnoresModifierReleaseAndRejectsUnsafeKeys() throws {
        let optionReleased = makeKeyEvent(
            type: .flagsChanged,
            keyCode: 58,
            modifiers: []
        )
        let bareK = makeKeyEvent(
            type: .keyDown,
            keyCode: 40,
            characters: "k",
            modifiers: []
        )
        let shiftA = makeKeyEvent(
            type: .keyDown,
            keyCode: 0,
            characters: "A",
            modifiers: [.shift]
        )

        XCTAssertNil(
            try ProductShortcutEventMapper.shortcut(from: optionReleased)
        )
        XCTAssertThrowsError(
            try ProductShortcutEventMapper.shortcut(from: bareK)
        ) { error in
            XCTAssertEqual(
                error as? ProductShortcut.ValidationError,
                .emptyModifiers
            )
        }
        XCTAssertThrowsError(
            try ProductShortcutEventMapper.shortcut(from: shiftA)
        ) { error in
            XCTAssertEqual(
                error as? ProductShortcut.ValidationError,
                .shiftOnly
            )
        }
        XCTAssertEqual(
            ProductShortcutEventMapper.displayName(from: shiftA),
            "Shift + A"
        )
    }

    func testRejectedCandidateCanBeDisplayedWithoutBecomingSavable() {
        let model = ProductShortcutEditorModel(current: .defaultFn)

        model.rejectCandidate(displayName: "Shift + A")

        XCTAssertEqual(model.state, .unavailable)
        XCTAssertEqual(model.displayedName, "Shift + A")
        XCTAssertFalse(model.canSave)

        model.beginCapture()
        XCTAssertEqual(model.displayedName, "Fn")
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
