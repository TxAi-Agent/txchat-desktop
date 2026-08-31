import Foundation

protocol DictionaryFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func readFile(at url: URL) throws -> Data
    func createDirectory(at url: URL) throws
    func writeAtomically(_ data: Data, to url: URL) throws
}

final class FoundationDictionaryFileSystem: @unchecked Sendable,
    DictionaryFileSystem
{
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}

enum DictionaryStoreError: Error, Equatable, Sendable {
    case readFailed
    case directoryCreationFailed
    case writeFailed
}

protocol DictionaryStoring: Sendable {
    var fileURL: URL { get }
    func load() async throws -> TxChatDictionaryDocument
    func save(_ entries: [TxChatDictionaryEntry]) async throws
    func ensureFileExists() async throws -> URL
}

actor DictionaryStore: DictionaryStoring {
    nonisolated let fileURL: URL

    private let fileSystem: any DictionaryFileSystem
    private let codec: DictionaryMarkdownCodec

    init(
        fileURL: URL,
        fileSystem: any DictionaryFileSystem = FoundationDictionaryFileSystem(),
        codec: DictionaryMarkdownCodec = DictionaryMarkdownCodec()
    ) {
        self.fileURL = fileURL
        self.fileSystem = fileSystem
        self.codec = codec
    }

    static func productionFileURL() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("TxChat", isDirectory: true)
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("TxChat-Dictionary.md", isDirectory: false)
    }

    static func production(
        fileManager: FileManager = .default
    ) -> DictionaryStore {
        DictionaryStore(
            fileURL: productionFileURL(),
            fileSystem: FoundationDictionaryFileSystem(fileManager: fileManager)
        )
    }

    func load() async throws -> TxChatDictionaryDocument {
        guard fileSystem.fileExists(at: fileURL) else { return .empty }
        let data: Data
        do {
            data = try fileSystem.readFile(at: fileURL)
        } catch {
            throw DictionaryStoreError.readFailed
        }
        return try codec.decode(data)
    }

    func save(_ entries: [TxChatDictionaryEntry]) async throws {
        let data = try codec.encode(entries)
        try createParentDirectory()
        do {
            try fileSystem.writeAtomically(data, to: fileURL)
        } catch {
            throw DictionaryStoreError.writeFailed
        }
    }

    @discardableResult
    func ensureFileExists() async throws -> URL {
        guard !fileSystem.fileExists(at: fileURL) else { return fileURL }
        try createParentDirectory()
        let data = try codec.encode([])
        do {
            try fileSystem.writeAtomically(data, to: fileURL)
        } catch {
            throw DictionaryStoreError.writeFailed
        }
        return fileURL
    }

    private func createParentDirectory() throws {
        do {
            try fileSystem.createDirectory(at: fileURL.deletingLastPathComponent())
        } catch {
            throw DictionaryStoreError.directoryCreationFailed
        }
    }
}
