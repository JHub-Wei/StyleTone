import CoreGraphics
import Foundation
import XCTest
import StyleToneCore
import StyleToneImaging

final class ColorPipelineTests: XCTestCase {
    private let pipeline = ColorPipeline()

    // MARK: - Transfer functions

    func testSRGBTransferRoundTrip() {
        for value in 0 ... 255 {
            let encoded = Float(value) / 255.0
            let linear = ColorPipeline.linearValue(fromSRGBEncoded: encoded)
            let roundTrip = ColorPipeline.srgbEncodedValue(fromLinear: linear)
            XCTAssertEqual(roundTrip, encoded, accuracy: 1e-5)
        }
    }

    func testKnownTransferValues() {
        XCTAssertEqual(ColorPipeline.linearValue(fromSRGBEncoded: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ColorPipeline.linearValue(fromSRGBEncoded: 1), 1, accuracy: 1e-6)
        XCTAssertEqual(
            ColorPipeline.linearValue(fromSRGBEncoded: 0.5),
            0.21404114,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            ColorPipeline.srgbEncodedValue(fromLinear: 0.2158605),
            0.5019608,
            accuracy: 1e-4
        )
    }

    // MARK: - Linearization

    func testLinearizesSolidSRGBColor() throws {
        let asset = try makeSolidAsset(red: 128, green: 64, blue: 32)
        let linear = try pipeline.linearize(asset)

        XCTAssertEqual(linear.width, 2)
        XCTAssertEqual(linear.height, 2)
        let pixel = try XCTUnwrap(linear.pixel(x: 1, y: 1))
        XCTAssertEqual(pixel.x, 0.2158605, accuracy: 1e-4)
        XCTAssertEqual(pixel.y, 0.0512695, accuracy: 1e-4)
        XCTAssertEqual(pixel.z, 0.0144438, accuracy: 1e-4)
        XCTAssertEqual(pixel.w, 1, accuracy: 1e-6)
    }

    func testEncodesSolidColorBackToSRGB() throws {
        let asset = try makeSolidAsset(red: 128, green: 64, blue: 32)
        let linear = try pipeline.linearize(asset)
        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)

        let pixels = try TestImage.pixels(of: output.cgImage)
        let color = TestImage.rgba(pixels, width: output.width, x: 0, y: 0)
        XCTAssertEqual(Double(color.0), 128, accuracy: 1)
        XCTAssertEqual(Double(color.1), 64, accuracy: 1)
        XCTAssertEqual(Double(color.2), 32, accuracy: 1)
        XCTAssertEqual(color.3, 255)
    }

    func testGradientRoundTrip() throws {
        let width = 256
        let source = try TestImage.image(width: width, height: 1, colorSpace: TestImage.sRGB) { x, _ in
            SIMD4<UInt8>(UInt8(x), UInt8(255 - x), UInt8((x * 3) % 256), 255)
        }
        let asset = ImageAsset(cgImage: source, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
        let linear = try pipeline.linearize(asset)
        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)

        let pixels = try TestImage.pixels(of: output.cgImage)
        for x in 0 ..< width {
            let value = TestImage.rgba(pixels, width: width, x: x, y: 0)
            XCTAssertEqual(Double(value.0), Double(x), accuracy: 1, "red at \(x)")
            XCTAssertEqual(Double(value.1), Double(255 - x), accuracy: 1, "green at \(x)")
            XCTAssertEqual(Double(value.2), Double((x * 3) % 256), accuracy: 1, "blue at \(x)")
        }
    }

    // MARK: - Wide gamut

    func testDisplayP3InputBecomesExtendedLinearSRGB() throws {
        let source = try TestImage.solid(
            width: 2,
            height: 2,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let asset = ImageAsset(
            cgImage: source,
            colorSpace: ImageColorSpace.displayP3.cgColorSpace
        )
        let linear = try pipeline.linearize(asset)
        let pixel = try XCTUnwrap(linear.pixel(x: 0, y: 0))

        XCTAssertGreaterThan(pixel.x, 1.20)
        XCTAssertLessThan(pixel.y, 0)
        XCTAssertLessThan(pixel.z, 0)
        XCTAssertEqual(pixel.x, 1.224745, accuracy: 0.005)
        XCTAssertEqual(pixel.y, -0.042058, accuracy: 0.005)
        XCTAssertEqual(pixel.z, -0.019642, accuracy: 0.005)
    }

    func testGamutMapsDisplayP3RedIntoSRGB() throws {
        let source = try TestImage.solid(
            width: 2,
            height: 2,
            color: .red,
            colorSpace: TestImage.displayP3
        )
        let asset = ImageAsset(
            cgImage: source,
            colorSpace: ImageColorSpace.displayP3.cgColorSpace
        )
        let linear = try pipeline.linearize(asset)
        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)

        let pixels = try TestImage.pixels(of: output.cgImage)
        let color = TestImage.rgba(pixels, width: output.width, x: 0, y: 0)
        XCTAssertGreaterThanOrEqual(color.0, 240)
        XCTAssertLessThanOrEqual(color.1, 80)
        XCTAssertLessThanOrEqual(color.2, 80)
        XCTAssertEqual(color.3, 255)

        let p3Output = try pipeline.makeImage(from: linear, colorSpace: .displayP3)
        XCTAssertEqual(ImageColorSpace.detect(p3Output.colorSpace), .displayP3)
        let p3Pixels = try TestImage.pixels(of: p3Output.cgImage)
        let p3Color = TestImage.rgba(p3Pixels, width: p3Output.width, x: 0, y: 0)
        XCTAssertGreaterThanOrEqual(p3Color.0, 245)
        XCTAssertLessThanOrEqual(p3Color.1, 12)
        XCTAssertLessThanOrEqual(p3Color.2, 12)
    }

    func testNeutralGraySurvivesColorSpaceConversion() throws {
        let asset = try makeSolidAsset(red: 128, green: 128, blue: 128)
        let p3 = try pipeline.convert(asset, to: .displayP3)
        let p3Pixels = try TestImage.pixels(of: p3.cgImage)
        let p3Color = TestImage.rgba(p3Pixels, width: p3.width, x: 0, y: 0)
        XCTAssertEqual(Double(p3Color.0), 128, accuracy: 1)
        XCTAssertEqual(Double(p3Color.1), 128, accuracy: 1)
        XCTAssertEqual(Double(p3Color.2), 128, accuracy: 1)

        let back = try pipeline.convert(p3, to: .sRGB)
        let sRGBPixels = try TestImage.pixels(of: back.cgImage)
        let sRGBColor = TestImage.rgba(sRGBPixels, width: back.width, x: 0, y: 0)
        XCTAssertEqual(Double(sRGBColor.0), 128, accuracy: 1)
        XCTAssertEqual(Double(sRGBColor.1), 128, accuracy: 1)
        XCTAssertEqual(Double(sRGBColor.2), 128, accuracy: 1)
    }

    // MARK: - Gamut safety

    func testOutOfRangeAndNonFiniteValuesAreSafe() throws {
        let pixels: [SIMD4<Float>] = [
            SIMD4<Float>(4, -1, 2, 1),
            SIMD4<Float>(-0.5, 1.5, 0.2, 0.5),
            SIMD4<Float>(Float.nan, 0, 0, 1)
        ]
        let linear = try LinearImage(width: 3, height: 1, pixels: pixels)
        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)
        let bytes = try TestImage.pixels(of: output.cgImage)

        XCTAssertEqual(bytes.count, 12)
        XCTAssertEqual(bytes[11], 255)
        XCTAssertEqual(bytes[8], 0)
        XCTAssertEqual(bytes[9], 0)
        XCTAssertEqual(bytes[10], 0)
    }

    func testNeutralLinearValueMapsToEqualChannels() throws {
        let linear = try LinearImage(
            width: 1,
            height: 1,
            pixels: [SIMD4<Float>(0.2, 0.2, 0.2, 1)]
        )
        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)
        let bytes = try TestImage.pixels(of: output.cgImage)
        XCTAssertEqual(bytes[0], bytes[1])
        XCTAssertEqual(bytes[1], bytes[2])
    }

    // MARK: - Alpha

    func testAlphaIsUnpremultipliedAndRepremultiplied() throws {
        let premultiplied = try TestImage.image(
            width: 2,
            height: 2,
            colorSpace: TestImage.sRGB
        ) { _, _ in
            SIMD4<UInt8>(128, 0, 0, 128)
        }
        let asset = ImageAsset(
            cgImage: premultiplied,
            colorSpace: ImageColorSpace.sRGB.cgColorSpace
        )
        let linear = try pipeline.linearize(asset)
        let pixel = try XCTUnwrap(linear.pixel(x: 0, y: 0))
        XCTAssertEqual(pixel.w, 128.0 / 255.0, accuracy: 1e-5)
        XCTAssertEqual(pixel.x, 1.0, accuracy: 1e-4)
        XCTAssertEqual(pixel.y, 0, accuracy: 1e-6)
        XCTAssertEqual(pixel.z, 0, accuracy: 1e-6)

        let output = try pipeline.makeImage(from: linear, colorSpace: .sRGB)
        let pixels = try TestImage.pixels(of: output.cgImage)
        let color = TestImage.rgba(pixels, width: 2, x: 0, y: 0)
        XCTAssertEqual(Double(color.0), 128, accuracy: 1)
        XCTAssertEqual(color.3, 128)
    }

    // MARK: - Regions and fast paths

    func testTilesMatchFullImage() throws {
        let width = 37
        let height = 23
        let source = try TestImage.image(width: width, height: height, colorSpace: TestImage.sRGB) { x, y in
            SIMD4<UInt8>(
                UInt8((x * 7) % 256),
                UInt8((y * 11) % 256),
                UInt8((x + y) % 256),
                255
            )
        }
        let asset = ImageAsset(cgImage: source, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
        let full = try pipeline.linearize(asset)

        var tileCount = 0
        try pipeline.forEachTile(in: asset, tileHeight: 8) { tile, region in
            tileCount += 1
            XCTAssertEqual(tile.width, width)
            XCTAssertEqual(tile.height, region.height)
            for y in 0 ..< region.height {
                for x in 0 ..< width {
                    let expected = try XCTUnwrap(full.pixel(x: x, y: region.y + y))
                    let actual = try XCTUnwrap(tile.pixel(x: x, y: y))
                    XCTAssertEqual(actual.x, expected.x, accuracy: 1e-6)
                    XCTAssertEqual(actual.y, expected.y, accuracy: 1e-6)
                    XCTAssertEqual(actual.z, expected.z, accuracy: 1e-6)
                    XCTAssertEqual(actual.w, expected.w, accuracy: 1e-6)
                }
            }
        }
        XCTAssertEqual(tileCount, 3)
    }

    func testConvertReturnsInputWhenSpaceMatches() throws {
        let asset = try makeSolidAsset(red: 10, green: 20, blue: 30)
        let converted = try pipeline.convert(asset, to: .sRGB)
        XCTAssertTrue(converted.cgImage === asset.cgImage)
    }

    func testLinearImageValidatesDimensions() {
        XCTAssertThrowsError(try LinearImage(width: 0, height: 1, pixels: []))
        XCTAssertThrowsError(
            try LinearImage(width: 2, height: 2, pixels: [SIMD4<Float>(0, 0, 0, 1)])
        )
        let image = try? LinearImage(
            width: 2,
            height: 1,
            pixels: [SIMD4<Float>(0, 0, 0, 1), SIMD4<Float>(1, 1, 1, 1)]
        )
        XCTAssertNotNil(image)
        XCTAssertNil(image?.pixel(x: 2, y: 0))
        XCTAssertNotNil(image?.pixel(x: 1, y: 0))
    }

    // MARK: - Helpers

    private func makeSolidAsset(red: UInt8, green: UInt8, blue: UInt8) throws -> ImageAsset {
        let source = try TestImage.image(width: 2, height: 2, colorSpace: TestImage.sRGB) { _, _ in
            SIMD4<UInt8>(red, green, blue, 255)
        }
        return ImageAsset(cgImage: source, colorSpace: ImageColorSpace.sRGB.cgColorSpace)
    }
}
