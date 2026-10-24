import CoreGraphics
import Foundation
import StyleToneCore

/// Vision-backed implementation of ``PortraitAnalyzing``.
///
/// The analyzer runs on a bounded proxy (1024 px long edge by default) in a
/// detached task, converts every Vision coordinate to the top-left normalized
/// convention, and resamples segmentation/skin/structure masks back to the
/// input's pixel size. It never identifies people, stores face templates, or
/// logs image content.
///
/// When a detector fails or finds nothing, the analyzer degrades: it returns
/// the masks it could produce, adds the matching ``AnalysisWarning``, and
/// lowers confidence instead of throwing. Only an unusable input image throws.
public struct VisionPortraitAnalyzer: PortraitAnalyzing {
    public let configuration: VisionAnalysisConfiguration

    public init(configuration: VisionAnalysisConfiguration = VisionAnalysisConfiguration()) {
        self.configuration = configuration
    }

    public func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        try await analyzeDetailed(image).analysis
    }

    /// Runs the full pipeline and returns confidence plus diagnostics.
    ///
    /// Use this entry point in editors that need an aggregate confidence for a
    /// warning banner; ``analyze(_:)`` remains the protocol-compliant API.
    public func analyzeDetailed(_ image: ImageAsset) async throws -> VisionPortraitAnalysisResult {
        let configuration = self.configuration
        let task = Task.detached(priority: .userInitiated) {
            try VisionPortraitAnalysisPipeline(configuration: configuration).run(image: image)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private struct VisionPortraitAnalysisPipeline {
    let configuration: VisionAnalysisConfiguration

    func run(image: ImageAsset) throws -> VisionPortraitAnalysisResult {
        let clock = ContinuousClock()
        let start = clock.now
        let targetSize = image.pixelSize
        guard targetSize.isPositive else {
            throw StyleToneError.invalidImage
        }

        let proxy = try AnalysisImageProxy.make(
            image: image,
            maximumLongEdge: configuration.maximumAnalysisDimension
        )
        try Task.checkCancellation()

        var failedStages: [VisionAnalysisStage] = []

        let faceOutcome = VisionFaceDetector.detect(
            in: proxy.cgImage,
            configuration: configuration
        )
        if faceOutcome.failed {
            failedStages.append(.faceDetection)
        }
        try Task.checkCancellation()

        let bodyOutcome = VisionBodyPoseDetector.detect(
            in: proxy.cgImage,
            configuration: configuration
        )
        if bodyOutcome.failed {
            failedStages.append(.bodyPose)
        }
        try Task.checkCancellation()

        let segmentationOutcome = VisionPersonSegmenter.segment(
            in: proxy.cgImage,
            proxySize: proxy.proxySize,
            configuration: configuration
        )
        if segmentationOutcome.failed {
            failedStages.append(.personSegmentation)
        }
        try Task.checkCancellation()

        var skinOutcome: SkinMaskResult?
        if configuration.skinMaskEnabled, !faceOutcome.faces.isEmpty {
            do {
                skinOutcome = try SkinMaskBuilder().build(
                    linearImage: proxy.linearImage,
                    faces: faceOutcome.faces
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedStages.append(.skinMask)
            }
        }
        try Task.checkCancellation()

        var backgroundOutcome: BackgroundEdgeMaskResult?
        if configuration.backgroundMaskEnabled {
            do {
                backgroundOutcome = try BackgroundEdgeMaskBuilder().build(
                    linearImage: proxy.linearImage,
                    personMask: segmentationOutcome.mask
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedStages.append(.backgroundStructure)
            }
        }
        try Task.checkCancellation()

        let meanLuma = ImageStatistics.meanEncodedLuma(linearImage: proxy.linearImage)
        let confidence = makeConfidence(
            faces: faceOutcome.faces,
            body: bodyOutcome.body,
            segmentation: segmentationOutcome,
            skin: skinOutcome,
            failedStages: failedStages,
            meanLuma: meanLuma
        )
        let warnings = PortraitWarningBuilder.build(
            faces: faceOutcome.faces,
            body: bodyOutcome.body,
            captureQuality: faceOutcome.primaryCaptureQuality,
            skinLowConfidence: skinOutcome?.lowConfidence ?? false,
            failedStages: failedStages,
            confidence: confidence,
            meanLuma: meanLuma,
            configuration: configuration
        )

        let personMask = try segmentationOutcome.mask.map {
            try MaskResampler.resample($0, to: targetSize)
        }
        let skinMask = try skinOutcome.map {
            try MaskResampler.resample($0.mask, to: targetSize)
        }
        let backgroundMask = try backgroundOutcome.map {
            try MaskResampler.resample($0.mask, to: targetSize)
        }
        try Task.checkCancellation()

        let analysis = PortraitAnalysis(
            imageSize: targetSize,
            faces: faceOutcome.faces,
            body: bodyOutcome.body,
            personMask: personMask,
            skinMask: skinMask,
            backgroundEdgeMask: backgroundMask,
            warnings: warnings
        )

        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        let diagnostics = VisionAnalysisDiagnostics(
            proxySize: proxy.proxySize,
            duration: seconds,
            detectedFaceCount: faceOutcome.faces.count,
            detectedBodyJointCount: bodyOutcome.body?.joints.count ?? 0,
            personCoverage: segmentationOutcome.coverage,
            skinCoverage: skinOutcome?.coverage ?? 0,
            backgroundEdgeRatio: backgroundOutcome?.edgeRatio ?? 0,
            meanLuma: meanLuma,
            failedStages: failedStages
        )
        return VisionPortraitAnalysisResult(
            analysis: analysis,
            confidence: confidence,
            diagnostics: diagnostics
        )
    }

    private func makeConfidence(
        faces: [FaceObservation],
        body: BodyObservation?,
        segmentation: PersonSegmentationOutcome,
        skin: SkinMaskResult?,
        failedStages: [VisionAnalysisStage],
        meanLuma: Double
    ) -> Float {
        var confidence: Float = 0
        if let primary = faces.first {
            confidence += 0.55 * primary.confidence
        }
        if let body {
            confidence += 0.25 * body.confidence
        }
        confidence += 0.20 * Float(min(1, segmentation.coverage / 0.25))

        if faces.isEmpty, body == nil {
            confidence = min(confidence, 0.15)
        }
        if !failedStages.isEmpty {
            confidence *= 0.88
        }
        if skin?.lowConfidence == true {
            confidence *= 0.92
        }
        if meanLuma < configuration.lowLightMeanLuma {
            confidence *= 0.85
        }
        return min(max(confidence, 0), 1)
    }
}

