import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Persistence tests: metadata survives, pixels never touch the disk.
final class PairingSessionSnapshotTests: XCTestCase {
    private let date = PairingTestFactory.referenceDate

    // MARK: - Snapshot

    func testSnapshotCarriesMetadataButNoImageBytes() throws {
        let session = PairingTestFactory.session(grades: [.good, .warning], target: .five)
        let snapshot = session.snapshot()

        let data = try Self.encode(snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertLessThan(data.count, 4096, "session metadata must stay tiny")
        XCTAssertFalse(json.contains("ImageAsset"))
        XCTAssertFalse(json.contains("jpeg"))
        XCTAssertFalse(json.contains("png"))
        XCTAssertFalse(json.contains("base64"))
        XCTAssertTrue(json.contains("schemaVersion"))
        XCTAssertTrue(json.contains("sourceWidth"))
    }

    func testSnapshotRoundTripRestoresPairsWithoutImages() throws {
        let session = PairingTestFactory.session(
            grades: [.good, .warning, .rejected],
            target: .eight
        )
        let snapshot = try Self.decode(Self.encode(session.snapshot()))
        let restored = try PairingSessionState(snapshot: snapshot, restoredAt: date)

        XCTAssertEqual(restored.target, .eight)
        XCTAssertEqual(restored.stage, .editing)
        XCTAssertEqual(restored.pairs.count, 3)
        XCTAssertEqual(
            restored.pairs.map { $0.quality?.grade },
            [.good, .warning, .rejected]
        )

        for pair in restored.pairs {
            XCTAssertNil(pair.original)
            XCTAssertNil(pair.edited)
            XCTAssertTrue(pair.needsReselectOriginal)
            XCTAssertTrue(pair.needsReselectEdited)
            XCTAssertFalse(pair.isLearnable, "a photo-less pair cannot be learned from")
        }
        XCTAssertEqual(restored.progress.eligible, 0)
        XCTAssertEqual(
            restored.pairs.filter { $0.quality?.grade == .rejected }.count,
            1
        )
    }

    func testRestoredSessionKeepsStageAndCountsWhenPhotosAreBack() throws {
        var session = PairingTestFactory.session(grades: [.good, .good, .good], target: .three)
        XCTAssertTrue(session.complete(at: date))
        let restored = try PairingSessionState(snapshot: session.snapshot(), restoredAt: date)
        XCTAssertEqual(restored.stage, .completed)
        XCTAssertEqual(restored.pairs.count, 3)
    }

    func testMissingFieldsDecodeWithDefaults() throws {
        let json = Data(#"{"schemaVersion":1}"#.utf8)
        let snapshot = try JSONDecoder().decode(PairingSessionSnapshot.self, from: json)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.targetCount, PairingTarget.defaultTarget.count)
        XCTAssertEqual(snapshot.stage, .editing)
        XCTAssertTrue(snapshot.pairs.isEmpty)
        XCTAssertTrue(snapshot.completedPairTimestamps.isEmpty)
    }

    func testUnknownFieldsAreIgnored() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PairingTestFactory.session(grades: [.good], target: .three).snapshot())
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("snapshot should be a JSON object")
        }
        object["futureField"] = ["ignored": true]
        let modified = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(PairingSessionSnapshot.self, from: modified)
        XCTAssertEqual(snapshot.pairs.count, 1)
    }

    func testUnsupportedSchemaThrows() throws {
        let snapshot = PairingSessionSnapshot(
            schemaVersion: 2,
            targetCount: 3,
            stage: .editing,
            startedAt: date,
            updatedAt: date,
            lastActivityAt: date,
            pairs: []
        )
        XCTAssertThrowsError(
            try PairingSessionState(snapshot: snapshot, restoredAt: date)
        ) { error in
            XCTAssertEqual(
                error as? PairingSessionStoreError,
                .unsupportedSchema(version: 2)
            )
        }
    }

    // MARK: - File store

    func testFileStoreRoundTripAndClear() async throws {
        let snapshot = PairingTestFactory.session(grades: [.good], target: .five).snapshot()
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "PairingStore") { directory in
            let store = FilePairingSessionStore(directory: directory)

            try await store.save(snapshot)
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))

            let loaded = try await store.load()
            XCTAssertEqual(loaded, snapshot)

            try await store.clear()
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
            let afterClear = try await store.load()
            XCTAssertNil(afterClear)
        }
    }

    func testFileStoreLoadWithoutFileReturnsNil() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "PairingEmpty") { directory in
            let store = FilePairingSessionStore(directory: directory)
            let snapshot = try await store.load()
            XCTAssertNil(snapshot)
        }
    }

    func testFileStoreRejectsCorruptJSON() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "PairingCorrupt") { directory in
            let store = FilePairingSessionStore(directory: directory)
            try Data("not a session".utf8).write(to: store.fileURL)
            do {
                _ = try await store.load()
                XCTFail("corrupt JSON must not load")
            } catch {
                XCTAssertEqual(error as? PairingSessionStoreError, .corrupted)
            }
        }
    }

    func testFileStoreRejectsOversizedFile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "PairingLarge") { directory in
            let store = FilePairingSessionStore(directory: directory)
            let oversized = Data(count: FilePairingSessionStore.maximumFileSize + 1)
            try oversized.write(to: store.fileURL)
            do {
                _ = try await store.load()
                XCTFail("oversized session must not load")
            } catch {
                XCTAssertEqual(error as? PairingSessionStoreError, .corrupted)
            }
        }
    }

    func testFileStoreRejectsUnsupportedSchema() async throws {
        let snapshot = PairingSessionSnapshot(
            schemaVersion: 99,
            targetCount: 3,
            stage: .editing,
            startedAt: date,
            updatedAt: date,
            lastActivityAt: date,
            pairs: []
        )
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "PairingSchema") { directory in
            let store = FilePairingSessionStore(directory: directory)
            try await store.save(snapshot)
            do {
                _ = try await store.load()
                XCTFail("unsupported schema must not load")
            } catch {
                XCTAssertEqual(
                    error as? PairingSessionStoreError,
                    .unsupportedSchema(version: 99)
                )
            }
        }
    }

    func testDefaultDirectoryIsInTheAppSandboxOnly() {
        guard let directory = FilePairingSessionStore.defaultDirectory() else {
            return XCTFail("application support directory should resolve")
        }
        XCTAssertEqual(directory.lastPathComponent, "Pairing")
        XCTAssertEqual(
            directory.deletingLastPathComponent().lastPathComponent,
            "StyleTone"
        )
        XCTAssertFalse(directory.path.contains("Group"))
    }

    // MARK: - Helpers

    private static func encode(_ snapshot: PairingSessionSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    private static func decode(_ data: Data) throws -> PairingSessionSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PairingSessionSnapshot.self, from: data)
    }
}
