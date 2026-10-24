import Foundation
import StyleToneCore

/// Pure warning rules for portrait analysis.
///
/// Extracted from the Vision pipeline so multi-face, no-face, no-body and
/// low-confidence behavior can be unit-tested without a detector.
enum PortraitWarningBuilder {
    static func build(
        faces: [FaceObservation],
        body: BodyObservation?,
        captureQuality: Float?,
        skinLowConfidence: Bool,
        failedStages: [VisionAnalysisStage],
        confidence: Float,
        meanLuma: Double,
        configuration: VisionAnalysisConfiguration
    ) -> [AnalysisWarning] {
        var warnings: [AnalysisWarning] = []
        func add(_ warning: AnalysisWarning) {
            if !warnings.contains(warning) {
                warnings.append(warning)
            }
        }

        if faces.isEmpty {
            add(.noFace)
        }
        if faces.count > 1 {
            add(.multipleFaces)
        }
        if body == nil {
            add(.noBody)
        }

        if let primary = faces.first,
           isOccluded(face: primary, captureQuality: captureQuality) {
            add(.occlusion)
        }
        if meanLuma < configuration.lowLightMeanLuma {
            add(.lowLight)
        }
        if confidence < configuration.lowConfidenceThreshold {
            add(.lowConfidence)
        }
        if failedStages.count >= 2 {
            add(.lowConfidence)
        }
        if skinLowConfidence {
            add(.lowConfidence)
        }
        if failedStages.contains(.personSegmentation), !faces.isEmpty {
            add(.lowConfidence)
        }
        return warnings
    }

    private static func isOccluded(face: FaceObservation, captureQuality: Float?) -> Bool {
        if let captureQuality, captureQuality < 0.25 {
            return true
        }
        if face.landmarks.count < 4 {
            return true
        }
        let box = face.boundingBox
        return box.x <= 0.005
            || box.y <= 0.005
            || box.maxX >= 0.995
            || box.maxY >= 0.995
    }
}
