import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

enum PersistenceTestSupport {
    static let referenceDate = FixedDateProvider.reference

    static func configuration(in directory: URL) -> PersistenceConfiguration {
        PersistenceConfiguration(
            baseDirectory: directory.appendingPathComponent("StyleToneStore", isDirectory: true)
        )
    }

    static func baseDirectory(in directory: URL) -> URL {
        configuration(in: directory).baseDirectory
    }

    static func makeStore(
        in directory: URL,
        fileSystem: any PersistenceFileSystem = LocalPersistenceFileSystem(),
        date: Date = referenceDate
    ) -> SwiftDataStyleProfileStore {
        makeStore(
            in: directory,
            fileSystem: fileSystem,
            dateProvider: FixedDateProvider(date)
        )
    }

    static func makeStore(
        in directory: URL,
        fileSystem: any PersistenceFileSystem = LocalPersistenceFileSystem(),
        dateProvider: any DateProviding
    ) -> SwiftDataStyleProfileStore {
        SwiftDataStyleProfileStore(
            configuration: configuration(in: directory),
            fileSystem: fileSystem,
            dateProvider: dateProvider
        )
    }

    static func profile(
        pairCount: Int = 5,
        confidence: ConfidenceLevel = .standard,
        tags: [String] = ["style.natural", "style.soft"],
        updatedAt: Date = referenceDate
    ) -> StyleProfile {
        StyleProfile(
            pairCount: pairCount,
            confidence: confidence,
            tone: ToneParameters(
                exposure: 0.12,
                contrast: -0.08,
                highlights: 0.2,
                shadows: -0.15,
                temperature: 0.3,
                tint: 0.04,
                saturation: 0.1
            ),
            skin: SkinParameters(smoothing: 0.4, evenness: 0.3, blemish: 0.25),
            face: FaceParameters(slim: 0.2, jaw: 0.15),
            body: BodyParameters(arm: 0.1, waist: 0.2, leg: 0.15, legLength: 1.05),
            finish: FinishParameters(grain: 0.1, vignette: -0.05),
            tags: tags,
            updatedAt: updatedAt
        )
    }

    static func profileFileURL(id: UUID, in baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent("style-profiles", isDirectory: true)
            .appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    static func profileFiles(in baseDirectory: URL) -> [URL] {
        let directory = baseDirectory.appendingPathComponent("style-profiles", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.path < $1.path }
    }

    static func allJSONFiles(in baseDirectory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    static func files(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Writes arbitrary JSON bytes into the canonical profile directory.
    @discardableResult
    static func writeProfileJSON(
        _ json: String,
        id: UUID = UUID(),
        in baseDirectory: URL
    ) throws -> URL {
        let directory = baseDirectory.appendingPathComponent("style-profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = profileFileURL(id: id, in: baseDirectory)
        try Data(json.utf8).write(to: url)
        return url
    }

    /// Writes a current-schema profile document without using the store index.
    @discardableResult
    static func writeProfile(
        _ profile: StyleProfile,
        id: UUID = UUID(),
        in baseDirectory: URL
    ) throws -> URL {
        let directory = baseDirectory.appendingPathComponent("style-profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = profileFileURL(id: id, in: baseDirectory)
        let data = try StyleProfileJSONMigrator.encode(profile)
        try data.write(to: url)
        return url
    }

    static func legacySchemaTwoJSON(
        temp: String = "0.25",
        updatedAt: String = "2025-12-01T00:00:00Z"
    ) -> String {
        """
        {
          "schemaVersion": 2,
          "algorithmVersion": "st-2.1.0",
          "pairCount": 5,
          "confidence": "standard",
          "tone": {
            "exposure": 0.1,
            "contrast": 0.05,
            "highlights": -0.1,
            "shadows": 0.02,
            "temp": \(temp),
            "tint": 0.01,
            "saturation": 0.03
          },
          "skin": {"smoothing": 0.4, "evenness": 0.3, "blemish": 0.2},
          "face": {"slim": 0.2, "jaw": 0.15},
          "body": {"arm": 0.1, "waist": 0.2, "leg": 0.15, "legLength": 1.05},
          "updatedAt": "\(updatedAt)"
        }
        """
    }

    static func legacySchemaOneJSON(
        updatedAt: String = "2025-11-01T00:00:00Z"
    ) -> String {
        """
        {
          "schemaVersion": 1,
          "algorithmVersion": "st-1.0.0",
          "pairCount": 3,
          "confidence": "trial",
          "tone": {"exposure": 0.05, "temp": -0.2},
          "skin": {"smoothing": 0.2},
          "updatedAt": "\(updatedAt)"
        }
        """
    }

    static func schemaVersion(of url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(object as? [String: Any])
        return try XCTUnwrap(root["schemaVersion"] as? Int)
    }
}

/// Captures a typed persistence error without throwing out of the test.
func capturePersistenceError<T>(
    _ operation: () async throws -> T
) async -> StylePersistenceError? {
    do {
        _ = try await operation()
        return nil
    } catch let error as StylePersistenceError {
        return error
    } catch {
        XCTFail("Unexpected error type: \(error)")
        return nil
    }
}

/// File-system decorator that records operations, their protection class and the
/// executing thread. Used to prove the store never performs I/O on the main
/// thread and always requests the configured protection.
final class RecordingPersistenceFileSystem: PersistenceFileSystem, @unchecked Sendable {
    struct Operation: Sendable {
        enum Kind: String, Sendable, Equatable {
            case createDirectory
            case write
            case read
            case move
            case remove
            case exists
            case files
            case setProtection
        }

        let kind: Kind
        let url: URL
        let protection: PersistenceFileProtection?
        let isMainThread: Bool
    }

    private let lock = NSLock()
    private var storage: [Operation] = []
    private let local = LocalPersistenceFileSystem()

    var operations: [Operation] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var writes: [Operation] {
        operations.filter { $0.kind == .write }
    }

    var callsOnMainThread: [Operation] {
        operations.filter { $0.isMainThread }
    }

    func createDirectory(at url: URL, protection: PersistenceFileProtection) throws {
        record(.createDirectory, url: url, protection: protection)
        try local.createDirectory(at: url, protection: protection)
    }

    func write(_ data: Data, to url: URL, protection: PersistenceFileProtection) throws {
        record(.write, url: url, protection: protection)
        try local.write(data, to: url, protection: protection)
    }

    func read(_ url: URL) throws -> Data {
        record(.read, url: url, protection: nil)
        return try local.read(url)
    }

    func move(_ source: URL, to destination: URL) throws {
        record(.move, url: source, protection: nil)
        try local.move(source, to: destination)
    }

    func remove(_ url: URL) throws {
        record(.remove, url: url, protection: nil)
        try local.remove(url)
    }

    func exists(_ url: URL) -> Bool {
        record(.exists, url: url, protection: nil)
        return local.exists(url)
    }

    func files(in directory: URL) throws -> [URL] {
        record(.files, url: directory, protection: nil)
        return try local.files(in: directory)
    }

    func setProtection(_ protection: PersistenceFileProtection, at url: URL) throws {
        record(.setProtection, url: url, protection: protection)
        try local.setProtection(protection, at: url)
    }

    private func record(
        _ kind: Operation.Kind,
        url: URL,
        protection: PersistenceFileProtection?
    ) {
        let operation = Operation(
            kind: kind,
            url: url,
            protection: protection,
            isMainThread: Thread.isMainThread
        )
        lock.lock()
        storage.append(operation)
        lock.unlock()
    }
}
