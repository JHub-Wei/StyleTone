import XCTest
import StyleToneCore
import TestShared
@testable import StyleToneVision

final class PortraitWarningBuilderTests: XCTestCase {
    private let configuration = VisionAnalysisConfiguration()

    func testMultipleFacesAndNoBodyAreReported() {
        let faces = [
            MockPortraitAnalysisFactory.faceObservation(
                boundingBox: NormalizedRect(x: 0.10, y: 0.20, width: 0.25, height: 0.25)
            ),
            MockPortraitAnalysisFactory.faceObservation(
                boundingBox: NormalizedRect(x: 0.60, y: 0.20, width: 0.25, height: 0.25)
            )
        ]
        let warnings = PortraitWarningBuilder.build(
            faces: faces,
            body: nil,
            captureQuality: 0.9,
            skinLowConfidence: false,
            failedStages: [],
            confidence: 0.8,
            meanLuma: 0.5,
            configuration: configuration
        )
        XCTAssertTrue(warnings.contains(.multipleFaces))
        XCTAssertTrue(warnings.contains(.noBody))
        XCTAssertFalse(warnings.contains(.noFace))
        XCTAssertFalse(warnings.contains(.lowLight))
    }

    func testEmptyDetectionReportsNoFaceAndNoBody() {
        let warnings = PortraitWarningBuilder.build(
            faces: [],
            body: nil,
            captureQuality: nil,
            skinLowConfidence: false,
            failedStages: [.faceDetection, .bodyPose],
            confidence: 0.05,
            meanLuma: 0.5,
            configuration: configuration
        )
        XCTAssertTrue(warnings.contains(.noFace))
        XCTAssertTrue(warnings.contains(.noBody))
        XCTAssertTrue(warnings.contains(.lowConfidence))
    }

    func testLowLightAndOcclusionAreReported() {
        let face = MockPortraitAnalysisFactory.faceObservation(
            boundingBox: NormalizedRect(x: 0.0, y: 0.3, width: 0.2, height: 0.2)
        )
        let warnings = PortraitWarningBuilder.build(
            faces: [face],
            body: MockPortraitAnalysisFactory.bodyObservation(),
            captureQuality: 0.1,
            skinLowConfidence: true,
            failedStages: [],
            confidence: 0.7,
            meanLuma: 0.05,
            configuration: configuration
        )
        XCTAssertTrue(warnings.contains(.lowLight))
        XCTAssertTrue(warnings.contains(.occlusion))
        XCTAssertTrue(warnings.contains(.lowConfidence))
    }

    func testBodyPresentRemovesNoBodyWarning() {
        let face = MockPortraitAnalysisFactory.faceObservation()
        let warnings = PortraitWarningBuilder.build(
            faces: [face],
            body: MockPortraitAnalysisFactory.bodyObservation(),
            captureQuality: 0.9,
            skinLowConfidence: false,
            failedStages: [],
            confidence: 0.9,
            meanLuma: 0.5,
            configuration: configuration
        )
        XCTAssertFalse(warnings.contains(.noBody))
        XCTAssertFalse(warnings.contains(.noFace))
        XCTAssertFalse(warnings.contains(.lowConfidence))
    }
}
