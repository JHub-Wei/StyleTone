import XCTest
import StyleToneCore
@testable import StyleToneVision

final class PairQualityClassifierTests: XCTestCase {
    private let configuration = VisionPairQualityConfiguration()

    func testGoodPairHasNoReasons() {
        let quality = PairQualityClassifier.classify(
            metrics: metrics(),
            configuration: configuration
        )
        XCTAssertEqual(quality.grade, .good)
        XCTAssertTrue(quality.reasons.isEmpty)
        XCTAssertGreaterThan(quality.confidence, 0.8)
    }

    func testWarningPairReportsLocalizationKeys() {
        let quality = PairQualityClassifier.classify(
            metrics: metrics(
                resolutionRatio: 0.80,
                aspectRatioDelta: 0.03,
                semanticSimilarity: 0.65,
                registrationOffset: 0.03,
                structureDelta: 0.25
            ),
            configuration: configuration
        )
        XCTAssertEqual(quality.grade, .warning)
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.resolutionReduced.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.aspectRatioChanged.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.misaligned.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.semanticDrift.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.structureChanged.rawValue))
    }

    func testRejectedPairReportsHardFailures() {
        let quality = PairQualityClassifier.classify(
            metrics: metrics(
                resolutionRatio: 0.30,
                aspectRatioDelta: 0.20,
                semanticSimilarity: 0.20,
                registrationOffset: 0.20,
                structureDelta: 0.80
            ),
            configuration: configuration
        )
        XCTAssertEqual(quality.grade, .rejected)
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.resolutionTooLow.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.aspectRatioMismatch.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.notRegistered.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.semanticMismatch.rawValue))
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.structureMismatch.rawValue))
    }

    func testUnavailableAnalysisDegradesToWarning() {
        let quality = PairQualityClassifier.classify(
            metrics: metrics(
                semanticSimilarity: nil,
                registrationOffset: nil,
                registrationConfidence: nil,
                structureDelta: nil
            ),
            configuration: configuration
        )
        XCTAssertEqual(quality.grade, .warning)
        XCTAssertTrue(quality.reasons.contains(PairQualityReason.analysisUnavailable.rawValue))
        XCTAssertLessThan(quality.confidence, 0.5)
    }

    func testTinyImagesLowerConfidence() {
        let quality = PairQualityClassifier.classify(
            metrics: metrics(originalSize: PixelSize(width: 32, height: 32)),
            configuration: configuration
        )
        XCTAssertLessThan(quality.confidence, 0.8)
    }

    private func metrics(
        originalSize: PixelSize = PixelSize(width: 1024, height: 768),
        resolutionRatio: Double = 1,
        aspectRatioDelta: Double = 0,
        semanticSimilarity: Float? = 0.95,
        registrationOffset: Double? = 0.001,
        registrationConfidence: Float? = 0.95,
        structureDelta: Double? = 0.05
    ) -> VisionPairQualityMetrics {
        VisionPairQualityMetrics(
            originalSize: originalSize,
            editedSize: originalSize,
            resolutionRatio: resolutionRatio,
            aspectRatioDelta: aspectRatioDelta,
            semanticSimilarity: semanticSimilarity,
            registrationOffset: registrationOffset,
            registrationConfidence: registrationConfidence,
            structureDelta: structureDelta,
            usedFeaturePrint: semanticSimilarity != nil,
            duration: 0.05
        )
    }
}
