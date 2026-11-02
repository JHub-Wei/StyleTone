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
                    signals[sample.id] = analysis.signals
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
}
