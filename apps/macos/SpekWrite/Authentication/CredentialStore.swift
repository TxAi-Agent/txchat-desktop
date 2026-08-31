import Foundation

struct StoredRefreshCredential: Codable, Equatable, Sendable,
    CustomStringConvertible
{
    let refreshToken: String
    let sessionID: String
    let maskedPhone: String?

    init(
        refreshToken: String,
        sessionID: String,
        maskedPhone: String? = nil
    ) {
        self.refreshToken = refreshToken
        self.sessionID = sessionID
        self.maskedPhone = maskedPhone
    }

    var description: String {
        "StoredRefreshCredential(sessionID: \(sessionID))"
    }
}

enum CredentialCodec {
    enum Error: Swift.Error, Equatable {
        case invalidShape
    }

    static func encode(_ value: StoredRefreshCredential) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode(_ data: Data) throws -> StoredRefreshCredential {
        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            Set(object.keys).isSubset(
                of: ["refreshToken", "sessionID", "maskedPhone"]
            ),
            object["refreshToken"] != nil,
            object["sessionID"] != nil
        else {
            throw Error.invalidShape
        }
        return try JSONDecoder().decode(
            StoredRefreshCredential.self,
            from: data
        )
    }
}

protocol CredentialStoring: Sendable {
    func load() async throws -> StoredRefreshCredential?
    func replace(with value: StoredRefreshCredential) async throws
    func delete() async throws
}
