import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class StyleProfileCorruptionTests: XCTestCase {
    func testCorruptActiveProfileIsReportedAndRetained() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let store = PersistenceTestSupport.makeStore(in: directory)
            let profile = PersistenceTestSupport.profile()
            try await store.save(profile)

            let files = PersistenceTestSupport.profileFiles(in: base)
            XCTAssertEqual(files.count, 1)
            let corrupted = Data("{ definitely not profile json".utf8)
            try corrupted.write(to: files[0])

            let reopened = PersistenceTestSupport.makeStore(in: directory)
            let error = await capturePersistenceError { try await reopened.loadActive() }

            XCTAssertEqual(error, .profileCorrupt)
            XCTAssertEqual(error?.recovery, AppError.Recovery.recalibrate)
            XCTAssertEqual(try Data(contentsOf: files[0]), corrupted)
        }
    }

    func testQuarantineActiveProfileAllowsRecalibration() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let store = PersistenceTestSupport.makeStore(in: directory)
            try await store.save(PersistenceTestSupport.profile())
            let files = PersistenceTestSupport.profileFiles(in: base)
            XCTAssertEqual(files.count, 1)
            try Data("broken".utf8).write(to: files[0])

            let quarantined = try await store.quarantineActiveProfile()
            XCTAssertTrue(quarantined)

            let recoveryDirectory = base.appendingPathComponent(
                "style-profile-recovery",
                isDirectory: true
            )
            let recovered = PersistenceTestSupport.files(in: recoveryDirectory)
            XCTAssertEqual(recovered.count, 1)
            XCTAssertEqual(try Data(contentsOf: recovered[0]), Data("broken".utf8))

            XCTAssertTrue(PersistenceTestSupport.profileFiles(in: base).isEmpty)
            let loaded = try await store.loadActive()
            XCTAssertNil(loaded)

            let replacement = PersistenceTestSupport.profile(pairCount: 3, confidence: .trial)
            try await store.save(replacement)
            let reloaded = try await store.loadActive()
            XCTAssertEqual(reloaded, replacement)
        }
    }

    func testQuarantineWithoutActiveProfileReturnsFalse() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let quarantined = try await store.quarantineActiveProfile()
            XCTAssertFalse(quarantined)
        }
    }

    func testCorruptSwiftDataIndexIsQuarantinedAndProfileRebuilt() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let profile = PersistenceTestSupport.profile(pairCount: 5)
            let profileURL = try PersistenceTestSupport.writeProfile(profile, in: base)
            let profileData = try Data(contentsOf: profileURL)

            let indexURL = base.appendingPathComponent("style-index.store", isDirectory: false)
            try Data("this is not a sqlite database".utf8).write(to: indexURL)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loadedOptional = try await store.loadActive()
            let loaded = try XCTUnwrap(loadedOptional)

            XCTAssertEqual(loaded, profile)
            XCTAssertEqual(try Data(contentsOf: profileURL), profileData)

            let recoveredIndexes = PersistenceTestSupport.files(
                in: base.appendingPathComponent("style-index-recovery", isDirectory: true)
            )
            XCTAssertFalse(recoveredIndexes.isEmpty)

            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)
        }
    }

    func testMissingSwiftDataIndexRebuildsFromJSON() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let profile = PersistenceTestSupport.profile(pairCount: 3, confidence: .trial)
            try PersistenceTestSupport.writeProfile(profile, in: base)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded, profile)
            let id = try await store.activeProfileID()
            XCTAssertNotNil(id)
        }
    }

    func testMultipleProfileFilesChooseMostRecentValidProfile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let older = PersistenceTestSupport.profile(
                pairCount: 3,
                confidence: .trial,
                updatedAt: PersistenceTestSupport.referenceDate.addingTimeInterval(-600)
            )
            let newer = PersistenceTestSupport.profile(
                pairCount: 8,
                confidence: .stable,
                updatedAt: PersistenceTestSupport.referenceDate
            )
            try PersistenceTestSupport.writeProfile(older, in: base)
            try PersistenceTestSupport.writeProfile(newer, in: base)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded, newer)
        }
    }

    func testValidProfileSurvivesCorruptSiblingDuringRebuild() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            let profile = PersistenceTestSupport.profile()
            try PersistenceTestSupport.writeProfile(profile, in: base)
            try PersistenceTestSupport.writeProfileJSON("{broken", in: base)

            let store = PersistenceTestSupport.makeStore(in: directory)
            let loaded = try await store.loadActive()

            XCTAssertEqual(loaded, profile)
        }
    }
}
