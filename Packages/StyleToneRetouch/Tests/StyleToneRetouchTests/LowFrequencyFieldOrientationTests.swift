import GoldenSupport
import StyleToneCore
import XCTest
@testable import StyleToneRetouch

final class LowFrequencyFieldOrientationTests: XCTestCase {
    func testFieldPreservesTopDownOrientation() throws {
        let width = 32
        let height = 32
        var buffer = try PixelBuffer(
            width: width,
            height: height,
            fill: RGB8(red: 0, green: 0, blue: 0)
        )

        // A bright band at the top of the source image. If the reduced field is
        // vertically mirrored, its luma centroid moves to the bottom half.
        for y in 0 ..< 8 {
            for x in 0 ..< width {
                buffer[x, y] = RGBA8(red: 255, green: 255, blue: 255)
            }
        }

        let image = try buffer.makeImageAsset()
        let field = try XCTUnwrap(
            try LowFrequencyField.make(
                image: image,
                colorSpace: image.colorSpace,
                regionalRadius: 2
            )
        )

        var totalLuma = 0.0
        var weightedY = 0.0
        for y in 0 ..< field.height {
            for x in 0 ..< field.width {
                let luma = Double(field.samples[y * field.width + x].x)
                totalLuma += luma
                weightedY += luma * Double(y)
            }
        }

        XCTAssertGreaterThan(totalLuma, 0.001)
        let centroidY = weightedY / totalLuma
        XCTAssertLessThan(
            centroidY,
            Double(field.height) * 0.25,
            "LowFrequencyField is vertically mirrored relative to the source image"
        )
    }

    func testFieldDoesNotBorrowBackgroundOutsideSkinMask() throws {
        let width = 32
        let height = 32
        var buffer = try PixelBuffer(
            width: width,
            height: height,
            fill: RGB8(red: 255, green: 255, blue: 255)
        )

        for y in 0 ..< 16 {
            for x in 0 ..< width {
                buffer[x, y] = RGBA8(red: 75, green: 46, blue: 33)
            }
        }

        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< 16 {
            for x in 0 ..< width {
                alpha[y * width + x] = 255
            }
        }

        let image = try buffer.makeImageAsset()
        let field = try XCTUnwrap(
            try LowFrequencyField.make(
                image: image,
                colorSpace: image.colorSpace,
                regionalRadius: 4,
                skinAlpha: alpha
            )
        )

        let nearBoundary = field.sample(x: width / 2, y: 14)
        XCTAssertLessThan(
            Double(nearBoundary.x),
            0.2,
            "evenness field borrowed the bright background outside the skin mask"
        )
    }
}
