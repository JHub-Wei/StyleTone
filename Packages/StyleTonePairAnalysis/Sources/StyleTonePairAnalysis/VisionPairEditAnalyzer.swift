import Foundation
import StyleToneCore
import StyleToneLearning
import StyleToneVision

/// Vision-based pair analyzer for P0 automatic style signals.
///
/// It never stores pixels or face templates. The analyzer sees the same
/// bounded proxy as the editor, compares normalised face/body geometry, and
/// measures texture only inside the face skin mask. Missing detections degrade
/// to partial signals instead of failing the calibration.
public struct VisionPairEditAnalyzer: PairEditAnalyzing {
    private let portraitAnalyzer: any PortraitAnalyzing

    public init(portraitAnalyzer: any PortraitAnalyzing = VisionPortraitAnalyzer()) {
        self.portraitAnalyzer = portraitAnalyzer
    }

    public func analyze(
        original: ImageAsset,
        edited: ImageAsset
    ) async throws -> PairEditAnalysis {
        async let originalAnalysis = portraitAnalyzer.analyze(original)
        async let editedAnalysis = portraitAnalyzer.analyze(edited)
        let (originalPortrait, editedPortrait) = try await (
            originalAnalysis,
            editedAnalysis
        )

        var signals = PairStrengthSignals()
        var issues: [PairEditIssue] = []
        var confidences: [Double] = []

        if let face = FaceEditMetrics.compare(
            original: originalPortrait.primaryFace,
            edited: editedPortrait.primaryFace
        ) {
            signals.faceSlim = face.slim
            signals.jaw = face.jaw
            confidences.append(face.confidence)
        } else {
            issues.append(.noFace)
        }

        if let body = BodyEditMetrics.compare(
            original: originalPortrait,
            edited: editedPortrait
        ) {
            signals.arm = body.arm
            signals.waist = body.waist
            signals.leg = body.leg
            signals.legLength = body.legLength
            confidences.append(body.confidence)
        } else {
            issues.append(.noBody)
        }

        if let skin = try SkinEditMetrics.compare(
            original: originalPortrait,
            edited: editedPortrait,
            originalImage: original,
            editedImage: edited
        ) {
            signals.smoothing = skin.smoothing
            signals.evenness = skin.evenness
            signals.blemish = skin.blemish
            confidences.append(skin.confidence)
        } else {
            issues.append(.noSkin)
        }

        if original.pixelSize.aspectRatio.isFinite,
           edited.pixelSize.aspectRatio.isFinite,
           abs(original.pixelSize.aspectRatio - edited.pixelSize.aspectRatio) > 0.02 {
            issues.append(.dimensionMismatch)
        }

        let confidence = confidences.isEmpty
            ? 0
            : confidences.reduce(0, +) / Double(confidences.count)
        if confidence < 0.2 {
            issues.append(.lowConfidence)
        }

        return PairEditAnalysis(
            signals: signals,
            confidence: confidence,
            issues: issues
        )
    }
}
