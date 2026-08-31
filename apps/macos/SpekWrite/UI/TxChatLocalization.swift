import SwiftUI

enum TxChatLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let productDefault: TxChatLanguage = .simplifiedChinese

    static var system: TxChatLanguage {
        let identifier = Locale.current.identifier.lowercased()
        return identifier.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    init?(visualValue: String?) {
        switch visualValue?.lowercased() {
        case "zh", "zh-hans", "chinese": self = .simplifiedChinese
        case "en", "english": self = .english
        default: return nil
        }
    }

    func select(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }
}

enum TxChatAccountDisplay {
    static func maskedPhone(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let phone = try? MainlandPhone(trimmed) {
            return phone.maskedDisplayPhone
        }
        guard trimmed.hasPrefix("+86") else { return trimmed }
        return String(trimmed.dropFirst(3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TxChatLanguageKey: EnvironmentKey {
    static let defaultValue = TxChatLanguage.productDefault
}

extension EnvironmentValues {
    var txChatLanguage: TxChatLanguage {
        get { self[TxChatLanguageKey.self] }
        set { self[TxChatLanguageKey.self] = newValue }
    }
}

extension View {
    func txChatLanguage(_ language: TxChatLanguage) -> some View {
        environment(\.txChatLanguage, language)
            .environment(\.locale, Locale(identifier: language.rawValue))
    }
}
