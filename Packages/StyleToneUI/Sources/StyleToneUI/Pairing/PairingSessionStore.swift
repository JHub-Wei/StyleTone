import Foundation

/// Errors surfaced by the pairing session store.
///
/// The UI maps these to localization keys; the errors themselves carry no file
/// paths, photo identifiers or user text.
public enum PairingSessionStoreError: Error, Sendable, Equatable {
    /// The file cannot be decoded, or exceeds the size limit.
    case corrupted
    /// The stored schema is newer than this build understands.
    case unsupportedSchema(version: Int)
    /// The session could not be written.
    case writeFailed
    /// The session could not be read.
    case readFailed
    /// The session could not be removed.
    case clearFailed
}

/// Persists the metadata-only pairing session.
///
/// Implementations must never store pixels. `StyleTonePersistence` (WP-08) can
/// adopt this protocol later without the UI importing it, keeping the module
/// dependency direction (`UI -> Core, Imaging`) intact.
public protocol PairingSessionStoring: Sendable {
    func load() async throws -> PairingSessionSnapshot?
    func save(_ snapshot: PairingSessionSnapshot) async throws
    func clear() async throws
}

// MARK: - In-memory store

/// Store used by previews, tests and the placeholder dependency container.
public actor InMemoryPairingSessionStore: PairingSessionStoring {
    private var snapshot: PairingSessionSnapshot?
    public private(set) var saveCount = 0
    public private(set) var loadCount = 0
    public private(set) var clearCount = 0

    public init(snapshot: PairingSessionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() async throws -> PairingSessionSnapshot? {
        loadCount += 1
        return snapshot
    }

    public func save(_ snapshot: PairingSessionSnapshot) async throws {
        self.snapshot = snapshot
        saveCount += 1
    }

    public func clear() async throws {
        snapshot = nil
        clearCount += 1
    }

    /// The stored snapshot, for assertions in tests.
    public func currentSnapshot() async -> PairingSessionSnapshot? {
        snapshot
    }
}

// MARK: - File store

/// Metadata-only session store backed by one JSON file.
///
/// The file lives in the app's own sandbox (the host decides the directory),
/// is written atomically and, on iOS, with complete file protection. It never
/// contains image data; after a relaunch the UI asks the user to re-pick the
/// photographs.
public actor FilePairingSessionStore: PairingSessionStoring {
    public static let defaultFileName = "pairing-session.json"
    /// Guard against decoding an unexpectedly huge or malicious file.
    public static let maximumFileSize = 512 * 1024

    private let directory: URL
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileName: String = FilePairingSessionStore.defaultFileName) {
        self.directory = directory
        self.fileName = fileName

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Full path of the metadata file.
    public nonisolated var fileURL: URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Default directory inside the app sandbox: Application Support/Pairing.
    ///
    /// The host may inject any directory; the store never resolves a shared
    /// App Group container.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return base
            .appendingPathComponent("StyleTone", isDirectory: true)
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    public func load() async throws -> PairingSessionSnapshot? {
        try Task.checkCancellation()
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, size > Self.maximumFileSize {
            throw PairingSessionStoreError.corrupted
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw PairingSessionStoreError.readFailed
        }

        let snapshot: PairingSessionSnapshot
        do {
            snapshot = try decoder.decode(PairingSessionSnapshot.self, from: data)
        } catch {
            throw PairingSessionStoreError.corrupted
        }

        guard snapshot.schemaVersion == PairingSessionSnapshot.currentSchemaVersion else {
            throw PairingSessionStoreError.unsupportedSchema(version: snapshot.schemaVersion)
        }
        return snapshot
    }

    public func save(_ snapshot: PairingSessionSnapshot) async throws {
        try Task.checkCancellation()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PairingSessionStoreError.writeFailed
        }

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw PairingSessionStoreError.writeFailed
        }
        guard data.count <= Self.maximumFileSize else {
            throw PairingSessionStoreError.writeFailed
        }

        do {
            try Self.write(data, to: fileURL)
        } catch {
            throw PairingSessionStoreError.writeFailed
        }
    }

    public func clear() async throws {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PairingSessionStoreError.clearFailed
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}
