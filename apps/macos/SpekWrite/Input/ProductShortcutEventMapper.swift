import AppKit
import Foundation

enum ProductShortcutEventMapper {
    static func displayName(from event: NSEvent) -> String {
        if event.type == .flagsChanged {
            if event.keyCode == 63 {
                return "Fn"
            }
            if event.keyCode == 61 {
                return "Right Option"
            }
        }

        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Command") }
        if flags.contains(.function) { parts.append("Fn") }
        let key = keyDisplayName(for: event)
        if !key.isEmpty { parts.append(key) }
        return parts.joined(separator: " + ")
    }

    static func shortcut(from event: NSEvent) throws -> ProductShortcut? {
        guard event.type != .keyDown || !event.isARepeat else {
            return nil
        }

        if event.type == .flagsChanged {
            if event.keyCode == 63,
               event.modifierFlags.contains(.function) {
                return .defaultFn
            }
            if event.keyCode == 61,
               event.modifierFlags.contains(.option) {
                return try ProductShortcut(
                    key: .rightOption,
                    modifiers: []
                )
            }
            return nil
        }

        guard event.type == .keyDown else {
            return nil
        }
        let displayName = keyDisplayName(for: event)
        guard !displayName.isEmpty else {
            return nil
        }
        return try ProductShortcut(
            key: .standard(
                keyCode: event.keyCode,
                displayName: displayName
            ),
            modifiers: modifiers(from: event.modifierFlags)
        )
    }

    private static func modifiers(
        from flags: NSEvent.ModifierFlags
    ) -> [ProductShortcut.Modifier] {
        var result: [ProductShortcut.Modifier] = []
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.command) { result.append(.command) }
        if flags.contains(.function) { result.append(.function) }
        return result
    }

    private static func keyDisplayName(for event: NSEvent) -> String {
        if let specialName = specialKeyNames[event.keyCode] {
            return specialName
        }
        return (event.charactersIgnoringModifiers ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        119: "End",
        121: "Page Down",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]
}
