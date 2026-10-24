import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class StyleProfileMigrationTests: XCTestCase {
    func testMigratesSchemaTwoDocumentOnIndexRebuild() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let legacy = PersistenceTestSupport.legacySchemaTwoJSON()
            let fileURL = try PersistenceTestSupport.writeProfileJSON(legacy, in: base)
            let originalData = try Data(contentsOf: fileURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loadedOptional = try await store.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            XCTAssertEqual(loaded.schemaVersion, StyleProfile.currentSchemaVersion)
            XCTAssertEqual(loaded.tone.temperature, 0.25)
            XCTAssertEqual(loaded.pairCount, 5)
            XCTAssertEqual(loaded.confidence, .standard)
            XCTAssertEqual(loaded.algorithmVersion, "st-2.1.0")
            XCTAssertEqual(loaded.finish, .neutral)
            XCTAssertEqual(loaded.tags, [])

            let rewrittenVersion = try PersistenceTestSupport.schemaVersion(of: fileURL)
            XCTAssertEqual(rewrittenVersion, StyleProfile.currentSchemaVersion)
            let rewritten = try XCTUnwrap(PersistenceTestSupport.jsonObject(at: fileURL))
            XCTAssertNotNil(rewritten["finish"])
            XCTAssertNotNil(rewritten["tags"])

            let backups = PersistenceTestSupport.files(
                in: base.appendingPathComponent("style-profile-migration-backups")
            )
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: backups[0]), originalData)

            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)

            // A fresh store must read the rewritten document without migrating
            // it again.
            let reopened = PersistenceTestSupport.makeStore(in: directory)
            let reloaded = try await reopened.loadActive()
            XCTAssertEqual(reloaded, loaded)
            let backupsAfterReload = PersistenceTestSupport.files(
                in: base.appendingPathComponent("style-profile-migration-backups")
            )
            XCTAssertEqual(backupsAfterReload.count, 1)
        }
    }

    func testMigratesLegacyActiveProfileAndRefreshesIndex() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let id: UUID
            do {
                let store = PersistenceTestSupport.makeStore(in: directory)
                try await store.save(PersistenceTestSupport.profile())
                let storedID = try await store.activeProfileID()
                id = try XCTUnwrap(storedID)
            }

            let profileURL = PersistenceTestSupport.profileFileURL(id: id, in: base)
            let legacy = Data(PersistenceTestSupport.legacySchemaTwoJSON().utf8)
            try legacy.write(to: profileURL)

            let reopened = PersistenceTestSupport.makeStore(in: directory)
            let loadedOptional = try await reopened.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            XCTAssertEqual(loaded.tone.temperature, 0.25)
            XCTAssertEqual(try PersistenceTestSupport.schemaVersion(of: profileURL), 3)

            let metadataOptional = try await reopened.activeProfileMetadata()
            let metadata = try XCTUnwrap(metadataOptional)
            XCTAssertEqual(metadata.id, id)
            XCTAssertEqual(metadata.schemaVersion, 3)

            let backups = PersistenceTestSupport.files(
                in: base.appendingPathComponent("style-profile-migration-backups")
            )
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: backups[0]), legacy)
        }
    }

    func testMigratesSchemaOneDocumentWithDefaults() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let fileURL = try PersistenceTestSupport.writeProfileJSON(
                PersistenceTestSupport.legacySchemaOneJSON(),
                in: base
            )

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loadedOptional = try await store.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            XCTAssertEqual(loaded.schemaVersion, StyleProfile.currentSchemaVersion)
            XCTAssertEqual(loaded.tone.exposure, 0.05)
            XCTAssertEqual(loaded.tone.temperature, -0.2)
            XCTAssertEqual(loaded.skin.smoothing, 0.2)
            XCTAssertEqual(loaded.body.legLength, 1.0)
            XCTAssertEqual(loaded.confidence, .trial)
            XCTAssertEqual(try PersistenceTestSupport.schemaVersion(of: fileURL), 3)
        }
    }

    func testDocumentWithoutSchemaVersionIsTreatedAsLegacy() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let json = """
            {
              "tone": {"exposure": 0.2, "temp": 0.4},
              "updatedAt": "2025-10-01T00:00:00Z"
            }
            """
            let fileURL = try PersistenceTestSupport.writeProfileJSON(json, in: base)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded?.tone.exposure, 0.2)
            XCTAssertEqual(loaded?.tone.temperature, 0.4)
            XCTAssertEqual(try PersistenceTestSupport.schemaVersion(of: fileURL), 3)
        }
    }

    func testFractionalSecondTimestampIsNormalized() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let json = PersistenceTestSupport.legacySchemaTwoJSON(
                updatedAt: "2025-12-01T00:00:00.500Z"
            )
            try PersistenceTestSupport.writeProfileJSON(json, in: base)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loadedOptional = try await store.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            let expected = try XCTUnwrap(
                ISO8601DateFormatter().date(from: "2025-12-01T00:00:00Z")
            )
            XCTAssertEqual(
                loaded.updatedAt.timeIntervalSince1970,
                expected.timeIntervalSince1970,
                accuracy: 1.0
            )
        }
    }

    func testCurrentSchemaIsNotRewrittenOrBackedUp() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            try await store.save(PersistenceTestSupport.profile())
            let files = PersistenceTestSupport.profileFiles(in: base)
            XCTAssertEqual(files.count, 1)
            let before = try Data(contentsOf: files[0])

            _ = try await store.loadActive()
            let after = try Data(contentsOf: files[0])

            XCTAssertEqual(after, before)
            let backups = base.appendingPathComponent("style-profile-migration-backups")
            XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        }
    }

    func testNewerSchemaIsRejectedAndFileRetained() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let newer = PersistenceTestSupport.legacySchemaTwoJSON()
                .replacingOccurrences(of: "\"schemaVersion\": 2", with: "\"schemaVersion\": 4")
            let fileURL = try PersistenceTestSupport.writeProfileJSON(newer, in: base)
            let original = try Data(contentsOf: fileURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError { try await store.loadActive() }

            XCTAssertEqual(error, .profileUnsupportedSchema(version: 4))
            XCTAssertEqual(error?.styleToneError, StyleToneError.unsupportedSchema(version: 4))
            XCTAssertEqual(error?.recovery, .recalibrate)
            XCTAssertFalse(error?.messageKey.isEmpty ?? true)
            XCTAssertEqual(try Data(contentsOf: fileURL), original)
        }
    }

    func testMalformedJSONIsRejectedAndFileRetained() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let fileURL = try PersistenceTestSupport.writeProfileJSON("{not valid json", in: base)
            let original = try Data(contentsOf: fileURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError { try await store.loadActive() }

            XCTAssertEqual(error, .profileCorrupt)
            XCTAssertEqual(error?.recovery, .recalibrate)
            XCTAssertEqual(try Data(contentsOf: fileURL), original)
        }
    }

    func testStructuralDamageInLegacyDocumentReportsMigrationFailure() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let fileURL = try PersistenceTestSupport.writeProfileJSON(
                PersistenceTestSupport.legacySchemaTwoJSON(),
                in: base
            )
            let data = try Data(contentsOf: fileURL)
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            root["tone"] = 42
            let damaged = try JSONSerialization.data(withJSONObject: root)
            try damaged.write(to: fileURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError { try await store.loadActive() }

            XCTAssertEqual(error, .profileMigrationFailed(sourceVersion: 2))
            XCTAssertEqual(try Data(contentsOf: fileURL), damaged)
        }
    }

    func testStructuralDamageInCurrentDocumentReportsCorruption() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let profile = PersistenceTestSupport.profile()
            let fileURL = try PersistenceTestSupport.writeProfile(profile, in: base)
            let data = try Data(contentsOf: fileURL)
            var root = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            root["tone"] = "not-an-object"
            let damaged = try JSONSerialization.data(withJSONObject: root)
            try damaged.write(to: fileURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError { try await store.loadActive() }

            XCTAssertEqual(error, .profileCorrupt)
            XCTAssertEqual(try Data(contentsOf: fileURL), damaged)
        }
    }

    func testEmptyFileReportsCorruption() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let fileURL = try PersistenceTestSupport.writeProfileJSON("", in: base)
            let store = PersistenceTestSupport.makeStore(in: directory)

            let error = await capturePersistenceError { try await store.loadActive() }
            XCTAssertEqual(error, .profileCorrupt)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testPureMigratorRoundTripsCurrentDocument() throws {
        let profile = PersistenceTestSupport.profile()
        let data = try StyleProfileJSONMigrator.encode(profile)
        let result = try StyleProfileJSONMigrator.decode(
            data,
            now: PersistenceTestSupport.referenceDate
        )

        XCTAssertFalse(result.migrated)
        XCTAssertEqual(result.sourceSchemaVersion, StyleProfile.currentSchemaVersion)
        XCTAssertEqual(result.profile, profile)
    }
}
