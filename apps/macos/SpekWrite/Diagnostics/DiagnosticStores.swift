import Darwin
import Foundation

protocol DiagnosticEventStoring: Sendable {
    func append(_ event: DiagnosticEvent) async throws
}

protocol DiagnosticLifecycleStoring: Sendable {
    func beginRun() async throws -> Bool
    func endRun() async throws
}

enum DiagnosticLocalStoreError: Error, Equatable {
    case unsafePath
    case oversized
}

enum DiagnosticLifecycleStoreError: Error, Equatable {
    case readFailed
    case writeFailed
    case deleteFailed
}

struct DiagnosticSecureFileHooks: Sendable {
    let afterOpenForRead: @Sendable () throws -> Void
    let beforeRename: @Sendable () throws -> Void
    let beforeUnlink: @Sendable () throws -> Void
    let beforeDirectorySync: @Sendable (Int32) throws -> Void

    init(
        afterOpenForRead: @escaping @Sendable () throws -> Void = {},
        beforeRename: @escaping @Sendable () throws -> Void = {},
        beforeUnlink: @escaping @Sendable () throws -> Void = {},
        beforeDirectorySync: @escaping @Sendable (Int32) throws -> Void = {
            _ in
        }
    ) {
        self.afterOpenForRead = afterOpenForRead
        self.beforeRename = beforeRename
        self.beforeUnlink = beforeUnlink
        self.beforeDirectorySync = beforeDirectorySync
    }

    static let none = DiagnosticSecureFileHooks()
}

enum DiagnosticSecureFile {
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW |
        O_CLOEXEC
    private static let fileMode = mode_t(0o600)
    private static let directoryMode = mode_t(0o700)

    static func prepareDirectory(_ directoryURL: URL) throws {
        let descriptor = try openDirectory(directoryURL, createMissing: true)
        _ = Darwin.close(descriptor)
    }

    static func read(
        from fileURL: URL,
        maximumBytes: Int,
        hooks: DiagnosticSecureFileHooks = .none
    ) throws -> Data? {
        guard maximumBytes >= 0 else {
            throw DiagnosticLocalStoreError.oversized
        }
        let name = try safeName(fileURL.lastPathComponent)
        let directory = try openDirectory(
            fileURL.deletingLastPathComponent(),
            createMissing: false
        )
        defer { _ = Darwin.close(directory) }

        let descriptor = Darwin.openat(
            directory,
            name,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0, errno == ENOENT {
            return nil
        }
        guard descriptor >= 0 else { throw posixError() }
        defer { _ = Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw posixError()
        }
        guard isRegular(metadata.st_mode) else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        guard metadata.st_size >= 0,
              metadata.st_size <= off_t(maximumBytes) else {
            throw DiagnosticLocalStoreError.oversized
        }

        try hooks.afterOpenForRead()
        var result = Data()
        result.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            guard result.count + count <= maximumBytes else {
                throw DiagnosticLocalStoreError.oversized
            }
            result.append(buffer, count: count)
        }
        return result
    }

    static func write(
        _ data: Data,
        to fileURL: URL,
        hooks: DiagnosticSecureFileHooks = .none
    ) throws {
        let name = try safeName(fileURL.lastPathComponent)
        let directory = try openDirectory(
            fileURL.deletingLastPathComponent(),
            createMissing: true
        )
        defer { _ = Darwin.close(directory) }

        var destinationMetadata = stat()
        if Darwin.fstatat(
            directory,
            name,
            &destinationMetadata,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            guard isRegular(destinationMetadata.st_mode) else {
                throw DiagnosticLocalStoreError.unsafePath
            }
        } else if errno != ENOENT {
            throw posixError()
        }

        let temporaryName = try safeName(".\(name).\(UUID().uuidString)")
        var temporaryDescriptor = Darwin.openat(
            directory,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            fileMode
        )
        guard temporaryDescriptor >= 0 else { throw posixError() }

        do {
            try writeAll(data, to: temporaryDescriptor)
            guard Darwin.fchmod(temporaryDescriptor, fileMode) == 0 else {
                throw posixError()
            }
            guard Darwin.fsync(temporaryDescriptor) == 0 else {
                throw posixError()
            }
            let closeResult = Darwin.close(temporaryDescriptor)
            temporaryDescriptor = -1
            guard closeResult == 0 else { throw posixError() }

            try hooks.beforeRename()
            guard Darwin.renameat(
                directory,
                temporaryName,
                directory,
                name
            ) == 0 else {
                throw posixError()
            }
            try hooks.beforeDirectorySync(directory)
            guard Darwin.fsync(directory) == 0 else {
                throw posixError()
            }
        } catch {
            if temporaryDescriptor >= 0 {
                _ = Darwin.close(temporaryDescriptor)
            }
            _ = Darwin.unlinkat(directory, temporaryName, 0)
            throw error
        }
    }

    static func delete(
        _ fileURL: URL,
        hooks: DiagnosticSecureFileHooks = .none
    ) throws {
        let name = try safeName(fileURL.lastPathComponent)
        let directory = try openDirectory(
            fileURL.deletingLastPathComponent(),
            createMissing: false
        )
        defer { _ = Darwin.close(directory) }

        var metadata = stat()
        if Darwin.fstatat(
            directory,
            name,
            &metadata,
            AT_SYMLINK_NOFOLLOW
        ) != 0 {
            if errno == ENOENT { return }
            throw posixError()
        }
        guard isRegular(metadata.st_mode) else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        try hooks.beforeUnlink()
        guard Darwin.unlinkat(directory, name, 0) == 0 else {
            throw posixError()
        }
        try hooks.beforeDirectorySync(directory)
        guard Darwin.fsync(directory) == 0 else {
            throw posixError()
        }
    }

    private static func openDirectory(
        _ directoryURL: URL,
        createMissing: Bool
    ) throws -> Int32 {
        guard directoryURL.isFileURL,
              directoryURL.path.hasPrefix("/") else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        let pathComponents = directoryURL.pathComponents
        guard pathComponents.count > 1 else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        let components = Array(pathComponents[1...])
        guard !components.isEmpty,
              components.allSatisfy({ (try? safeName($0)) != nil }) else {
            throw DiagnosticLocalStoreError.unsafePath
        }

        var current = Darwin.open("/", directoryFlags)
        guard current >= 0 else { throw posixError() }
        do {
            for component in components {
                var next = Darwin.openat(current, component, directoryFlags)
                if next < 0, errno == ENOENT, createMissing {
                    guard Darwin.mkdirat(
                        current,
                        component,
                        directoryMode
                    ) == 0 || errno == EEXIST else {
                        throw posixError()
                    }
                    next = Darwin.openat(current, component, directoryFlags)
                }
                guard next >= 0 else {
                    if errno == ELOOP || errno == ENOTDIR {
                        throw DiagnosticLocalStoreError.unsafePath
                    }
                    throw posixError()
                }
                _ = Darwin.close(current)
                current = next
            }
            guard Darwin.fchmod(current, directoryMode) == 0 else {
                throw posixError()
            }
            return current
        } catch {
            _ = Darwin.close(current)
            throw error
        }
    }

    private static func safeName(_ value: String) throws -> String {
        guard !value.isEmpty,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\0") else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        return value
    }

    private static func isRegular(_ mode: mode_t) -> Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                guard count > 0 else { throw posixError(EIO) }
                offset += count
            }
        }
    }

    private static func posixError(_ code: Int32 = errno) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}

actor DiagnosticEventStore {
    static let defaultDirectoryURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TxChat/Diagnostics", isDirectory: true)

    private let directoryURL: URL
    private let fileURL: URL
    private let capacity: Int
    private let now: @Sendable () -> Date
    private let retention: TimeInterval = 7 * 86_400

    init(
        directoryURL: URL = defaultDirectoryURL,
        capacity: Int = 200,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("events.json")
        self.capacity = max(1, capacity)
        self.now = now
    }

    func append(_ event: DiagnosticEvent) async throws {
        try DiagnosticSecureFile.prepareDirectory(directoryURL)
        var events = try loadEvents()
        let cutoff = now().addingTimeInterval(-retention)
        events = events.filter { ($0.occurredAt.date ?? .distantPast) >= cutoff }
        events.append(event)
        events = Array(events.suffix(capacity))
        try DiagnosticSecureFile.write(
            DiagnosticJSONCodec.encode(events),
            to: fileURL
        )
    }

    func recent(
        confirmedAt: Date,
        limit: Int = 20
    ) throws -> [DiagnosticEvent] {
        try DiagnosticSecureFile.prepareDirectory(directoryURL)
        let cutoff = now().addingTimeInterval(-retention)
        let events = try loadEvents().filter {
            guard let date = $0.occurredAt.date else { return false }
            return date >= cutoff && date <= confirmedAt
        }
        return Array(events.suffix(min(max(0, limit), 20)))
    }

    private func loadEvents() throws -> [DiagnosticEvent] {
        guard let data = try DiagnosticSecureFile.read(
            from: fileURL,
            maximumBytes: 1_048_576
        ) else {
            return []
        }
        return try JSONDecoder().decode([DiagnosticEvent].self, from: data)
    }
}

actor DiagnosticLifecycleStore {
    private struct Marker: Codable {
        let schemaVersion: Int
        let runId: UUID
    }

    private let directoryURL: URL
    private let markerURL: URL
    private let cleanExitURL: URL
    private let deleteFile: @Sendable (URL) throws -> Void
    private var currentRunID: UUID?

    init(
        directoryURL: URL = DiagnosticEventStore.defaultDirectoryURL,
        deleteFile: @escaping @Sendable (URL) throws -> Void = {
            try DiagnosticSecureFile.delete($0)
        }
    ) {
        self.directoryURL = directoryURL
        markerURL = directoryURL.appendingPathComponent("running.json")
        cleanExitURL = directoryURL.appendingPathComponent("clean-exit.json")
        self.deleteFile = deleteFile
    }

    @discardableResult
    func beginRun() async throws -> Bool {
        do {
            try DiagnosticSecureFile.prepareDirectory(directoryURL)
        } catch {
            throw DiagnosticLifecycleStoreError.writeFailed
        }
        let previousMarker: Marker?
        let cleanExitMarker: Marker?
        do {
            previousMarker = try readMarker(at: markerURL)
            cleanExitMarker = try readMarker(at: cleanExitURL)
        } catch {
            throw DiagnosticLifecycleStoreError.readFailed
        }
        let previousRunWasUnclean = previousMarker != nil &&
            previousMarker?.runId != cleanExitMarker?.runId
        let runID = UUID()
        do {
            try writeMarker(Marker(schemaVersion: 1, runId: runID), to: markerURL)
            currentRunID = runID
        } catch {
            throw DiagnosticLifecycleStoreError.writeFailed
        }
        do {
            try deleteFile(cleanExitURL)
        } catch {
            throw DiagnosticLifecycleStoreError.deleteFailed
        }
        return previousRunWasUnclean
    }

    func endRun() async throws {
        guard let currentRunID else { return }
        do {
            try writeMarker(
                Marker(schemaVersion: 1, runId: currentRunID),
                to: cleanExitURL
            )
        } catch {
            do {
                try deleteFile(markerURL)
                self.currentRunID = nil
            } catch {
                throw DiagnosticLifecycleStoreError.deleteFailed
            }
            throw DiagnosticLifecycleStoreError.writeFailed
        }
        do {
            try deleteFile(markerURL)
            self.currentRunID = nil
        } catch {
            throw DiagnosticLifecycleStoreError.deleteFailed
        }
        do {
            try deleteFile(cleanExitURL)
        } catch {
            throw DiagnosticLifecycleStoreError.deleteFailed
        }
    }

    private func readMarker(at url: URL) throws -> Marker? {
        guard let data = try DiagnosticSecureFile.read(
            from: url,
            maximumBytes: 512
        ) else {
            return nil
        }
        let marker = try JSONDecoder().decode(Marker.self, from: data)
        guard marker.schemaVersion == 1 else {
            throw DiagnosticLocalStoreError.unsafePath
        }
        return marker
    }

    private func writeMarker(_ marker: Marker, to url: URL) throws {
        try DiagnosticSecureFile.write(
            DiagnosticJSONCodec.encode(marker),
            to: url
        )
    }
}

extension DiagnosticEventStore: DiagnosticEventStoring {}
extension DiagnosticLifecycleStore: DiagnosticLifecycleStoring {}

actor DiagnosticReportCache {
    private let directoryURL: URL
    private let fileURL: URL
    private let now: @Sendable () -> Date

    init(
        directoryURL: URL = DiagnosticEventStore.defaultDirectoryURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appendingPathComponent("consented-report.json")
        self.now = now
    }

    func saveIfAbsent(_ report: DiagnosticReportEnvelope) throws {
        try DiagnosticEnvelopeValidator.validate(report, now: now())
        try DiagnosticSecureFile.prepareDirectory(directoryURL)
        guard try load() == nil else {
            return
        }
        let data = try DiagnosticJSONCodec.encode(report)
        guard data.count <= 65_536 else {
            throw DiagnosticLocalStoreError.oversized
        }
        try DiagnosticSecureFile.write(data, to: fileURL)
    }

    func load() throws -> DiagnosticReportEnvelope? {
        try DiagnosticSecureFile.prepareDirectory(directoryURL)
        guard let data = try DiagnosticSecureFile.read(
            from: fileURL,
            maximumBytes: 65_536
        ) else {
            return nil
        }
        let report = try DiagnosticJSONCodec.decode(
            DiagnosticReportEnvelope.self,
            from: data
        )
        try DiagnosticEnvelopeValidator.validate(report, now: now())
        return report
    }

    func delete() throws {
        try DiagnosticSecureFile.prepareDirectory(directoryURL)
        try DiagnosticSecureFile.delete(fileURL)
    }

    func purgeOnLaunch() throws {
        try delete()
    }
}
