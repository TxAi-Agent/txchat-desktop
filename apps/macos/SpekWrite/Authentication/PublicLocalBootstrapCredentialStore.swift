import Foundation

actor PublicLocalBootstrapCredentialStore: CredentialStoring {
    typealias Bootstrap = @Sendable () async throws -> StoredRefreshCredential

    private struct BootstrapFlight: Sendable {
        let id: UUID
        let task: Task<StoredRefreshCredential, Error>
    }

    private let bootstrap: Bootstrap
    private var credential: StoredRefreshCredential?
    private var flight: BootstrapFlight?

    init(bootstrap: @escaping Bootstrap) {
        self.bootstrap = bootstrap
    }

    func load() async throws -> StoredRefreshCredential? {
        if let credential {
            return credential
        }
        if let flight {
            return try await consume(flight)
        }

        let id = UUID()
        let bootstrap = self.bootstrap
        let task = Task<StoredRefreshCredential, Error> {
            try await bootstrap()
        }
        let newFlight = BootstrapFlight(id: id, task: task)
        flight = newFlight
        return try await consume(newFlight)
    }

    func replace(with value: StoredRefreshCredential) async throws {
        flight?.task.cancel()
        flight = nil
        credential = value
    }

    func delete() async throws {
        flight?.task.cancel()
        flight = nil
        credential = nil
    }

    private func consume(
        _ consumedFlight: BootstrapFlight
    ) async throws -> StoredRefreshCredential? {
        do {
            let value = try await consumedFlight.task.value
            guard flight?.id == consumedFlight.id else {
                return credential
            }
            flight = nil
            credential = value
            return value
        } catch {
            if flight?.id == consumedFlight.id {
                flight = nil
            }
            throw error
        }
    }
}
