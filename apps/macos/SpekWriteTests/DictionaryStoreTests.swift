import Foundation
import XCTest
@testable import SpekWrite

final class DictionaryStoreTests: XCTestCase {
    func testProductionURLUsesSystemApplicationSupportDirectory() throws {
        let fileURL = DictionaryStore.productionFileURL()
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        )

        XCTAssertEqual(
            fileURL,
            applicationSupport
                .appendingPathComponent("TxChat", isDirectory: true)
                .appendingPathComponent("Dictionary", isDirectory: true)
                .appendingPathComponent("TxChat-Dictionary.md", isDirectory: false)
        )
    }

    func testMissingFileLoadsEmptyWithoutCreatingFileOrDirectory() async throws {
        let fileSystem = DictionaryStoreFileSystemSpy()
        let fileURL = URL(fileURLWithPath: "/test/TxChat-Dictionary.md")
        let store = DictionaryStore(fileURL: fileURL, fileSystem: fileSystem)

        let document = try await store.load()

        XCTAssertEqual(document, .empty)
        XCTAssertEqual(fileSystem.createDirectoryCallCount, 0)
        XCTAssertEqual(fileSystem.atomicWriteCallCount, 0)
    }

    func testFirstSaveCreatesDirectoryAndUsesAtomicWrite() async throws {
        let fileSystem = DictionaryStoreFileSystemSpy()
        let fileURL = URL(fileURLWithPath: "/test/Dictionary/TxChat-Dictionary.md")
        let store = DictionaryStore(fileURL: fileURL, fileSystem: fileSystem)
        let entries = [
            TxChatDictionaryEntry(
                wrong: "Txchat",
                correct: "TxChat",
                isEnabled: true
            ),
        ]

        try await store.save(entries)

        XCTAssertEqual(
            fileSystem.createdDirectories,
            [fileURL.deletingLastPathComponent()]
        )
        XCTAssertEqual(fileSystem.atomicWriteCallCount, 1)
        let stored = try XCTUnwrap(fileSystem.files[fileURL])
        XCTAssertEqual(
            try DictionaryMarkdownCodec().decode(stored).entries,
            entries
        )
    }

    func testEnsureFileExistsCreatesStableEmptyTemplateOnlyOnce() async throws {
        let fileSystem = DictionaryStoreFileSystemSpy()
        let fileURL = URL(fileURLWithPath: "/test/Dictionary/TxChat-Dictionary.md")
        let store = DictionaryStore(fileURL: fileURL, fileSystem: fileSystem)

        let first = try await store.ensureFileExists()
        let second = try await store.ensureFileExists()

        XCTAssertEqual(first, fileURL)
        XCTAssertEqual(second, fileURL)
        XCTAssertEqual(fileSystem.atomicWriteCallCount, 1)
        XCTAssertEqual(
            fileSystem.files[fileURL],
            try DictionaryMarkdownCodec().encode([])
        )
    }

    func testAtomicWriteFailureLeavesOldFileUntouched() async throws {
        let fileURL = URL(fileURLWithPath: "/test/Dictionary/TxChat-Dictionary.md")
        let oldData = try DictionaryMarkdownCodec().encode([
            .init(wrong: "old", correct: "existing", isEnabled: true),
        ])
        let fileSystem = DictionaryStoreFileSystemSpy(
            files: [fileURL: oldData]
        )
        fileSystem.atomicWriteError = DictionaryStoreFileSystemSpy.Failure()
        let store = DictionaryStore(fileURL: fileURL, fileSystem: fileSystem)

        do {
            try await store.save([
                .init(wrong: "new", correct: "replacement", isEnabled: true),
            ])
            XCTFail("Expected atomic write failure")
        } catch {
            XCTAssertEqual(error as? DictionaryStoreError, .writeFailed)
        }
        XCTAssertEqual(fileSystem.files[fileURL], oldData)
    }

    func testReadAndDirectoryFailuresAreMappedToContentFreeCategories() async {
        let fileURL = URL(fileURLWithPath: "/test/Dictionary/TxChat-Dictionary.md")
        let readFailure = DictionaryStoreFileSystemSpy(
            files: [fileURL: Data()]
        )
        readFailure.readError = DictionaryStoreFileSystemSpy.Failure()
        let readStore = DictionaryStore(
            fileURL: fileURL,
            fileSystem: readFailure
        )

        do {
            _ = try await readStore.load()
            XCTFail("Expected read failure")
        } catch {
            XCTAssertEqual(error as? DictionaryStoreError, .readFailed)
        }

        let directoryFailure = DictionaryStoreFileSystemSpy()
        directoryFailure.createDirectoryError =
            DictionaryStoreFileSystemSpy.Failure()
        let directoryStore = DictionaryStore(
            fileURL: fileURL,
            fileSystem: directoryFailure
        )
        do {
            try await directoryStore.save([])
            XCTFail("Expected directory failure")
        } catch {
            XCTAssertEqual(
                error as? DictionaryStoreError,
                .directoryCreationFailed
            )
        }
    }
}

private final class DictionaryStoreFileSystemSpy: @unchecked Sendable,
    DictionaryFileSystem
{
    struct Failure: Error {}

    var files: [URL: Data]
    var createdDirectories: [URL] = []
    var atomicWriteCallCount = 0
    var readError: Error?
    var createDirectoryError: Error?
    var atomicWriteError: Error?

    var createDirectoryCallCount: Int { createdDirectories.count }

    init(files: [URL: Data] = [:]) {
        self.files = files
    }

    func fileExists(at url: URL) -> Bool {
        files[url] != nil
    }

    func readFile(at url: URL) throws -> Data {
        if let readError { throw readError }
        return files[url] ?? Data()
    }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError { throw createDirectoryError }
        createdDirectories.append(url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        atomicWriteCallCount += 1
        if let atomicWriteError { throw atomicWriteError }
        files[url] = data
    }
}
