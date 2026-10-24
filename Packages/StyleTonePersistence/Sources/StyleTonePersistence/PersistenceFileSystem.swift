import Foundation

/// Narrow file-system boundary used by the persistence store.
///
/// Injecting the file system keeps the store testable (failure injection,
/// protection auditing, main-thread checks) without exposing paths in logs or
/// errors. Implementations must be thread-safe; the store calls them from its
/// actor, never from the main actor.
public protocol PersistenceFileSystem: Sendable {
    func createDirectory(at url: URL, protection: PersistenceFileProtection) throws
    func write(_ data: Data, to url: URL, protection: PersistenceFileProtection) throws
    func read(_ url: URL) throws -> Data
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
    func exists(_ url: URL) -> Bool
    func files(in directory: URL) throws -> [URL]
    func setProtection(_ protection: PersistenceFileProtection, at url: URL) throws
}

public extension PersistenceFileSystem {
    /// Removes a file or directory if it exists. Missing items are not an error.
    func removeIfExists(_ url: URL) throws {
        if exists(url) {
            try remove(url)
        }
    }
}

/// Production file-system implementation.
///
/// Writes are atomic (`Data.write(options: .atomic)`), then the requested data
/// protection class is applied immediately. On iOS-family platforms the class is
/// enforced with `FileAttributeKey.protectionKey`; on macOS the attribute does
/// not exist and ``setProtection(_:at:)`` is intentionally a no-op.
public struct LocalPersistenceFileSystem: PersistenceFileSystem {
    public init() {}

    public func createDirectory(at url: URL, protection: PersistenceFileProtection) throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection.platformValue]
        )
        #else
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #endif
        try? setProtection(protection, at: url)
    }

    public func write(_ data: Data, to url: URL, protection: PersistenceFileProtection) throws {
        try data.write(to: url, options: [.atomic])
        try setProtection(protection, at: url)
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func move(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func files(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        return contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { $0.path < $1.path }
    }

    public func setProtection(_ protection: PersistenceFileProtection, at url: URL) throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try FileManager.default.setAttributes(
            [.protectionKey: protection.platformValue],
            ofItemAtPath: url.path
        )
        #else
        _ = protection
        _ = url
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
private extension PersistenceFileProtection {
    var platformValue: FileProtectionType {
        switch self {
        case .complete:
            return .complete
        case .completeUnlessOpen:
            return .completeUnlessOpen
        case .completeUntilFirstUserAuthentication:
            return .completeUntilFirstUserAuthentication
        case .none:
            return .none
        }
    }
}
#endif
