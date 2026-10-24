import XCTest
import GoldenSupport
import StyleToneCore
import TestShared
@testable import StyleToneVision

final class VisionPairQualityAnalyzerTests: XCTestCase {
    private let analyzer = VisionPairQualityAnalyzer()

    func testIdenticalImagesAreGood() async throws {
        let image = try VisionTestImage.fixture(named: "noise.midgray")
        let result = try await analyzer.assessDetailed(original: image, edited: image)

        XCTAssertEqual(result.quality.grade, .good, "\(result.quality.reasons)")
        XCTAssertTrue(result.quality.reasons.isEmpty)
        XCTAssertGreaterThanOrEqual(result.quality.confidence, 0.5)
        XCTAssertEqual(result.metrics.resolutionRatio, 1, accuracy: 1e-9)
        XCTAssertEqual(result.metrics.aspectRatioDelta, 0, accuracy: 1e-9)
    }

    func testUnrelatedImagesAreRejected() async throws {
        let original = try VisionTestImage.fixture(named: "noise.midgray")
        let edited = try VisionTestImage.gradient(size: original.pixelSize)
        let result = try await analyzer.assessDetailed(original: original, edited: edited)

        XCTAssertEqual(result.quality.grade, .rejected, "\(result.quality.reasons)")
        XCTAssertGreaterThan(
            result.metrics.structureDelta ?? 1,
            VisionPairQualityConfiguration().rejectedStructureDelta
        )
    }

    func testLowResolutionEditedImageIsRejected() async throws {
        let original = try VisionTestImage.gradient(size: PixelSize(width: 1024, height: 1024))
        let edited = try VisionTestImage.resized(original, to: PixelSize(width: 320, height: 320))
        let result = try await analyzer.assessDetailed(original: original, edited: edited)

        XCTAssertEqual(result.quality.grade, .rejected, "\(result.quality.reasons)")
        XCTAssertTrue(result.quality.reasons.contains(PairQualityReason.resolutionTooLow.rawValue))
    }

    func testAspectRatioMismatchIsRejected() async throws {
        let original = try VisionTestImage.fixture(named: "grid.tiles")
        let edited = try VisionTestImage.resized(
            original,
            to: PixelSize(width: original.pixelSize.width, height: original.pixelSize.height / 2)
        )
        let result = try await analyzer.assessDetailed(original: original, edited: edited)

        XCTAssertEqual(result.quality.grade, .rejected, "\(result.quality.reasons)")
        XCTAssertTrue(result.quality.reasons.contains(PairQualityReason.aspectRatioMismatch.rawValue))
    }

    func testTranslatedPairIsFlaggedAsMisaligned() async throws {
        let base = try VisionTestImage.fixture(named: "noise.midgray")
        let original = try VisionTestImage.resized(base, to: PixelSize(width: 512, height: 512))
        let edited = try VisionTestImage.shifted(original, dx: 24, dy: 0)
        let result = try await analyzer.assessDetailed(original: original, edited: edited)

        XCTAssertNotEqual(result.quality.grade, .good, "\(result.quality.reasons)")
        XCTAssertTrue(
            result.quality.reasons.contains(PairQualityReason.misaligned.rawValue)
                || result.quality.reasons.contains(PairQualityReason.notRegistered.rawValue),
            "\(result.quality.reasons)"
        )
    }

    func testBlankPairReturnsAStableGrade() async throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 256, height: 256),
            color: RGB8(gray: 160)
        )
        let result = try await analyzer.assessDetailed(original: image, edited: image)

        XCTAssertFalse(result.quality.reasons.contains(PairQualityReason.analysisUnavailable.rawValue))
        XCTAssertGreaterThanOrEqual(result.quality.confidence, 0.05)
        XCTAssertLessThanOrEqual(result.quality.confidence, 1)
    }
}
