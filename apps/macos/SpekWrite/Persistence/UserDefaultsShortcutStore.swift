import CryptoKit
import Foundation

protocol OnboardingCompletionStoring: AnyObject {
    func isCompleted(for account: AccountSummary) -> Bool
    @discardableResult
    func markCompleted(for account: AccountSummary) -> Bool
}

final class UserDefaultsOnboardingCompletionStore:
    OnboardingCompletionStoring
{
    static let defaultKey = "com.txchat.product.completed-onboarding-accounts"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = UserDefaultsOnboardingCompletionStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func isCompleted(for account: AccountSummary) -> Bool {
        guard let accountKey = Self.accountKey(for: account) else {
            return false
        }
        return Set(userDefaults.stringArray(forKey: key) ?? [])
            .contains(accountKey)
    }

    @discardableResult
    func markCompleted(for account: AccountSummary) -> Bool {
        guard let accountKey = Self.accountKey(for: account) else {
            return false
        }
        let previousValue = userDefaults.object(forKey: key)
        var completed = Set(userDefaults.stringArray(forKey: key) ?? [])
        completed.insert(accountKey)
        userDefaults.set(completed.sorted(), forKey: key)
        guard Set(userDefaults.stringArray(forKey: key) ?? [])
            .contains(accountKey) else {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            return false
        }
        return true
    }

    private static func accountKey(
        for account: AccountSummary
    ) -> String? {
        var canonical = account.maskedPhone.filter {
            $0.isNumber || $0 == "*"
        }
        if canonical.hasPrefix("86"), canonical.contains("*") {
            canonical.removeFirst(2)
        }
        guard !canonical.isEmpty else {
            return nil
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

protocol ShortcutPreferenceStoring {
    func loadShortcut() -> ProductShortcut
    @discardableResult
    func saveShortcut(_ shortcut: ProductShortcut) -> Bool
}

protocol DictationModePreferenceStoring {
    func loadMode() -> DictationMode
    @discardableResult
    func saveMode(_ mode: DictationMode) -> Bool
}

final class UserDefaultsDictationModeStore: DictationModePreferenceStoring {
    static let defaultKey = "com.txchat.product.dictation-mode"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = UserDefaultsDictationModeStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadMode() -> DictationMode {
        guard let rawValue = userDefaults.string(forKey: key),
              let mode = DictationMode(rawValue: rawValue) else {
            return .smart
        }
        return mode
    }

    @discardableResult
    func saveMode(_ mode: DictationMode) -> Bool {
        let previousValue = userDefaults.object(forKey: key)
        userDefaults.set(mode.rawValue, forKey: key)
        guard userDefaults.string(forKey: key) == mode.rawValue else {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            return false
        }
        return true
    }
}

final class UserDefaultsShortcutStore: ShortcutPreferenceStoring {
    static let defaultKey = "org.example.txchat.product.shortcut"

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = UserDefaultsShortcutStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadShortcut() -> ProductShortcut {
        guard
            let data = userDefaults.data(forKey: key),
            let shortcut = try? JSONDecoder().decode(
                ProductShortcut.self,
                from: data
            )
        else {
            return .defaultFn
        }

        return shortcut
    }

    @discardableResult
    func saveShortcut(_ shortcut: ProductShortcut) -> Bool {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return false
        }
        let previousValue = userDefaults.object(forKey: key)
        userDefaults.set(data, forKey: key)
        guard userDefaults.data(forKey: key) == data else {
            if let previousValue {
                userDefaults.set(previousValue, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
            return false
        }
        return true
    }
}
