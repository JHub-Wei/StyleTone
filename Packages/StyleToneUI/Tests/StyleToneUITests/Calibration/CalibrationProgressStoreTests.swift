import Foundation
import XCTest
import StyleToneCore
import TestShared
@testable import StyleToneUI

final class CalibrationProgressStoreTests: XCTestCase {
    func testSaveLoadAndClearRoundTrip() async throws {
        let directory = try TemporaryDirectory(prefix: "CalibrationProgress")
        defer { directory.remove() }

        let store = FileCalibrationProgressStore(directoryURL: directory.url)
        let profile = MockStyleProfileFactory.trial()
        let draft = CalibrationDraft(
            revision: 4,
            phase: .result,
            selectedPairCount: 3,
            trainingPairIDs: [UUID()],
            answers: [CalibrationAnswer(dimension: .tone, choseA: true, strengthDelta: -0.35)],
            comparisonIndex: 6,
            skippedComparisonCount: 1,
            profile: profile,
            updatedAt: FixedDateProvider.reference
        )

        let initial = try await store.loadDraft()
        XCTAssertNil(initial)

        try await store.saveDraft(draft)
        let loaded = try await store.loadDraft()
        XCTAssertEqual(loaded, draft)

        try await store.clearDraft()
        let afterClear = try await store.loadDraft()
        XCTAssertNil(afterClear)
    }

    func testCorruptDraftIsReportedWithoutDeletingFile() async throws {
        let directory = try TemporaryDirectory(prefix: "CalibrationCorrupt")
        defer { directory.remove() }

        let fileURL = directory.url.appendingPathComponent("calibration-progress.json")
        try Data("{not-json".utf8).write(to: fileURL)

        let store = FileCalibrationProgressStore(directoryURL: directory.url)
        do {
            _ = try await store.loadDraft()
            XCTFail("Expected corrupted error")
        } catch let error as CalibrationProgressStoreError {
            XCTAssertEqual(error, .corrupted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testInMemoryStoreRejectsLateOlderRevision() async throws {
        let store = CalibrationInMemoryProgressStore()
        let first = CalibrationDraft(revision: 1, phase: .pairs)
        let second = CalibrationDraft(revision: 2, phase: .comparisons)

        try await store.saveDraft(second)
        try await store.saveDraft(first)
        let stored = await store.storedDraft
        XCTAssertEqual(stored, second)
    }
}
