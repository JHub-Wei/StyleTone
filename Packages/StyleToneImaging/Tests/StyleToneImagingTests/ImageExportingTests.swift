import Foundation
import XCTest
import StyleToneCore
import StyleToneImaging

final class ImageExportingTests: XCTestCase {
    func testExportsJPEGToUniqueFile() async throws {
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = FileImageExporter(directory: directory)
        let asset = try makeAsset()

        let result = try await exporter.export(
            asset,
            options: ExportOptions(format: .jpeg, quality: 0.9)
        )

        XCTAssertEqual(result.format, .jpeg)
        XCTAssertEqual(result.pixelSize, PixelSize(width: 24, height: 18))
        XCTAssertEqual(
            result.url.deletingLastPathComponent().standardizedFileURL,
            directory.standardizedFileURL
        )
        XCTAssertEqual(result.url.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))

        let reloaded = try ImageLoader().decodeImage(contentsOf: result.url)
        XCTAssertEqual(reloaded.pixelSize, PixelSize(width: 24, height: 18))
    }

    func testExportsHEIC() async throws {
        try XCTSkipUnless(TestImage.isHEICEncodingSupported, "HEIC encoding is unavailable")
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = FileImageExporter(directory: directory)
        let asset = try makeAsset()

        let result = try await exporter.export(
            asset,
            options: ExportOptions(format: .heic, quality: 0.9)
        )
        XCTAssertEqual(result.format, .heic)
        XCTAssertEqual(result.url.pathExtension, "heic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))

        let reloaded = try ImageLoader().decodeImage(contentsOf: result.url)
        XCTAssertEqual(reloaded.pixelSize, PixelSize(width: 24, height: 18))
    }

    func testDefaultDirectoryIsTemporary() {
        let exporter = FileImageExporter()
        XCTAssertEqual(
            exporter.directory.lastPathComponent,
            FileImageExporter.defaultDirectoryName
        )
        XCTAssertTrue(
            exporter.directory.standardizedFileURL.path
                .hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path)
        )
    }

    func testRemoveExportedFileIsIdempotent() async throws {
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = FileImageExporter(directory: directory)
        let asset = try makeAsset()
        let result = try await exporter.export(
            asset,
            options: ExportOptions(format: .jpeg, quality: 0.8)
        )

        try exporter.removeExportedFile(at: result.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertNoThrow(try exporter.removeExportedFile(at: result.url))
    }

    func testInvalidDirectoryFails() async throws {
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("not-a-directory")
        try Data([0]).write(to: fileURL)
        let exporter = FileImageExporter(directory: fileURL)
        let asset = try makeAsset()

        do {
            _ = try await exporter.export(
                asset,
                options: ExportOptions(format: .jpeg, quality: 0.9)
            )
            XCTFail("Expected exportFailed")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .exportFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConformsToImageExporting() {
        let exporter: any ImageExporting = FileImageExporter()
        XCTAssertTrue(exporter is FileImageExporter)
    }

    private func makeAsset() throws -> ImageAsset {
        let image = try TestImage.solid(width: 24, height: 18, color: .magenta)
        return ImageAsset(cgImage: image, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
    }
}
