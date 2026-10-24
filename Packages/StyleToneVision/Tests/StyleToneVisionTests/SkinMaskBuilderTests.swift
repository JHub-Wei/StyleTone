import XCTest
import GoldenSupport
import StyleToneCore
import TestShared
@testable import StyleToneVision

final class SkinMaskBuilderTests: XCTestCase {
    private let skinColor = RGB8(red: 214, green: 170, blue: 148)
    private let faceBox = NormalizedRect(x: 0.25, y: 0.20, width: 0.50, height: 0.55)

    func testSkinIsDetectedInsideFaceEllipse() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 256, height: 256),
            color: skinColor
        )
        let face = MockPortraitAnalysisFactory.faceObservation(boundingBox: faceBox)
        let result = try XCTUnwrap(
            try SkinMaskBuilder().build(image: image, faces: [face])
        )

        XCTAssertEqual(result.mask.width, 256)
        XCTAssertEqual(result.mask.height, 256)
        XCTAssertGreaterThan(result.mask.value(x: 128, y: 130) ?? 0, 200)
        XCTAssertEqual(result.mask.value(x: 10, y: 10), 0)
        XCTAssertGreaterThan(result.coverage, 0.35)
        XCTAssertFalse(result.lowConfidence)
    }

    func testNeutralGrayIsNotSkin() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 256, height: 256),
            color: RGB8(gray: 180)
        )
        let face = MockPortraitAnalysisFactory.faceObservation(boundingBox: faceBox)
        let result = try XCTUnwrap(
            try SkinMaskBuilder().build(image: image, faces: [face])
        )

        XCTAssertLessThan(result.mask.value(x: 128, y: 130) ?? 255, 10)
        XCTAssertLessThan(result.coverage, 0.05)
        XCTAssertTrue(result.lowConfidence)
    }

    func testEyesAndLipsAreExcluded() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 256, height: 256),
            color: skinColor
        )
        let face = MockPortraitAnalysisFactory.faceObservation(boundingBox: faceBox)
        let result = try XCTUnwrap(
            try SkinMaskBuilder().build(image: image, faces: [face])
        )

        let leftPupil = try XCTUnwrap(face.points(for: .leftPupil).first)
        let pupilX = Int((leftPupil.x * 256).rounded())
        let pupilY = Int((leftPupil.y * 256).rounded())
        XCTAssertLessThan(result.mask.value(x: pupilX, y: pupilY) ?? 255, 60)

        let lipX = Int((0.5 * 256).rounded())
        let lipY = Int(((faceBox.y + faceBox.height * 0.74) * 256).rounded())
        XCTAssertLessThan(result.mask.value(x: lipX, y: lipY) ?? 255, 60)

        XCTAssertGreaterThan(result.mask.value(x: 128, y: 135) ?? 0, 180)
    }

    func testNoFacesReturnsNil() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 64, height: 64),
            color: skinColor
        )
        XCTAssertNil(try SkinMaskBuilder().build(image: image, faces: []))
    }

    func testMultipleFacesAreUnited() throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 256, height: 256),
            color: skinColor
        )
        let left = MockPortraitAnalysisFactory.faceObservation(
            boundingBox: NormalizedRect(x: 0.06, y: 0.22, width: 0.34, height: 0.45)
        )
        let right = MockPortraitAnalysisFactory.faceObservation(
            boundingBox: NormalizedRect(x: 0.60, y: 0.22, width: 0.34, height: 0.45)
        )
        let result = try XCTUnwrap(
            try SkinMaskBuilder().build(image: image, faces: [left, right])
        )
        XCTAssertGreaterThan(result.mask.value(x: 61, y: 128) ?? 0, 180)
        XCTAssertGreaterThan(result.mask.value(x: 195, y: 128) ?? 0, 180)
    }
}
