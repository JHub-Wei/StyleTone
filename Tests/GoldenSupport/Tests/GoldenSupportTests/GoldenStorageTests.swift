import Foundation
import XCTest
@testable import GoldenSupport
import StyleToneCore
import TestShared

final class GoldenStorageTests: XCTestCase {
    func testMissingGoldenThrows() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let store = GoldenImageStore(directory: directory)
            XCTAssertThrowsError(try store.loadPixels(named: "missing")) { error in
                XCTAssertEqual(error as? GoldenSupportError, .goldenImageMissing(name: "missing"))
            }
        }
    }

    func testSaveAndLoadRoundTrip() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let store = GoldenImageStore(directory: directory)
            let buffer = try PixelBuffer(width: 6, height: 5, fill: RGB8(red: 1, green: 2, blue: 3))
            try store.save(buffer, named: "round-trip")

            let url = try store.url(for: "round-trip")
            XCTAssertEqual(url.pathExtension, "png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

            let loaded = try store.loadPixels(named: "round-trip")
            XCTAssertEqual(loaded.bytes, buffer.bytes)
        }
    }

    func testCompareIdenticalPassesAndDifferentFails() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let store = GoldenImageStore(directory: directory)
            let golden = try PixelBuffer(width: 8, height: 8, fill: RGB8(gray: 120))
            try store.save(golden, named: "flat")

            let identical = try store.compare(golden, named: "flat", thresholds: .identity)
            XCTAssertTrue(identical.passes)

            var changed = golden
            changed[4, 4] = RGBA8(color: .white)
            let different = try store.compare(changed, named: "flat", thresholds: .identity)
            XCTAssertFalse(different.passes)
            XCTAssertEqual(different.differingPixelCount, 1)
        }
    }

    func testRecordModeWritesAndPasses() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let store = GoldenImageStore(directory: directory, recordMode: true)
            let buffer = try PixelBuffer(width: 4, height: 4, fill: RGB8(red: 10, green: 20, blue: 30))
            let report = try store.compare(buffer, named: "recorded", thresholds: .identity)
            XCTAssertTrue(report.passes)

            let saved = try store.loadPixels(named: "recorded")
            XCTAssertEqual(saved.bytes, buffer.bytes)
        }
    }

    func testInvalidGoldenNamesAreRejected() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let store = GoldenImageStore(directory: directory)
            for name in ["", "  ", "../escape", "a/b", "a\\b", ".hidden"] {
                XCTAssertThrowsError(try store.url(for: name), "name '\(name)'")
            }
        }
    }

    func testArtifactWriterProducesAllFiles() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let expected = try PixelBuffer(width: 8, height: 8, fill: .black)
            var actual = expected
            actual[1, 2] = RGBA8(color: .white)
            let report = try ImageComparator.compare(expected: expected, actual: actual, thresholds: .identity)

            let artifacts = try DiffArtifactWriter.write(
                expected: expected,
                actual: actual,
                report: report,
                name: "case-1",
                to: directory
            )

            for url in [
                artifacts.expectedURL,
                artifacts.actualURL,
                artifacts.differenceURL,
                artifacts.reportURL,
                artifacts.markdownURL
            ] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
            }

            let reportData = try Data(contentsOf: artifacts.reportURL)
            let decoded = try JSONDecoder().decode(ImageDifferenceReport.self, from: reportData)
            XCTAssertEqual(decoded, report)

            let markdown = String(
                decoding: try Data(contentsOf: artifacts.markdownURL),
                as: UTF8.self
            )
            XCTAssertTrue(markdown.contains("FAIL"))
        }
    }
}
