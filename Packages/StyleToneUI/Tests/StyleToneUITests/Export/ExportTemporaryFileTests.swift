import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Temporary-file lifecycle: immediate deletion helpers plus the crash-only
/// stale sweep. No test touches the real photo library or the user's files.
final class ExportTemporaryFileTests: XCTestCase {
    func testDefaultDirectoryMatchesTheImagingLayout() {
        let store = ExportTemporaryFileStore()
        XCTAssertEqual(
            ExportTemporaryFileStore.directoryName,
            "StyleToneExports"
        )
        XCTAssertEqual(store.directory.lastPathComponent, "StyleToneExports")
        XCTAssertEqual(
            store.directory,
            FileManager.default.temporaryDirectory
                .appendingPathComponent("StyleToneExports", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(store.staleAfter, ExportAcceptance.staleTemporaryFileAge)
    }

    func testRemoveStaleFilesRemovesOnlyOldRegularFiles() throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportStale")
        defer { temp.remove() }

        let oldFile = temp.url.appendingPathComponent("old.heic")
        let freshFile = temp.url.appendingPathComponent("fresh.jpg")
        try Data(repeating: 0x11, count: 128).write(to: oldFile)
        try Data(repeating: 0x22, count: 64).write(to: freshFile)

        let earlier = Date(timeIntervalSinceNow: -3_600)
        try FileManager.default.setAttributes(
            [.modificationDate: earlier],
            ofItemAtPath: oldFile.path
        )

        let nested = temp.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedFile = nested.appendingPathComponent("keep.heic")
        try Data().write(to: nestedFile)

        let store = ExportTemporaryFileStore(directory: temp.url, staleAfter: 600)
        let removed = store.removeStaleFiles(now: Date())

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
    }

    func testRemoveRefusesFilesOutsideTheExportDirectory() throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportInside")
        defer { temp.remove() }
        let outside = try TemporaryDirectory(prefix: "StyleToneExportOutside")
        defer { outside.remove() }

        let file = outside.url.appendingPathComponent("do-not-touch.heic")
        try Data(repeating: 0x33, count: 8).write(to: file)

        let store = ExportTemporaryFileStore(directory: temp.url, staleAfter: 600)
        XCTAssertFalse(store.contains(file))
        XCTAssertFalse(store.fileExists(at: file))
        XCTAssertFalse(store.remove(file))
        XCTAssertEqual(store.byteCount(of: file), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRemoveIsIdempotentAndByteCountReadsTheFile() throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportRemove")
        defer { temp.remove() }

        let file = temp.url.appendingPathComponent("export.heic")
        try Data(repeating: 0x44, count: 1_024).write(to: file)

        let store = ExportTemporaryFileStore(directory: temp.url, staleAfter: 600)
        XCTAssertTrue(store.fileExists(at: file))
        XCTAssertEqual(store.byteCount(of: file), 1_024)
        XCTAssertTrue(store.remove(file))
        XCTAssertFalse(store.fileExists(at: file))
        XCTAssertTrue(store.remove(file))
        XCTAssertEqual(store.byteCount(of: file), 0)
    }

    func testStaleSweepIgnoresAMissingDirectory() throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportMissingDir")
        let directory = temp.url.appendingPathComponent("not-created", isDirectory: true)
        defer { temp.remove() }

        let store = ExportTemporaryFileStore(directory: directory, staleAfter: 1)
        XCTAssertEqual(store.removeStaleFiles(now: Date()), 0)
    }
}
