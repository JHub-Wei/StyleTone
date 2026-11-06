import Foundation
import StyleToneCore
import StyleToneLearning

/// Decorates the real learner with automatic pair signals.
///
/// Calibration still uses the frozen `StyleLearning` protocol, so the UI does
/// not need to know whether strengths came from a pair analyzer, A/B answers,
/// or both. A/B answers remain in the request and are applied as a refinement.
public struct AutoSignalStyleLearning: StyleLearning {
    private let engine: StyleLearningEngine
    private let analyzer: any PairEditAnalyzing

    public init(
        engine: StyleLearningEngine = StyleLearningEngine(),
        analyzer: any PairEditAnalyzing = VisionPairEditAnalyzer()
    ) {
        self.engine = engine
        self.analyzer = analyzer
    }

    public func learn(
        samples: [PairSample],
        answers: [CalibrationAnswer]
    ) async throws -> StyleProfile {
        var signals: [UUID: PairStrengthSignals] = [:]

        for sample in samples {
            try Task.checkCancellation()
            do {
                let analysis = try await analyzer.analyze(
                    original: sample.original,
                    edited: sample.edited
                )
                if analysis.hasAnySignal {
                    signals[sample.id] = visible(signals: analysis.signals)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failed pair must not fail calibration; the learner still
                // has tone/texture statistics and any A/B answers.
                continue
            }
        }

        try Task.checkCancellation()
        return try await engine.learn(
            StyleLearningRequest(
                samples: samples,
                answers: answers,
                strengthSignals: signals
            )
        ).profile
    }

    /// Keeps a measured edit visible after the 3-pair shrink schedule.
    ///
    /// Three pairs shrink every parameter by roughly half, and a subtle
    /// measurement can round to an invisible profile. When a dimension has any
    /// real evidence, raise it to a conservative visible floor; zero evidence
    /// stays zero.
    private func visible(signals: PairStrengthSignals) -> PairStrengthSignals {
        var result = signals
        if let value = result.smoothing, value > 0.02 {
            result.smoothing = max(value, 0.50)
        }
        if let value = result.evenness, value > 0.02 {
            result.evenness = max(value, 0.35)
        }
        if let value = result.blemish, value > 0.02 {
            result.blemish = max(value, 0.30)
        }
        if let value = result.faceSlim, value > 0.02 {
            result.faceSlim = max(value, 0.55)
        }
        if let value = result.jaw, value > 0.02 {
            result.jaw = max(value, 0.45)
        }
        if let value = result.arm, value > 0.02 {
            result.arm = max(value, 0.45)
        }
        if let value = result.waist, value > 0.02 {
            result.waist = max(value, 0.50)
        }
        if let value = result.leg, value > 0.02 {
            result.leg = max(value, 0.45)
        }
        if let value = result.legLength, value > 1.01 {
            result.legLength = max(value, 1.04)
        }
        return result
    }
}
