import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class PersistenceDeletionTests: XCTestCase {
    func testDeleteAllRemovesEveryLocalArtifact() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)

            try await store.save(PersistenceTestSupport.profile())
            _ = try await store.recordEdit(EditDraft(
                inputReference: "edit-ref-1",
                adjustments: ManualAdjustments(exposure: 0.2)
            ))
            _ = try await store.savePairSession(PairSessionDraft(
                pairReferences: ["pair-1", "pair-2", "pair-3"],
                targetPairCount: 3
            ))
            _ = try await store.recordSuccessfulExport()

            try writeFixture(
                Data("thumbnail".utf8),
                to: base.appendingPathComponent("style-thumbnails", isDirectory: true),
                fileName: "thumbnail.jpg"
            )
            try writeFixture(
                Data("{\"schemaVersion\": 1}".utf8),
                to: base.appendingPathComponent("style-profile-migration-backups", isDirectory: true),
                fileName: "backup.json"
            )
            try writeFixture(
                Data("{\"schemaVersion\": 1}".utf8),
                to: base.appendingPathComponent("style-profile-recovery", isDirectory: true),
                fileName: "recovery.json"
            )
            try writeFixture(
                Data("{\"schemaVersion\": 1}".utf8),
                to: base.appendingPathComponent("style-index-recovery", isDirectory: true),
                fileName: "old.store"
            )

            try await store.deleteAll()

            for relativePath in [
                "style-profiles",
                "style-thumbnails",
                "style-profile-migration-backups",
                "style-profile-recovery",
                "style-index-recovery"
            ] {
                let url = base.appendingPathComponent(relativePath, isDirectory: true)
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: url.path),
                    "\(relativePath) should be removed"
                )
            }
            XCTAssertTrue(PersistenceTestSupport.allJSONFiles(in: base).isEmpty)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: base.appendingPathComponent("style-index.store").path
                )
            )

            let active = try await store.loadActive()
            XCTAssertNil(active)
            let edits = try await store.edits()
            XCTAssertTrue(edits.isEmpty)
            let sessions = try await store.pairSessions()
            XCTAssertTrue(sessions.isEmpty)
            let quota = try await store.quota()
            XCTAssertEqual(quota.freeExportsUsed, 0)
            XCTAssertEqual(quota.remainingFreeExports, QuotaSnapshot.freeExportLimit)
        }
    }

    func testDeleteAllSurvivesRestart() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            do {
                let store = PersistenceTestSupport.makeStore(in: directory)
                try await store.save(PersistenceTestSupport.profile())
                _ = try await store.recordSuccessfulExport()
                try await store.deleteAll()
            }

            let reopened = PersistenceTestSupport.makeStore(in: directory)
            let active = try await reopened.loadActive()
            XCTAssertNil(active)
            let quota = try await reopened.quota()
            XCTAssertEqual(quota.freeExportsUsed, 0)
        }
    }

    func testDeleteAllOnFreshStoreIsNoOp() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            try await store.deleteAll()
            let active = try await store.loadActive()
            XCTAssertNil(active)
        }
    }

    func testDeleteAllThenSaveWorks() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            try await store.save(PersistenceTestSupport.profile(pairCount: 3))
            try await store.deleteAll()

            let replacement = PersistenceTestSupport.profile(pairCount: 8, confidence: .stable)
            try await store.save(replacement)
            let loaded = try await store.loadActive()
            XCTAssertEqual(loaded, replacement)
        }
    }

    private func writeFixture(_ data: Data, to directory: URL, fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName))
    }
}
