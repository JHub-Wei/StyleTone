import CoreGraphics
import StyleToneCore
import XCTest
@testable import StyleToneUI

final class SkinToolsImageGeometryTests: XCTestCase {
    private let square = SkinToolsImageGeometry(
        containerSize: CGSize(width: 200, height: 200),
        imageSize: CGSize(width: 100, height: 100)
    )

    func testSquareImageFillsContainerAndMapsCorners() throws {
        XCTAssertEqual(square.fitScale, 2, accuracy: 0.0001)
        XCTAssertEqual(square.displayedSize.width, 200, accuracy: 0.0001)
        XCTAssertEqual(square.imageOrigin.x, 0, accuracy: 0.0001)

        let topLeft = try XCTUnwrap(square.normalizedPoint(at: CGPoint(x: 0, y: 0)))
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)

        let bottomRight = try XCTUnwrap(square.normalizedPoint(at: CGPoint(x: 200, y: 200)))
        XCTAssertEqual(bottomRight.x, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 0.0001)

        let center = try XCTUnwrap(square.normalizedPoint(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }

    func testLetterboxedImageRejectsTapsOutsideThePhoto() {
        let wide = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(wide.fitScale, 1, accuracy: 0.0001)
        XCTAssertEqual(wide.displayedSize.height, 100, accuracy: 0.0001)
        XCTAssertEqual(wide.imageOrigin.y, 50, accuracy: 0.0001)

        XCTAssertNil(wide.normalizedPoint(at: CGPoint(x: 100, y: 10)))
        XCTAssertNil(wide.normalizedPoint(at: CGPoint(x: 100, y: 190)))
        XCTAssertNil(wide.normalizedPoint(at: CGPoint(x: -1, y: 100)))

        let center = wide.normalizedPoint(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(center?.x, 0.5)
        XCTAssertEqual(center?.y, 0.5)
    }

    func testZoomCentersTheImageAndMapsTaps() throws {
        let zoomed = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100),
            zoomScale: 2
        )

        XCTAssertEqual(zoomed.displayedSize.width, 400, accuracy: 0.0001)
        XCTAssertEqual(zoomed.imageOrigin.x, -100, accuracy: 0.0001)

        let center = try XCTUnwrap(zoomed.normalizedPoint(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)

        let quarter = try XCTUnwrap(zoomed.normalizedPoint(at: CGPoint(x: 0, y: 0)))
        XCTAssertEqual(quarter.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(quarter.y, 0.25, accuracy: 0.0001)

        let viewPoint = zoomed.viewPoint(for: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(viewPoint.x, 100, accuracy: 0.0001)
        XCTAssertEqual(viewPoint.y, 100, accuracy: 0.0001)
    }

    func testZoomIsClampedToAtLeastOne() {
        let underZoomed = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100),
            zoomScale: 0.25
        )

        XCTAssertEqual(underZoomed.resolvedZoom, 1, accuracy: 0.0001)
        XCTAssertEqual(underZoomed.displayedSize.width, 200, accuracy: 0.0001)
    }

    func testMarkerDiameterUsesTheShortEdgeAndTracksZoom() {
        XCTAssertEqual(square.markerDiameter(forRadius: 0.02), 8, accuracy: 0.0001)

        let zoomed = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100),
            zoomScale: 2
        )
        XCTAssertEqual(zoomed.markerDiameter(forRadius: 0.02), 16, accuracy: 0.0001)
        XCTAssertEqual(zoomed.markerDiameter(forRadius: .nan), 0, accuracy: 0.0001)
    }

    func testPanClampsToTheDisplayedImage() {
        let zoomed = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100),
            zoomScale: 2
        )

        XCTAssertEqual(
            zoomed.clampedPanOffset(CGSize(width: 500, height: -500)).width,
            100,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            zoomed.clampedPanOffset(CGSize(width: 500, height: -500)).height,
            -100,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            zoomed.clampedPanOffset(CGSize(width: 10, height: 10)).width,
            10,
            accuracy: 0.0001
        )
    }

    func testInvalidSizesAreSafe() {
        let empty = SkinToolsImageGeometry(
            containerSize: .zero,
            imageSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(empty.fitScale, 0, accuracy: 0.0001)
        XCTAssertNil(empty.normalizedPoint(at: .zero))
        XCTAssertEqual(empty.markerDiameter(forRadius: 0.02), 0, accuracy: 0.0001)

        let zeroImage = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: .zero
        )
        XCTAssertEqual(zeroImage.fitScale, 0, accuracy: 0.0001)
        XCTAssertNil(zeroImage.normalizedPoint(at: CGPoint(x: 100, y: 100)))
    }

    func testPanOffsetMovesTheMapping() throws {
        let panned = SkinToolsImageGeometry(
            containerSize: CGSize(width: 200, height: 200),
            imageSize: CGSize(width: 100, height: 100),
            zoomScale: 2,
            panOffset: CGSize(width: -100, height: 0)
        )

        XCTAssertEqual(panned.imageOrigin.x, -200, accuracy: 0.0001)
        let center = try XCTUnwrap(panned.normalizedPoint(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(center.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.0001)
    }
}
