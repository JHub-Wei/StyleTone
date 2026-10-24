import CoreGraphics
import Foundation
import ImageIO
import XCTest
import StyleToneCore
import StyleToneImaging

final class ImageLoaderTests: XCTestCase {
    private let loader = ImageLoader()

    // MARK: - Formats

    func testLoadsPNG() async throws {
        let source = try TestImage.solid(width: 9, height: 7, color: .red)
        let data = try TestImage.encode(source, format: "public.png")
        let image = try await loader.load(data: data)

        XCTAssertEqual(image.pixelSize, PixelSize(width: 9, height: 7))
        let pixels = try TestImage.pixels(of: image.cgImage)
        let color = TestImage.rgba(pixels, width: 9, x: 4, y: 3)
        XCTAssertEqual(color.0, 255)
        XCTAssertLessThanOrEqual(color.1, 2)
        XCTAssertLessThanOrEqual(color.2, 2)
        XCTAssertEqual(color.3, 255)
    }

    func testLoadsJPEG() async throws {
        let source = try TestImage.solid(width: 32, height: 24, color: .blue)
        let data = try TestImage.encode(source, format: "public.jpeg", quality: 1.0)
        let image = try await loader.load(data: data)

        XCTAssertEqual(image.pixelSize, PixelSize(width: 32, height: 24))
        let pixels = try TestImage.pixels(of: image.cgImage)
        let color = TestImage.rgba(pixels, width: 32, x: 16, y: 12)
        XCTAssertLessThanOrEqual(color.0, 30)
        XCTAssertLessThanOrEqual(color.1, 30)
        XCTAssertGreaterThanOrEqual(color.2, 220)
    }

    func testLoadsHEIC() async throws {
        try XCTSkipUnless(TestImage.isHEICEncodingSupported, "HEIC encoding is unavailable")
        let source = try TestImage.solid(width: 32, height: 24, color: .green)
        let data = try TestImage.encode(source, format: "public.heic", quality: 1.0)
        let image = try await loader.load(data: data)

        XCTAssertEqual(image.pixelSize, PixelSize(width: 32, height: 24))
        let pixels = try TestImage.pixels(of: image.cgImage)
        let color = TestImage.rgba(pixels, width: 32, x: 16, y: 12)
        XCTAssertLessThanOrEqual(color.0, 30)
        XCTAssertGreaterThanOrEqual(color.1, 220)
        XCTAssertLessThanOrEqual(color.2, 30)
    }

    func testPreservesDisplayP3Input() async throws {
        let source = try TestImage.solid(
            width: 32,
            height: 24,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let data = try TestImage.encode(source, format: "public.jpeg", quality: 1.0)
        let image = try await loader.load(data: data)

        XCTAssertEqual(ImageColorSpace.detect(image.colorSpace), .displayP3)
        let pixels = try TestImage.pixels(of: image.cgImage)
        let color = TestImage.rgba(pixels, width: 32, x: 16, y: 12)
        XCTAssertGreaterThanOrEqual(color.0, 220)
        XCTAssertLessThanOrEqual(color.1, 60)
        XCTAssertLessThanOrEqual(color.2, 60)
    }

    func testForcesSRGBWhenRequested() async throws {
        let source = try TestImage.solid(
            width: 32,
            height: 24,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let data = try TestImage.encode(source, format: "public.jpeg", quality: 1.0)
        let options = ImageLoadOptions(targetColorSpace: .sRGB)
        let image = try await loader.load(data: data, options: options)

        XCTAssertEqual(ImageColorSpace.detect(image.colorSpace), .sRGB)
    }

    // MARK: - Orientation

    func testAppliesExifOrientationUpMirrored() async throws {
        let stored = try makeOrientationFixture()
        let data = try TestImage.encode(
            stored,
            format: "public.jpeg",
            orientation: .upMirrored,
            quality: 1.0
        )
        let image = try await loader.load(data: data)
        XCTAssertEqual(image.pixelSize, PixelSize(width: 80, height: 40))

        let pixels = try TestImage.pixels(of: image.cgImage)
        let expected: [[TestColor]] = [
            [.white, .blue, .green, .red],
            [.black, .magenta, .cyan, .yellow]
        ]
        assertBlocks(pixels, width: 80, height: 40, columns: 4, rows: 2, expected: expected)
    }

    func testAppliesExifOrientationRight() async throws {
        let stored = try makeOrientationFixture()
        let data = try TestImage.encode(
            stored,
            format: "public.jpeg",
            orientation: .right,
            quality: 1.0
        )
        let image = try await loader.load(data: data)
        XCTAssertEqual(image.pixelSize, PixelSize(width: 40, height: 80))

        let pixels = try TestImage.pixels(of: image.cgImage)
        let expected: [[TestColor]] = [
            [.yellow, .red],
            [.cyan, .green],
            [.magenta, .blue],
            [.black, .white]
        ]
        assertBlocks(pixels, width: 40, height: 80, columns: 2, rows: 4, expected: expected)
    }

    func testAppliesExifOrientationDown() async throws {
        let stored = try makeOrientationFixture()
        let data = try TestImage.encode(
            stored,
            format: "public.jpeg",
            orientation: .down,
            quality: 1.0
        )
        let image = try await loader.load(data: data)
        XCTAssertEqual(image.pixelSize, PixelSize(width: 80, height: 40))

        let pixels = try TestImage.pixels(of: image.cgImage)
        let expected: [[TestColor]] = [
            [.black, .magenta, .cyan, .yellow],
            [.white, .blue, .green, .red]
        ]
        assertBlocks(pixels, width: 80, height: 40, columns: 4, rows: 2, expected: expected)
    }

    func testAppliesExifOrientationLeft() async throws {
        let stored = try makeOrientationFixture()
        let data = try TestImage.encode(
            stored,
            format: "public.jpeg",
            orientation: .left,
            quality: 1.0
        )
        let image = try await loader.load(data: data)
        XCTAssertEqual(image.pixelSize, PixelSize(width: 40, height: 80))

        let pixels = try TestImage.pixels(of: image.cgImage)
        let expected: [[TestColor]] = [
            [.white, .black],
            [.blue, .magenta],
            [.green, .cyan],
            [.red, .yellow]
        ]
        assertBlocks(pixels, width: 40, height: 80, columns: 2, rows: 4, expected: expected)
    }

    // MARK: - Downsampling

    func testDownsamplesPreviewPreservingAspectRatio() async throws {
        let source = try TestImage.solid(width: 400, height: 300, color: .red)
        let data = try TestImage.encode(source, format: "public.png")
        let options = ImageLoadOptions(maximumLongEdge: 100)
        let image = try await loader.load(data: data, options: options)

        XCTAssertEqual(image.pixelSize, PixelSize(width: 100, height: 75))
        let aspect = Double(image.width) / Double(image.height)
        XCTAssertEqual(aspect, 4.0 / 3.0, accuracy: 0.01)
    }

    func testDownsampleAppliesOrientationBeforeSizing() async throws {
        let source = try TestImage.solid(width: 400, height: 300, color: .red)
        let data = try TestImage.encode(
            source,
            format: "public.jpeg",
            orientation: .right,
            quality: 1.0
        )
        let options = ImageLoadOptions(maximumLongEdge: 100)
        let image = try await loader.load(data: data, options: options)

        XCTAssertEqual(image.pixelSize, PixelSize(width: 75, height: 100))
    }

    func testPreviewPresetIs2048() {
        XCTAssertEqual(ImageLoadOptions.preview.maximumLongEdge, 2048)
    }

    // MARK: - Errors

    func testRejectsEmptyData() async {
        do {
            _ = try await loader.load(data: Data())
            XCTFail("Expected invalidImage")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsCorruptData() async {
        let garbage = Data((0 ..< 128).map { UInt8(($0 * 37) % 251) })
        do {
            _ = try await loader.load(data: garbage)
            XCTFail("Expected imageDecodingFailed")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .imageDecodingFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsTruncatedPNG() async throws {
        let source = try TestImage.solid(width: 64, height: 64, color: .cyan)
        let data = try TestImage.encode(source, format: "public.png")
        let truncated = Data(data.prefix(max(12, data.count / 3)))
        do {
            _ = try await loader.load(data: truncated)
            XCTFail("Expected imageDecodingFailed")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .imageDecodingFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsUnsupportedFormat() async throws {
        let gif = try XCTUnwrap(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        do {
            _ = try await loader.load(data: gif)
            XCTFail("Expected unsupportedFormat")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .unsupportedFormat)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsTooSmallImage() async throws {
        let source = try TestImage.solid(width: 40, height: 30, color: .white)
        let data = try TestImage.encode(source, format: "public.png")
        let options = ImageLoadOptions(minimumLongEdge: 100)
        do {
            _ = try await loader.load(data: data, options: options)
            XCTFail("Expected imageTooSmall")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .imageTooSmall(minimumLongEdge: 100))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).png")
        do {
            _ = try await loader.load(url: url)
            XCTFail("Expected invalidImage")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    /// 80 x 40 image made of 4 x 2 uniform 20 x 20 blocks, in `TestColor` order.
    private func makeOrientationFixture() throws -> CGImage {
        let colors = TestColor.allCases.map { $0.rgba }
        return try TestImage.image(width: 80, height: 40, colorSpace: TestImage.sRGB) { x, y in
            let column = min(x / 20, 3)
            let row = min(y / 20, 1)
            let value = colors[row * 4 + column]
            return SIMD4<UInt8>(value.0, value.1, value.2, value.3)
        }
    }

    private func assertBlocks(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        columns: Int,
        rows: Int,
        expected: [[TestColor]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let blockWidth = width / columns
        let blockHeight = height / rows
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let x = column * blockWidth + blockWidth / 2
                let y = row * blockHeight + blockHeight / 2
                let value = TestImage.rgba(pixels, width: width, x: x, y: y)
                let actual = TestColor.nearest(red: value.0, green: value.1, blue: value.2)
                XCTAssertEqual(
                    actual,
                    expected[row][column],
                    "block row \(row), column \(column)",
                    file: file,
                    line: line
                )
            }
        }
    }
}
