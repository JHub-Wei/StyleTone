import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class PersistenceConcurrencyTests: XCTestCase {
    func testConcurrentSavesLeaveOneActiveProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<20 {
                    group.addTask {
                        try await store.save(PersistenceTestSupport.profile(
                            pairCount: 3 + index,
                            confidence: .standard,
                            updatedAt: PersistenceTestSupport.referenceDate
                                .addingTimeInterval(Double(index))
                        ))
                    }
                }
                try await group.waitForAll()
            }

            let loaded = try await store.loadActive()
            XCTAssertNotNil(loaded)
            XCTAssertTrue((3...22).contains(loaded?.pairCount ?? -1))
            XCTAssertEqual(PersistenceTestSupport.profileFiles(in: base).count, 1)
            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)
        }
    }

    func testConcurrentLoadsDuringSavesNeverFail() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            try await store.save(PersistenceTestSupport.profile(pairCount: 3, confidence: .trial))

            var loadedProfiles: [StyleProfile] = []
            try await withThrowingTaskGroup(of: StyleProfile?.self) { group in
                for index in 0..<24 {
                    group.addTask {
                        if index % 2 == 0 {
                            try await store.save(PersistenceTestSupport.profile(
                                pairCount: 3 + index,
                                confidence: .standard,
                                updatedAt: PersistenceTestSupport.referenceDate
                                    .addingTimeInterval(Double(index))
                            ))
                            return nil
                        }
                        return try await store.loadActive()
                    }
                }

                for try await profile in group {
                    if let profile {
                        loadedProfiles.append(profile)
                    }
                }
            }

            XCTAssertFalse(loadedProfiles.isEmpty)
            for profile in loadedProfiles {
                XCTAssertTrue((3...26).contains(profile.pairCount))
                XCTAssertEqual(profile.schemaVersion, StyleProfile.currentSchemaVersion)
            }
        }
    }

    func testConcurrentQuotaIncrementsAreSerialized() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<40 {
                    group.addTask {
                        _ = try await store.recordSuccessfulExport()
                    }
                }
                try await group.waitForAll()
            }

            let quota = try await store.quota()
            XCTAssertEqual(quota.freeExportsUsed, 40)
            XCTAssertEqual(quota.remainingFreeExports, 0)
        }
    }

    func testConcurrentEditsAllPersist() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let ids = try await withThrowingTaskGroup(of: UUID.self) { group -> [UUID] in
                for index in 0..<20 {
                    group.addTask {
                        let snapshot = try await store.recordEdit(EditDraft(
                            inputReference: "concurrent-\(index)",
                            adjustments: ManualAdjustments(exposure: Double(index) / 100)
                        ))
                        return snapshot.id
                    }
                }
                var collected: [UUID] = []
                for try await id in group {
                    collected.append(id)
                }
                return collected
            }

            XCTAssertEqual(ids.count, 20)
            XCTAssertEqual(Set(ids).count, 20)
            let edits = try await store.edits(limit: 100)
            XCTAssertEqual(edits.count, 20)
            XCTAssertEqual(Set(edits.map(\.id)), Set(ids))
        }
    }

    func testConcurrentReadsSeeCompletedWrites() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let profile = PersistenceTestSupport.profile(pairCount: 8, confidence: .stable)
            try await store.save(profile)

            try await withThrowingTaskGroup(of: StyleProfile?.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        try await store.loadActive()
                    }
                }
                for try await loaded in group {
                    XCTAssertEqual(loaded, profile)
                }
            }
        }
    }
}
