import Foundation
import Security

protocol CustomAISecretStoring: Sendable {
    func load(_ reference: CustomAISecretReference) async throws -> String?
    func replace(
        _ value: String,
        for reference: CustomAISecretReference
    ) async throws
    func delete(_ reference: CustomAISecretReference) async throws
}

actor CustomAIKeychainSecretStore: CustomAISecretStoring {
    struct Error: Swift.Error, Equatable, Sendable {
        let status: OSStatus
    }

    static let service = "org.example.txchat.custom-ai"

    func load(_ reference: CustomAISecretReference) async throws -> String? {
        var query = Self.baseQuery(for: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count <= 16_384,
              let value = String(data: data, encoding: .utf8),
              Self.isValidSecret(value) else {
            if status != errSecSuccess {
                throw Error(status: status)
            }
            throw Error(status: errSecDecode)
        }
        return value
    }

    func replace(
        _ value: String,
        for reference: CustomAISecretReference
    ) async throws {
        guard Self.isValidSecret(value) else {
            throw Error(status: errSecParam)
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            Self.baseQuery(for: reference) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw Error(status: updateStatus)
        }
        let addStatus = SecItemAdd(
            Self.additionQuery(for: reference, value: data) as CFDictionary,
            nil
        )
        guard addStatus == errSecSuccess else {
            throw Error(status: addStatus)
        }
    }

    func delete(_ reference: CustomAISecretReference) async throws {
        let status = SecItemDelete(
            Self.baseQuery(for: reference) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error(status: status)
        }
    }

    static func baseQuery(
        for reference: CustomAISecretReference,
        service: String = service
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func additionQuery(
        for reference: CustomAISecretReference,
        value: Data,
        service: String = service
    ) -> [String: Any] {
        var query = baseQuery(for: reference, service: service)
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return query
    }

    private static func isValidSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed &&
            !value.isEmpty &&
            value.utf8.count <= 16_384 &&
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }
}
