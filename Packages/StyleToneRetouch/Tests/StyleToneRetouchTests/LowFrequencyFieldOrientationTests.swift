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
}
