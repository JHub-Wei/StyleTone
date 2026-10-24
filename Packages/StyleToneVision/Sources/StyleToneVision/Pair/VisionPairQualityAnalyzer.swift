import Foundation
import StyleToneCore

/// Vision-backed implementation of ``PairQualityAnalyzing``.
///
/// The gate combines four signals:
///
/// 1. **Semantic similarity** from `VNGenerateImageFeaturePrintRequest`.
/// 2. **Translation registration** via normalized cross-correlation.
/// 3. **Resolution and aspect ratio** of the original/edited pair.
/// 4. **Structural delta** from edge orientation after registration.
///
/// A pair is `good` only when every signal is inside its warning band. The
/// comparison runs off the caller's actor and never stores images or feature
/// prints.
public struct VisionPairQualityAnalyzer: PairQualityAnalyzing {
    public let configuration: VisionPairQualityConfiguration

    public init(configuration: VisionPairQualityConfiguration = VisionPairQualityConfiguration()) {
        self.configuration = configuration
    }

    public func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        try await assessDetailed(original: original, edited: edited).quality
    }

    /// Returns the grade plus the numeric metrics behind it.
    public func assessDetailed(
        original: ImageAsset,
        edited: ImageAsset
    ) async throws -> VisionPairQualityResult {
        let configuration = self.configuration
        let task = Task.detached(priority: .userInitiated) {
            try PairQualityPipeline(configuration: configuration).run(
                original: original,
                edited: edited
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private struct PairQualityPipeline {
    let configuration: VisionPairQualityConfiguration

    func run(original: ImageAsset, edited: ImageAsset) throws -> VisionPairQualityResult {
        let clock = ContinuousClock()
        let start = clock.now
        guard original.pixelSize.isPositive, edited.pixelSize.isPositive else {
            throw StyleToneError.invalidImage
        }

        let originalLongEdge = Double(max(1, original.pixelSize.longEdge))
        let editedLongEdge = Double(max(1, edited.pixelSize.longEdge))
        let resolutionRatio = min(1, editedLongEdge / originalLongEdge)

        let originalAspect = original.pixelSize.aspectRatio
        let editedAspect = edited.pixelSize.aspectRatio
        let aspectRatioDelta = abs(originalAspect - editedAspect) / max(originalAspect, 0.0001)

        let originalProxy = try AnalysisImageProxy.make(
            image: original,
            maximumLongEdge: configuration.maximumAnalysisDimension
        )
        let editedProxy = try AnalysisImageProxy.make(
            image: edited,
            maximumLongEdge: configuration.maximumAnalysisDimension
        )
        try Task.checkCancellation()

        let semanticSimilarity = try? FeaturePrintSimilarity.similarity(
            between: originalProxy.cgImage,
            and: editedProxy.cgImage
        )
        try Task.checkCancellation()

        let registration = try TranslationRegistration.estimate(
            original: originalProxy.linearImage,
            edited: editedProxy.linearImage,
            dimension: configuration.registrationDimension
        )
        try Task.checkCancellation()

        let scaleToStructure = Double(configuration.structureDimension)
        let shiftX = Int(((registration?.offsetX ?? 0) * scaleToStructure).rounded())
        let shiftY = Int(((registration?.offsetY ?? 0) * scaleToStructure).rounded())
        let structure = try StructuralDifference.compare(
            original: originalProxy.linearImage,
            edited: editedProxy.linearImage,
            shiftX: shiftX,
            shiftY: shiftY,
            dimension: configuration.structureDimension
        )
        try Task.checkCancellation()

        let elapsed = clock.now - start
        let duration = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        let metrics = VisionPairQualityMetrics(
            originalSize: original.pixelSize,
            editedSize: edited.pixelSize,
            resolutionRatio: resolutionRatio,
            aspectRatioDelta: aspectRatioDelta,
            semanticSimilarity: semanticSimilarity,
            registrationOffset: registration?.magnitude,
            registrationConfidence: registration?.peak,
            structureDelta: structure?.delta,
            usedFeaturePrint: semanticSimilarity != nil,
            duration: duration
        )
        let quality = PairQualityClassifier.classify(
            metrics: metrics,
            configuration: configuration
        )
        return VisionPairQualityResult(quality: quality, metrics: metrics)
    }
}
