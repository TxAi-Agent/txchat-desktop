actor VolatileCredentialStore: CredentialStoring {
    private var credential: StoredRefreshCredential?

    func load() async throws -> StoredRefreshCredential? {
        credential
    }

    func replace(with value: StoredRefreshCredential) async throws {
        credential = value
    }

    func delete() async throws {
        credential = nil
    }
}
