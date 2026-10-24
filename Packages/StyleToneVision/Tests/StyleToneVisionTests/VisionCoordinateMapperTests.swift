import CoreGraphics
import XCTest
import StyleToneCore
@testable import StyleToneVision

final class VisionCoordinateMapperTests: XCTestCase {
    func testFlipsVisionPointToTopLeft() {
        let point = VisionCoordinateMapper.topLeftPoint(
            fromVisionNormalized: CGPoint(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(point.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0.25, accuracy: 1e-9)
        XCTAssertTrue(point.isNormalized)
    }

    func testFlipsVisionRectToTopLeft() {
        let rect = VisionCoordinateMapper.topLeftRect(
            fromVisionNormalized: CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40)
        )
        XCTAssertEqual(rect.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0.40, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.30, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.40, accuracy: 1e-9)
        XCTAssertEqual(rect.maxY, 0.80, accuracy: 1e-9)
    }

    func testMapsLandmarkRelativeToFaceBoundingBox() {
        let box = CGRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40)
        let bottomLeft = VisionCoordinateMapper.topLeftPoint(
            landmark: CGPoint(x: 0, y: 0),
            inVisionFaceBoundingBox: box
        )
        XCTAssertEqual(bottomLeft.x, 0.10, accuracy: 1e-9)
        XCTAssertEqual(bottomLeft.y, 0.80, accuracy: 1e-9)

        let topRight = VisionCoordinateMapper.topLeftPoint(
            landmark: CGPoint(x: 1, y: 1),
            inVisionFaceBoundingBox: box
        )
        XCTAssertEqual(topRight.x, 0.40, accuracy: 1e-9)
        XCTAssertEqual(topRight.y, 0.40, accuracy: 1e-9)
    }

    func testClampsOutOfBoundsValues() {
        let point = VisionCoordinateMapper.topLeftPoint(
            fromVisionNormalized: CGPoint(x: 1.4, y: -0.2)
        )
        XCTAssertEqual(point.x, 1, accuracy: 1e-9)
        XCTAssertEqual(point.y, 1, accuracy: 1e-9)

        let rect = VisionCoordinateMapper.topLeftRect(
            fromVisionNormalized: CGRect(x: -0.2, y: -0.3, width: 2, height: 2)
        )
        XCTAssertEqual(rect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 1, accuracy: 1e-9)
    }

    func testNonFiniteValuesBecomeZero() {
        let point = VisionCoordinateMapper.topLeftPoint(
            fromVisionNormalized: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)
        )
        XCTAssertEqual(point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0, accuracy: 1e-9)
        XCTAssertTrue(point.isNormalized)
    }

    func testPixelPointUsesTopLeftOrigin() {
        let point = VisionCoordinateMapper.pixelPoint(
            NormalizedPoint(x: 0.5, y: 0.25),
            width: 200,
            height: 400
        )
        XCTAssertEqual(point.x, 100, accuracy: 1e-9)
        XCTAssertEqual(point.y, 100, accuracy: 1e-9)
    }
}
