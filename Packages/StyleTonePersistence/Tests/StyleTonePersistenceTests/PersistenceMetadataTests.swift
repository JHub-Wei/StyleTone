import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class PersistenceMetadataTests: XCTestCase {
    // MARK: - Edits

    func testEditHistoryIsOrderedAndLimited() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let clock = AdjustableTestClock()
            let store = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
            var identities: [UUID] = []

            for index in 0..<3 {
                clock.advance(by: 60)
                let snapshot = try await store.recordEdit(EditDraft(
                    inputReference: "reference-\(index)",
                    adjustments: ManualAdjustments(exposure: Double(index) / 10)
                ))
                identities.append(snapshot.id)
                XCTAssertEqual(snapshot.exported, false)
            }

            let all = try await store.edits()
            XCTAssertEqual(all.count, 3)
            XCTAssertEqual(all.map(\.id), Array(identities.reversed()))
            XCTAssertEqual(all[0].adjustments.exposure, 0.2)

            let limited = try await store.edits(limit: 2)
            XCTAssertEqual(limited.count, 2)
            XCTAssertEqual(limited.map(\.id), [identities[2], identities[1]])

            let none = try await store.edits(limit: 0)
            XCTAssertTrue(none.isEmpty)
        }
    }

    func testMarkEditExportedAndDelete() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let clock = AdjustableTestClock()
            let store = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
            let snapshot = try await store.recordEdit(EditDraft(
                inputReference: "reference-export",
                adjustments: ManualAdjustments(grain: 0.2),
                styleID: UUID()
            ))

            clock.advance(by: 30)
            try await store.markEditExported(id: snapshot.id)

            let exported = try await store.edits()
            XCTAssertEqual(exported.count, 1)
            XCTAssertTrue(exported[0].exported)
            XCTAssertNotNil(exported[0].exportedAt)

            try await store.markEditExported(id: snapshot.id)
            let stillOneTimestamp = try await store.edits()
            XCTAssertEqual(stillOneTimestamp[0].exportedAt, exported[0].exportedAt)

            try await store.deleteEdit(id: snapshot.id)
            let empty = try await store.edits()
            XCTAssertTrue(empty.isEmpty)

            // Deleting a missing edit is idempotent.
            try await store.deleteEdit(id: UUID())
        }
    }

    func testMarkMissingEditThrows() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError {
                try await store.markEditExported(id: UUID())
            }
            XCTAssertEqual(error, .recordNotFound)
        }
    }

    func testRecordEditRejectsEmptyReference() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError {
                try await store.recordEdit(EditDraft(
                    inputReference: "   ",
                    adjustments: ManualAdjustments()
                ))
            }
            XCTAssertEqual(error, .invalidRecord)
            let edits = try await store.edits()
            XCTAssertTrue(edits.isEmpty)
        }
    }

    func testDeleteAllEdits() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            for index in 0..<3 {
                _ = try await store.recordEdit(EditDraft(
                    inputReference: "reference-\(index)",
                    adjustments: ManualAdjustments()
                ))
            }
            try await store.deleteAllEdits()
            let edits = try await store.edits()
            XCTAssertTrue(edits.isEmpty)
        }
    }

    // MARK: - Pair sessions

    func testPairSessionCreateUpdateAndDelete() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let clock = AdjustableTestClock()
            let store = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
            let draft = PairSessionDraft(
                pairReferences: ["pair-1", "pair-2", "pair-3"],
                targetPairCount: 3
            )
            let created = try await store.savePairSession(draft)
            XCTAssertEqual(created.pairCount, 3)
            XCTAssertEqual(created.status, .draft)
            XCTAssertEqual(created.createdAt, created.updatedAt)

            clock.advance(by: 60)
            let updated = try await store.savePairSession(PairSessionDraft(
                id: created.id,
                pairReferences: ["pair-1", "pair-2", "pair-3", "pair-4", "pair-5"],
                targetPairCount: 5,
                abChoiceCount: 4,
                status: .completed
            ))
            XCTAssertEqual(updated.id, created.id)
            XCTAssertEqual(updated.pairCount, 5)
            XCTAssertEqual(updated.status, .completed)
            XCTAssertEqual(updated.createdAt, created.createdAt)
            XCTAssertGreaterThan(updated.updatedAt, created.updatedAt)

            let latest = try await store.latestPairSession()
            XCTAssertEqual(latest, updated)

            let sessions = try await store.pairSessions()
            XCTAssertEqual(sessions.count, 1)

            try await store.deletePairSession(id: created.id)
            let remaining = try await store.pairSessions()
            XCTAssertTrue(remaining.isEmpty)
        }
    }

    func testLatestPairSessionPrefersNewestAndSupportsLimit() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let clock = AdjustableTestClock()
            let store = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
            clock.advance(by: 10)
            _ = try await store.savePairSession(PairSessionDraft(
                pairReferences: ["a", "b", "c"],
                targetPairCount: 3
            ))
            clock.advance(by: 10)
            let newest = try await store.savePairSession(PairSessionDraft(
                pairReferences: ["d", "e", "f", "g", "h"],
                targetPairCount: 5
            ))

            let latest = try await store.latestPairSession()
            XCTAssertEqual(latest?.id, newest.id)
            let limited = try await store.pairSessions(limit: 1)
            XCTAssertEqual(limited.count, 1)
            XCTAssertEqual(limited[0].id, newest.id)
        }
    }

    func testPairSessionValidation() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let invalidTarget = await capturePersistenceError {
                try await store.savePairSession(PairSessionDraft(
                    pairReferences: ["a", "b", "c"],
                    targetPairCount: 9
                ))
            }
            XCTAssertEqual(invalidTarget, .invalidRecord)

            let invalidChoices = await capturePersistenceError {
                try await store.savePairSession(PairSessionDraft(
                    pairReferences: ["a", "b", "c"],
                    targetPairCount: 3,
                    abChoiceCount: -1
                ))
            }
            XCTAssertEqual(invalidChoices, .invalidRecord)
        }
    }

    func testDeleteAllPairSessions() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            for target in [3, 5, 8] {
                _ = try await store.savePairSession(PairSessionDraft(
                    pairReferences: ["a", "b", "c"],
                    targetPairCount: target
                ))
            }
            try await store.deleteAllPairSessions()
            let sessions = try await store.pairSessions()
            XCTAssertTrue(sessions.isEmpty)
        }
    }

    // MARK: - Quota

    func testQuotaLifecycle() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)

            let initial = try await store.quota()
            XCTAssertEqual(initial.freeExportsUsed, 0)
            XCTAssertEqual(initial.remainingFreeExports, QuotaSnapshot.freeExportLimit)
            XCTAssertTrue(initial.isFreeExportAvailable)

            let first = try await store.recordSuccessfulExport()
            XCTAssertEqual(first.freeExportsUsed, 1)
            XCTAssertEqual(first.remainingFreeExports, 2)

            _ = try await store.recordSuccessfulExport()
            let third = try await store.recordSuccessfulExport()
            XCTAssertEqual(third.freeExportsUsed, 3)
            XCTAssertEqual(third.remainingFreeExports, 0)
            XCTAssertFalse(third.isFreeExportAvailable)

            let reset = try await store.resetQuota()
            XCTAssertEqual(reset.freeExportsUsed, 0)
            XCTAssertEqual(reset.remainingFreeExports, 3)
        }
    }

    func testResetWithoutQuotaRowIsSafe() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let reset = try await store.resetQuota()
            XCTAssertEqual(reset.freeExportsUsed, 0)
            let quota = try await store.quota()
            XCTAssertEqual(quota.freeExportsUsed, 0)
        }
    }

    // MARK: - Restart

    func testMetadataPersistsAcrossStoreInstances() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let clock = AdjustableTestClock()
            let editID: UUID
            let sessionID: UUID
            do {
                let store = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
                let edit = try await store.recordEdit(EditDraft(
                    inputReference: "restart-reference",
                    adjustments: ManualAdjustments(exposure: 0.4)
                ))
                editID = edit.id
                let session = try await store.savePairSession(PairSessionDraft(
                    pairReferences: ["x", "y", "z"],
                    targetPairCount: 3
                ))
                sessionID = session.id
                _ = try await store.recordSuccessfulExport()
            }

            let reopened = PersistenceTestSupport.makeStore(in: directory, dateProvider: clock)
            let edits = try await reopened.edits()
            XCTAssertEqual(edits.map(\.id), [editID])
            XCTAssertEqual(edits[0].adjustments.exposure, 0.4)
            let latest = try await reopened.latestPairSession()
            XCTAssertEqual(latest?.id, sessionID)
            let quota = try await reopened.quota()
            XCTAssertEqual(quota.freeExportsUsed, 1)
        }
    }
}
