import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class StyleProfileStoreCRUDTests: XCTestCase {
    func testNewStoreHasNoActiveProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)

            let profile = try await store.loadActive()
            XCTAssertNil(profile)
            let id = try await store.activeProfileID()
            XCTAssertNil(id)
        }
    }

    func testSaveThenLoadReturnsProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let profile = PersistenceTestSupport.profile()

            try await store.save(profile)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded, profile)
            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)
        }
    }

    func testProfilePersistsAcrossStoreInstances() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let profile = PersistenceTestSupport.profile()
            let base = PersistenceTestSupport.baseDirectory(in: directory)

            do {
                let store = PersistenceTestSupport.makeStore(in: directory)
                try await store.save(profile)
            }

            let reopened = PersistenceTestSupport.makeStore(in: directory)
            let loaded = try await reopened.loadActive()

            XCTAssertEqual(loaded, profile)
            XCTAssertEqual(PersistenceTestSupport.profileFiles(in: base).count, 1)
        }
    }

    func testSecondSaveReusesIdentityAndFile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let first = PersistenceTestSupport.profile(pairCount: 3, confidence: .trial)
            let second = PersistenceTestSupport.profile(
                pairCount: 8,
                confidence: .stable,
                updatedAt: PersistenceTestSupport.referenceDate.addingTimeInterval(120)
            )

            try await store.save(first)
            let firstID = try await store.activeProfileID()
            XCTAssertNotNil(firstID)

            try await store.save(second)
            let secondID = try await store.activeProfileID()

            XCTAssertEqual(firstID, secondID)
            XCTAssertEqual(PersistenceTestSupport.profileFiles(in: base).count, 1)
            let loaded = try await store.loadActive()
            XCTAssertEqual(loaded, second)
        }
    }

    func testSaveRepairsSchemaVersionAndMetadata() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            var profile = PersistenceTestSupport.profile()
            profile.schemaVersion = 1
            profile.algorithmVersion = "   "
            profile.tags = [" style.a ", "", "style.a", "style.b"]
            profile.tone.exposure = .nan

            try await store.save(profile)
            let loadedOptional = try await store.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            XCTAssertEqual(loaded.schemaVersion, StyleProfile.currentSchemaVersion)
            XCTAssertEqual(loaded.algorithmVersion, StyleProfile.currentAlgorithmVersion)
            XCTAssertEqual(loaded.tags, ["style.a", "style.b"])
            XCTAssertEqual(loaded.tone.exposure, 0)

            let files = PersistenceTestSupport.profileFiles(in: base)
            let schemaVersion = try PersistenceTestSupport.schemaVersion(of: files[0])
            XCTAssertEqual(schemaVersion, StyleProfile.currentSchemaVersion)
        }
    }

    func testSaveNormalizesPairCount() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            var profile = PersistenceTestSupport.profile()
            profile.pairCount = -4

            try await store.save(profile)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded?.pairCount, 0)
        }
    }

    func testDeleteAllThenSaveCreatesFreshProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let first = PersistenceTestSupport.profile(pairCount: 3)
            try await store.save(first)
            let firstID = try await store.activeProfileID()

            try await store.deleteAll()
            let afterDelete = try await store.loadActive()
            XCTAssertNil(afterDelete)

            let second = PersistenceTestSupport.profile(pairCount: 5)
            try await store.save(second)
            let secondID = try await store.activeProfileID()

            XCTAssertNotEqual(firstID, secondID)
            let reloaded = try await store.loadActive()
            XCTAssertEqual(reloaded, second)
        }
    }

    func testMissingActiveFileIsRecoveredAsNoProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            try await store.save(PersistenceTestSupport.profile())
            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)

            let files = PersistenceTestSupport.profileFiles(in: base)
            XCTAssertEqual(files.count, 1)
            try FileManager.default.removeItem(at: files[0])

            // The same store instance must degrade to "no profile" instead of
            // crashing on a stale index row.
            let loaded = try await store.loadActive()
            XCTAssertNil(loaded)
            let activeID = try await store.activeProfileID()
            XCTAssertNil(activeID)
        }
    }

    func testMetadataMatchesSavedProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let profile = PersistenceTestSupport.profile(pairCount: 8, confidence: .stable)
            try await store.save(profile)
            let idOptional = try await store.activeProfileID()
            let id = try XCTUnwrap(idOptional)

            let metadataOptional = try await store.activeProfileMetadata()
            let metadata = try XCTUnwrap(metadataOptional)
            XCTAssertEqual(metadata.id, id)
            XCTAssertEqual(metadata.schemaVersion, StyleProfile.currentSchemaVersion)
            XCTAssertEqual(metadata.algorithmVersion, StyleProfile.currentAlgorithmVersion)
            XCTAssertEqual(metadata.pairCount, 8)
            XCTAssertEqual(metadata.confidence, .stable)
            XCTAssertEqual(metadata.tags, profile.tags)
            XCTAssertEqual(metadata.updatedAt, profile.updatedAt)
        }
    }
}
