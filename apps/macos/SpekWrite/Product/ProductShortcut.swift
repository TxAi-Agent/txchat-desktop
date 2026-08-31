import Foundation

struct ProductShortcut: Codable, Equatable, Sendable {
    enum Key: Codable, Equatable, Sendable {
        case function
        case rightOption
        case standard(keyCode: UInt16, displayName: String)

        var keyCode: UInt16 {
            switch self {
            case .function:
                63
            case .rightOption:
                61
            case let .standard(keyCode, _):
                keyCode
            }
        }

        fileprivate var displayName: String {
            switch self {
            case .function:
                "Fn"
            case .rightOption:
                "Right Option"
            case let .standard(_, displayName):
                displayName
            }
        }
    }

    enum Modifier: String, Codable, CaseIterable, Equatable, Sendable {
        case control
        case option
        case shift
        case command
        case function

        fileprivate var displayName: String {
            switch self {
            case .control:
                "Control"
            case .option:
                "Option"
            case .shift:
                "Shift"
            case .command:
                "Command"
            case .function:
                "Fn"
            }
        }

        fileprivate var stableOrder: Int {
            switch self {
            case .control:
                0
            case .option:
                1
            case .shift:
                2
            case .command:
                3
            case .function:
                4
            }
        }
    }

    enum ValidationError: Error, Equatable, Sendable {
        case emptyModifiers
        case duplicateModifiers
        case shiftOnly
        case functionKeyCombination
        case standaloneModifierCombination
        case emptyKeyDisplayName
    }

    static let defaultFn = ProductShortcut(
        validatedKey: .function,
        modifiers: []
    )

    let key: Key
    let modifiers: [Modifier]

    var keyCode: UInt16 {
        key.keyCode
    }

    var displayName: String {
        switch key {
        case .function, .rightOption:
            key.displayName
        case .standard:
            (modifiers.map(\.displayName) + [key.displayName])
                .joined(separator: " + ")
        }
    }

    init(key: Key, modifiers: [Modifier]) throws {
        guard Set(modifiers).count == modifiers.count else {
            throw ValidationError.duplicateModifiers
        }

        switch key {
        case .function:
            guard modifiers.isEmpty else {
                throw ValidationError.functionKeyCombination
            }
            self.init(validatedKey: key, modifiers: [])

        case .rightOption:
            guard modifiers.isEmpty else {
                throw ValidationError.standaloneModifierCombination
            }
            self.init(validatedKey: key, modifiers: [])

        case let .standard(keyCode, displayName):
            let normalizedDisplayName = displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedDisplayName.isEmpty else {
                throw ValidationError.emptyKeyDisplayName
            }
            guard !modifiers.isEmpty else {
                throw ValidationError.emptyModifiers
            }
            guard !modifiers.contains(.function) else {
                throw ValidationError.functionKeyCombination
            }
            guard modifiers != [.shift] else {
                throw ValidationError.shiftOnly
            }

            self.init(
                validatedKey: .standard(
                    keyCode: keyCode,
                    displayName: normalizedDisplayName
                ),
                modifiers: modifiers.sorted {
                    $0.stableOrder < $1.stableOrder
                }
            )
        }
    }

    private init(validatedKey: Key, modifiers: [Modifier]) {
        key = validatedKey
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(Key.self, forKey: .key),
            modifiers: container.decode([Modifier].self, forKey: .modifiers)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
}

enum ShortcutUpdateResult: Equatable, Sendable {
    case updated
    case failed(ShortcutRegistrationFailure)
    case saveFailed
}
