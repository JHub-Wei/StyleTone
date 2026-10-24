import Foundation
import StyleToneCore

/// Quality level requested from Vision's person segmentation.
///
/// This mirrors `VNGeneratePersonSegmentationRequest.QualityLevel` without
/// exposing Vision in the public API, so callers can configure the analyzer on
/// platforms where Vision is an implementation detail.
public enum VisionSegmentationQuality: String, Sendable, Codable, CaseIterable {
    case fast
    case balanced
    case accurate
}

/// Tuning knobs for ``VisionPortraitAnalyzer``.
///
/// Defaults target the 1024 px proxy budget in the contracts: analysis runs on
/// a downscaled proxy while masks are resampled back to the original image.
public struct VisionAnalysisConfiguration: Sendable, Equatable {
    /// Longest edge of the proxy Vision runs on. Larger inputs are downscaled.
    public var maximumAnalysisDimension: Int

    /// Faces below this Vision confidence are ignored.
    public var minimumFaceConfidence: Float

    /// Faces smaller than this fraction of the image are ignored (noise).
    public var minimumFaceAreaFraction: Double

    /// Upper bound on returned faces; largest faces are kept.
    public var maximumFaceCount: Int

    /// Body poses below this average joint confidence are discarded.
    public var minimumBodyConfidence: Float

    /// Minimum number of recognized joints required to return a body.
    public var minimumBodyJointCount: Int

    /// Segmentation coverage below this fraction is treated as "no person".
    public var minimumPersonCoverage: Double

    /// Person segmentation quality/speed trade-off.
    public var segmentationQuality: VisionSegmentationQuality

    /// Whether to run person segmentation at all.
    public var personSegmentationEnabled: Bool

    /// Whether to build the skin probability mask when a face exists.
    public var skinMaskEnabled: Bool

    /// Whether to build the background edge/line mask.
    public var backgroundMaskEnabled: Bool

    /// Images with a mean encoded luma below this value get ``AnalysisWarning/lowLight``.
    public var lowLightMeanLuma: Double

    /// Overall confidence below which ``AnalysisWarning/lowConfidence`` is added.
    public var lowConfidenceThreshold: Float

    public init(
        maximumAnalysisDimension: Int = 1024,
        minimumFaceConfidence: Float = 0.30,
        minimumFaceAreaFraction: Double = 0.0012,
        maximumFaceCount: Int = 8,
        minimumBodyConfidence: Float = 0.25,
        minimumBodyJointCount: Int = 5,
        minimumPersonCoverage: Double = 0.002,
        segmentationQuality: VisionSegmentationQuality = .balanced,
        personSegmentationEnabled: Bool = true,
        skinMaskEnabled: Bool = true,
        backgroundMaskEnabled: Bool = true,
        lowLightMeanLuma: Double = 0.18,
        lowConfidenceThreshold: Float = 0.45
    ) {
        self.maximumAnalysisDimension = max(128, maximumAnalysisDimension)
        self.minimumFaceConfidence = min(max(minimumFaceConfidence, 0), 1)
        self.minimumFaceAreaFraction = min(max(minimumFaceAreaFraction, 0), 1)
        self.maximumFaceCount = max(1, maximumFaceCount)
        self.minimumBodyConfidence = min(max(minimumBodyConfidence, 0), 1)
        self.minimumBodyJointCount = max(1, minimumBodyJointCount)
        self.minimumPersonCoverage = min(max(minimumPersonCoverage, 0), 1)
        self.segmentationQuality = segmentationQuality
        self.personSegmentationEnabled = personSegmentationEnabled
        self.skinMaskEnabled = skinMaskEnabled
        self.backgroundMaskEnabled = backgroundMaskEnabled
        self.lowLightMeanLuma = min(max(lowLightMeanLuma, 0), 1)
        self.lowConfidenceThreshold = min(max(lowConfidenceThreshold, 0), 1)
    }
}

/// A stage of the analysis pipeline that degraded instead of failing the image.
public enum VisionAnalysisStage: String, Sendable, Codable, CaseIterable {
    case faceDetection
    case bodyPose
    case personSegmentation
    case skinMask
    case backgroundStructure
}

/// Non-identifying diagnostics for one analysis run.
///
/// The values describe image geometry and detector coverage only. They never
/// contain landmarks, file names, identifiers or pixel data.
public struct VisionAnalysisDiagnostics: Sendable, Equatable {
    public let proxySize: PixelSize
    public let duration: TimeInterval
    public let detectedFaceCount: Int
    public let detectedBodyJointCount: Int
    public let personCoverage: Double
    public let skinCoverage: Double
    public let backgroundEdgeRatio: Double
    public let meanLuma: Double
    public let failedStages: [VisionAnalysisStage]

    public init(
        proxySize: PixelSize,
        duration: TimeInterval,
        detectedFaceCount: Int,
        detectedBodyJointCount: Int,
        personCoverage: Double,
        skinCoverage: Double,
        backgroundEdgeRatio: Double,
        meanLuma: Double,
        failedStages: [VisionAnalysisStage]
    ) {
        self.proxySize = proxySize
        self.duration = duration
        self.detectedFaceCount = detectedFaceCount
        self.detectedBodyJointCount = detectedBodyJointCount
        self.personCoverage = personCoverage
        self.skinCoverage = skinCoverage
        self.backgroundEdgeRatio = backgroundEdgeRatio
        self.meanLuma = meanLuma
        self.failedStages = failedStages
    }
}

/// ``PortraitAnalysis`` plus the aggregate confidence the Core struct cannot
/// carry.
///
/// `PortraitAnalysis` is frozen, so the analyzer exposes confidence and
/// diagnostics alongside it. ``VisionPortraitAnalyzer/analyze(_:)`` returns
/// the contract type only; use ``VisionPortraitAnalyzer/analyzeDetailed(_:)``
/// when the caller wants diagnostics.
public struct VisionPortraitAnalysisResult: Sendable {
    public let analysis: PortraitAnalysis
    public let confidence: Float
    public let diagnostics: VisionAnalysisDiagnostics

    public init(
        analysis: PortraitAnalysis,
        confidence: Float,
        diagnostics: VisionAnalysisDiagnostics
    ) {
        self.analysis = analysis
        self.confidence = min(max(confidence, 0), 1)
        self.diagnostics = diagnostics
    }
}
