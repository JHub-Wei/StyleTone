import CoreGraphics
import Foundation
import ImageIO
import XCTest
import StyleToneCore
import StyleToneImaging

final class ImageWriterTests: XCTestCase {
    private let writer = ImageWriter()

    // MARK: - Formats and profiles

    func testWritesJPEGWithSRGBColorProfile() throws {
        let asset = try makeAsset(color: .red, width: 32, height: 24)
        let data = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 1.0, colorSpace: .sRGB)
        )

        let decoded = try TestImage.decode(data)
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 24)
        XCTAssertEqual(try decodedColorSpace(decoded), .sRGB)

        let pixels = try TestImage.pixels(of: decoded)
        let color = TestImage.rgba(pixels, width: 32, x: 16, y: 12)
        XCTAssertGreaterThanOrEqual(color.0, 220)
        XCTAssertLessThanOrEqual(color.1, 40)
        XCTAssertLessThanOrEqual(color.2, 40)

        let properties = try XCTUnwrap(TestImage.properties(of: data))
        if let profileName = properties[kCGImagePropertyProfileName] as? String {
            XCTAssertTrue(profileName.localizedCaseInsensitiveContains("sRGB"))
        }
    }

    func testWritesHEICWithSRGBColorProfile() throws {
        try XCTSkipUnless(TestImage.isHEICEncodingSupported, "HEIC encoding is unavailable")
        let asset = try makeAsset(color: .green, width: 32, height: 24)
        let data = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .heic, quality: 1.0, colorSpace: .sRGB)
        )

        let decoded = try TestImage.decode(data)
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 24)
        XCTAssertEqual(try decodedColorSpace(decoded), .sRGB)

        let pixels = try TestImage.pixels(of: decoded)
        let color = TestImage.rgba(pixels, width: 32, x: 16, y: 12)
        XCTAssertLessThanOrEqual(color.0, 40)
        XCTAssertGreaterThanOrEqual(color.1, 220)
        XCTAssertLessThanOrEqual(color.2, 40)
    }

    func testWritesDisplayP3Profile() throws {
        let source = try TestImage.solid(
            width: 32,
            height: 24,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let asset = ImageAsset(
            cgImage: source,
            colorSpace: ImageColorSpace.displayP3.cgColorSpace
        )
        let data = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 1.0, colorSpace: .displayP3)
        )

        let decoded = try TestImage.decode(data)
        XCTAssertEqual(try decodedColorSpace(decoded), .displayP3)
        let properties = try XCTUnwrap(TestImage.properties(of: data))
        if let profileName = properties[kCGImagePropertyProfileName] as? String {
            XCTAssertTrue(profileName.localizedCaseInsensitiveContains("P3"))
        }
    }

    func testWritesSRGBWhenSourceIsDisplayP3() throws {
        let source = try TestImage.solid(
            width: 32,
            height: 24,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let asset = ImageAsset(
            cgImage: source,
            colorSpace: ImageColorSpace.displayP3.cgColorSpace
        )
        let data = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 1.0, colorSpace: .sRGB)
        )

        let decoded = try TestImage.decode(data)
        XCTAssertEqual(try decodedColorSpace(decoded), .sRGB)
    }

    // MARK: - Metadata

    func testOutputHasNoGPSMetadata() async throws {
        let source = try TestImage.solid(width: 48, height: 36, color: .cyan)
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 31.2304,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 121.4737,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]
        let input = try TestImage.encode(
            source,
            format: "public.jpeg",
            quality: 1.0,
            metadata: [kCGImagePropertyGPSDictionary: gps]
        )
        let inputProperties = try XCTUnwrap(TestImage.properties(of: input))
        XCTAssertNotNil(inputProperties[kCGImagePropertyGPSDictionary])

        let asset = try await ImageLoader().load(data: input)
        let output = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 0.9)
        )
        let outputProperties = try XCTUnwrap(TestImage.properties(of: output))
        XCTAssertNil(outputProperties[kCGImagePropertyGPSDictionary])
    }

    // MARK: - Quality and alpha

    func testQualityAffectsJPEGFileSize() throws {
        var state: UInt32 = 0x1234_5678
        let source = try TestImage.image(width: 128, height: 128, colorSpace: TestImage.sRGB) { _, _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(truncatingIfNeeded: state >> 16)
            return SIMD4<UInt8>(value, value &+ 31, value &* 3, 255)
        }
        let asset = ImageAsset(cgImage: source, colorSpace: ImageColorSpace.sRGB.cgColorSpace)

        let low = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 0.3)
        )
        let high = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 0.95)
        )
        XCTAssertLessThan(low.count, high.count)
    }

    func testFlattensAlphaOverWhite() throws {
        let source = try TestImage.image(width: 16, height: 16, colorSpace: TestImage.sRGB) { _, _ in
            // Premultiplied 50% red.
            SIMD4<UInt8>(128, 0, 0, 128)
        }
        let asset = ImageAsset(cgImage: source, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
        let data = try writer.data(
            for: asset,
            options: ImageWriteOptions(format: .jpeg, quality: 1.0)
        )
        let decoded = try TestImage.decode(data)
        let pixels = try TestImage.pixels(of: decoded)
        let color = TestImage.rgba(pixels, width: 16, x: 8, y: 8)
        XCTAssertGreaterThanOrEqual(color.0, 235)
        XCTAssertEqual(Double(color.1), 128, accuracy: 30)
        XCTAssertEqual(Double(color.2), 128, accuracy: 30)
        XCTAssertEqual(color.3, 255)
    }

    // MARK: - Files

    func testWritesFileAndReturnsResult() throws {
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("export.jpg")
        let asset = try makeAsset(color: .blue, width: 20, height: 15)

        let result = try writer.write(asset, to: url, using: ExportOptions(format: .jpeg, quality: 0.9))
        XCTAssertEqual(result.url, url)
        XCTAssertEqual(result.pixelSize, PixelSize(width: 20, height: 15))
        XCTAssertEqual(result.format, .jpeg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reloaded = try ImageLoader().decodeImage(contentsOf: url)
        XCTAssertEqual(reloaded.pixelSize, PixelSize(width: 20, height: 15))
    }

    func testWriteToMissingDirectoryFails() throws {
        let directory = try TestImage.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("export.jpg")
        let asset = try makeAsset(color: .white, width: 8, height: 8)

        do {
            _ = try writer.write(asset, to: url)
            XCTFail("Expected exportFailed")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .exportFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFormatSupportMatchesImageIO() {
        XCTAssertTrue(writer.isFormatSupported(.jpeg))
        XCTAssertEqual(
            writer.isFormatSupported(.heic),
            TestImage.isHEICEncodingSupported
        )
    }

    // MARK: - Helpers

    private func makeAsset(color: TestColor, width: Int, height: Int) throws -> ImageAsset {
        let image = try TestImage.solid(width: width, height: height, color: color)
        return ImageAsset(cgImage: image, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
    }

    private func decodedColorSpace(_ image: CGImage) throws -> ImageColorSpace {
        let space = try XCTUnwrap(image.colorSpace)
        return ImageColorSpace.detect(space)
    }
}
