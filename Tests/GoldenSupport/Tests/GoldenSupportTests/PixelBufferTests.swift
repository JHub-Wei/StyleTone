import Foundation
import XCTest
@testable import GoldenSupport
import StyleToneCore

final class PixelBufferTests: XCTestCase {
    func testSolidFillProducesOneColour() throws {
        let color = RGB8(red: 0x12, green: 0x34, blue: 0x56)
        let buffer = try PixelBuffer(width: 4, height: 3, fill: color)

        XCTAssertEqual(buffer.width, 4)
        XCTAssertEqual(buffer.height, 3)
        XCTAssertEqual(buffer.pixelCount, 12)
        XCTAssertEqual(buffer.pixelSize, PixelSize(width: 4, height: 3))
        XCTAssertEqual(buffer.uniqueColorCount, 1)
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                XCTAssertEqual(buffer[x, y], RGBA8(color: color))
            }
        }
        XCTAssertEqual(buffer.meanLuma, color.luma, accuracy: 1e-9)
    }

    func testInvalidDimensionsThrow() {
        XCTAssertThrowsError(try PixelBuffer(width: 0, height: 4, fill: .black)) { error in
            XCTAssertEqual(
                error as? GoldenSupportError,
                .invalidDimensions(width: 0, height: 4)
            )
        }
    }

    func testRawByteCountIsValidated() {
        XCTAssertThrowsError(
            try PixelBuffer(width: 2, height: 2, rgbaBytes: [UInt8](repeating: 0, count: 15))
        ) { error in
            XCTAssertEqual(
                error as? GoldenSupportError,
                .invalidPixelBuffer(expectedByteCount: 16, actualByteCount: 15)
            )
        }
    }

    func testSubscriptRoundTripAndSafeLookup() throws {
        var buffer = try PixelBuffer(width: 3, height: 2, fill: .black)
        buffer[2, 1] = RGBA8(red: 10, green: 20, blue: 30)
        XCTAssertEqual(buffer[2, 1].red, 10)
        XCTAssertEqual(buffer.pixel(x: 2, y: 1)?.green, 20)
        XCTAssertNil(buffer.pixel(x: 3, y: 1))
        XCTAssertNil(buffer.colorAt(x: 0, y: -1))
    }

    func testPNGRoundTripIsExactAndKeepsOrientation() throws {
        var buffer = try PixelBuffer(width: 8, height: 4, fill: RGB8(red: 255, green: 0, blue: 0))
        for y in 2..<4 {
            for x in 0..<8 {
                buffer[x, y] = RGBA8(color: RGB8(red: 0, green: 0, blue: 255))
            }
        }

        let data = try buffer.pngData()
        let decoded = try PixelBuffer(imageData: data)

        XCTAssertEqual(decoded.pixelSize, buffer.pixelSize)
        XCTAssertEqual(decoded.bytes, buffer.bytes)
        XCTAssertEqual(decoded[0, 0].color, RGB8(red: 255, green: 0, blue: 0))
        XCTAssertEqual(decoded[0, 3].color, RGB8(red: 0, green: 0, blue: 255))
    }

    func testImageAssetRoundTripIsExactForOpaquePixels() throws {
        let buffer = try PixelBuffer(width: 5, height: 4, fill: RGB8(red: 12, green: 200, blue: 99))
        let asset = try buffer.makeImageAsset()
        XCTAssertEqual(asset.pixelSize, buffer.pixelSize)
        XCTAssertEqual(asset.width, 5)
        XCTAssertEqual(asset.height, 4)

        let decoded = try PixelBuffer(image: asset)
        XCTAssertEqual(decoded.bytes, buffer.bytes)
    }

    func testPremultipliedAlphaRoundTrip() throws {
        var buffer = try PixelBuffer(width: 2, height: 2, fill: .black)
        buffer[0, 0] = RGBA8(red: 200, green: 100, blue: 50, alpha: 128)
        let asset = try buffer.makeImageAsset()
        let decoded = try PixelBuffer(image: asset)
        let pixel = try XCTUnwrap(decoded.pixel(x: 0, y: 0))
        XCTAssertLessThanOrEqual(abs(Int(pixel.red) - 200), 2)
        XCTAssertLessThanOrEqual(abs(Int(pixel.green) - 100), 2)
        XCTAssertLessThanOrEqual(abs(Int(pixel.blue) - 50), 2)
        XCTAssertEqual(pixel.alpha, 128)
    }

    func testCropping() throws {
        var buffer = try PixelBuffer(width: 4, height: 4, fill: .black)
        for y in 0..<4 {
            for x in 0..<4 {
                buffer[x, y] = RGBA8(red: UInt8(x), green: UInt8(y), blue: 0)
            }
        }
        let cropped = try buffer.cropped(to: PixelRect(x: 1, y: 2, width: 2, height: 2))
        XCTAssertEqual(cropped.pixelSize, PixelSize(width: 2, height: 2))
        XCTAssertEqual(cropped[0, 0].red, 1)
        XCTAssertEqual(cropped[0, 0].green, 2)
        XCTAssertEqual(cropped[1, 1].red, 2)
        XCTAssertEqual(cropped[1, 1].green, 3)
    }

    func testCroppingClampsAndRejectsEmptyRectangles() throws {
        let buffer = try PixelBuffer(width: 4, height: 4, fill: .white)
        let clamped = try buffer.cropped(to: PixelRect(x: -5, y: -5, width: 100, height: 100))
        XCTAssertEqual(clamped.pixelSize, PixelSize(width: 4, height: 4))
        XCTAssertThrowsError(try buffer.cropped(to: PixelRect(x: 10, y: 10, width: 2, height: 2)))
    }

    func testUniqueColourCount() throws {
        var buffer = try PixelBuffer(width: 2, height: 2, fill: .white)
        buffer[1, 0] = RGBA8(color: .black)
        XCTAssertEqual(buffer.uniqueColorCount, 2)
    }
}
