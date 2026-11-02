import Foundation
import StyleToneLearning

/// One automatic read of what changed between an original and its edit.
///
/// Signals are optional per dimension: a portrait pair can teach face slim
/// without a usable body mask, or skin smoothing without a face contour.
public struct PairEditAnalysis: Sendable, Equatable {
    public var signals: PairStrengthSignals
    /// Aggregate confidence across the dimensions that produced a signal.
    public var confidence: Double
    /// Non-fatal reasons a dimension was skipped.
    public var issues: [PairEditIssue]

    public init(
        signals: PairStrengthSignals,
        confidence: Double,
        issues: [PairEditIssue] = []
    ) {
        self.signals = signals
        self.confidence = min(max(confidence, 0), 1)
        self.issues = issues
    }

    public var hasAnySignal: Bool {
        signals.smoothing != nil
            || signals.evenness != nil
            || signals.blemish != nil
            || signals.faceSlim != nil
            || signals.jaw != nil
            || signals.arm != nil
            || signals.waist != nil
            || signals.leg != nil
            || signals.legLength != nil
    }
}

public enum PairEditIssue: String, Sendable, Equatable, CaseIterable {
    case noFace
    case noBody
    case noSkin
    case lowConfidence
    case dimensionMismatch
}

/// Extracts edit strengths directly from an original/edited pair.
public protocol PairEditAnalyzing: Sendable {
    func analyze(
        original: ImageAsset,
        edited: ImageAsset
    ) async throws -> PairEditAnalysis
}
