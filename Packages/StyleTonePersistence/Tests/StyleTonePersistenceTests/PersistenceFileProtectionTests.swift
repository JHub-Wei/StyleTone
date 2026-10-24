import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleTonePersistence

final class PersistenceFileProtectionTests: XCTestCase {
    func testAllFileOperationsRunOffTheMainThread() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let recording = RecordingPersistenceFileSystem()
            let store = PersistenceTestSupport.makeStore(
                in: directory,
                fileSystem: recording
            )

            try await store.save(PersistenceTestSupport.profile())
            _ = try await store.loadActive()
            _ = try await store.recordEdit(EditDraft(
                inputReference: "main-thread-reference",
                adjustments: ManualAdjustments()
            ))
            _ = try await store.savePairSession(PairSessionDraft(
                pairReferences: ["a", "b", "c"],
                targetPairCount: 3
            ))
            _ = try await store.recordSuccessfulExport()
            try await store.deleteAll()

            let mainThreadCalls = recording.callsOnMainThread
            XCTAssertTrue(
                mainThreadCalls.isEmpty,
                "Unexpected main-thread operations: \(mainThreadCalls.map(\.kind.rawValue))"
            )
        }
    }

    func testWritesAndDirectoriesRequestCompleteProtection() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let recording = RecordingPersistenceFileSystem()
            let store = PersistenceTestSupport.makeStore(
                in: directory,
                fileSystem: recording
            )

            try await store.save(PersistenceTestSupport.profile())

            let writes = recording.writes
            XCTAssertFalse(writes.isEmpty)
            for operation in writes {
                XCTAssertEqual(operation.protection, .some(.complete))
            }
            XCTAssertTrue(writes.contains {
                $0.url.path.contains("style-profiles") && $0.url.pathExtension == "json"
            })

            let directories = recording.operations.filter { $0.kind == .createDirectory }
            XCTAssertFalse(directories.isEmpty)
            for operation in directories {
                XCTAssertEqual(operation.protection, .some(.complete))
            }

            let storeFileProtections = recording.operations.filter {
                $0.kind == .setProtection
                    && $0.url.lastPathComponent.hasPrefix("style-index.store")
            }
            XCTAssertFalse(storeFileProtections.isEmpty)
            for operation in storeFileProtections {
                XCTAssertEqual(operation.protection, .some(.complete))
            }
        }
    }

    func testCustomProtectionClassIsPropagated() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let recording = RecordingPersistenceFileSystem()
            let configuration = PersistenceConfiguration(
                baseDirectory: PersistenceTestSupport.baseDirectory(in: directory),
                fileProtection: .completeUntilFirstUserAuthentication
            )
            let store = SwiftDataStyleProfileStore(
                configuration: configuration,
                fileSystem: recording,
                dateProvider: FixedDateProvider()
            )

            try await store.save(PersistenceTestSupport.profile())

            XCTAssertFalse(recording.writes.isEmpty)
            for operation in recording.writes {
                XCTAssertEqual(operation.protection, .some(.completeUntilFirstUserAuthentication))
            }
            let directories = recording.operations.filter { $0.kind == .createDirectory }
            for operation in directories {
                XCTAssertEqual(operation.protection, .some(.completeUntilFirstUserAuthentication))
            }
        }
    }

    #if os(iOS)
    func testProfileFileCarriesCompleteProtectionAttribute() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync { directory -> Void in
            let store = PersistenceTestSupport.makeStore(in: directory)
            let base = PersistenceTestSupport.baseDirectory(in: directory)
            try await store.save(PersistenceTestSupport.profile())

            let files = PersistenceTestSupport.profileFiles(in: base)
            let attributes = try FileManager.default.attributesOfItem(atPath: files[0].path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            XCTAssertEqual(protection?.rawValue, FileProtectionType.complete.rawValue)
        }
    }
    #endif
}
