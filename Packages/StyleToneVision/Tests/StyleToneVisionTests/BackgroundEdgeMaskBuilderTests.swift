import XCTest
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import TestShared
@testable import StyleToneVision

final class BackgroundEdgeMaskBuilderTests: XCTestCase {
    func testGridProducesStraightLineMask() throws {
        let image = try VisionTestImage.fixture(named: "grid.tiles")
        let result = try BackgroundEdgeMaskBuilder().build(image: image)

        XCTAssertEqual(result.mask.width, image.pixelSize.width)
        XCTAssertEqual(result.mask.height, image.pixelSize.height)
        XCTAssertGreaterThan(result.lineRatio, 0.02)
        XCTAssertGreaterThan(result.edgeRatio, 0.02)
        XCTAssertGreaterThan(
            result.mask.bytes.reduce(0) { $0 + Int($1) } / result.mask.bytes.count,
            10
        )
    }

    func testVerticalEdgeIsMarkedAsLine() throws {
        let image = try VisionTestImage.fixture(named: "edge.vertical")
        let result = try BackgroundEdgeMaskBuilder().build(image: image)

        XCTAssertGreaterThan(result.edgeRatio, 0.005)
        XCTAssertGreaterThan(result.lineRatio, 0.001)
        XCTAssertGreaterThan(result.mask.value(x: 80, y: 60) ?? 0, 80)
    }

    func testFlatImageProducesEmptyMask() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 128, height: 96),
            color: RGB8(gray: 128)
        )
        let result = try BackgroundEdgeMaskBuilder().build(image: image)

        XCTAssertLessThan(result.edgeRatio, 0.001)
        XCTAssertLessThan(result.lineRatio, 0.001)
        XCTAssertEqual(result.mask.bytes.reduce(0) { $0 + Int($1) }, 0)
    }

    func testPersonMaskSuppressesSubjectEdges() throws {
        let image = try VisionTestImage.fixture(named: "grid.tiles")
        let mask = try MockMaskFactory.rectangle(
            size: image.pixelSize,
            rect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        )
        let result = try BackgroundEdgeMaskBuilder().build(
            linearImage: try ColorPipeline().linearize(image),
            personMask: mask
        )

        var leftSum = 0
        var rightSum = 0
        var leftCount = 0
        var rightCount = 0
        for y in 0 ..< result.mask.height {
            for x in 0 ..< result.mask.width {
                let value = Int(result.mask.value(x: x, y: y) ?? 0)
                if x < result.mask.width / 2 {
                    leftSum += value
                    leftCount += 1
                } else {
                    rightSum += value
                    rightCount += 1
                }
            }
        }
        let leftMean = Double(leftSum) / Double(max(leftCount, 1))
        let rightMean = Double(rightSum) / Double(max(rightCount, 1))
        XCTAssertGreaterThan(rightMean, leftMean)
    }
}
