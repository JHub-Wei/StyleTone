import Foundation
import StyleToneCore

/// Deterministic, local style learner for `StyleProfile` schema 3.
///
/// The engine consumes original/edited pairs plus optional AB answers and
/// emits a conservative, personal profile. It never uploads, logs or persists
/// pixels; sampled proxies live only for the duration of one call.
///
/// Pipeline:
/// 1. Filter rejected pairs, decode the rest into small sRGB proxies.
/// 2. Fit tone, white balance and saturation per pair; estimate retouch
///    strength from skin texture loss and optional caller signals.
/// 3. Aggregate with weighted medians and robust down-weighting of outliers.
/// 4. Validate with leave-one-out; shrink 3/5/8 toward neutral.
/// 5. Apply 6–8 AB preferences as small bounded nudges.
/// 6. Clamp to ``StyleSafetyRanges`` and assign confidence/tags.
///
/// Cancellation is checked between pairs and propagates as
/// `CancellationError`; no partial profile is returned.
///
/// - Note: The engine does no face/body detection. Geometry strengths are only
///   learned from explicit ``PairStrengthSignals`` or AB preferences.
public struct StyleLearningEngine: StyleLearning, Sendable {
    /// Sampling and safety configuration.
    public let configuration: StyleLearningConfiguration
    private let dateProvider: any DateProviding

    /// Creates an engine.
    /// - Parameters:
    ///   - configuration: Sampling, thresholds and safety envelope.
    ///   - dateProvider: Clock used for `StyleProfile.updatedAt`.
    public init(
        configuration: StyleLearningConfiguration = .standard,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.configuration = configuration
        self.dateProvider = dateProvider
    }

    /// `StyleLearning` entry point. Use ``learn(_:)`` when per-pair strength
    /// signals or diagnostics are needed.
    public func learn(
        samples: [PairSample],
        answers: [CalibrationAnswer]
    ) async throws -> StyleProfile {
        try await learn(
            StyleLearningRequest(samples: samples, answers: answers)
        ).profile
    }

    /// Learns a profile and returns fit diagnostics.
    ///
    /// Abnormal input never crashes: rejected pairs are skipped, unreadable
    /// pairs are skipped, and a request with no usable pair returns a neutral
    /// trial profile so the UI can fall back to the natural default.
    public func learn(_ request: StyleLearningRequest) async throws -> StyleLearningResult {
        try Task.checkCancellation()

        var issues = Set<StyleLearningIssue>()
        var pairFits = [PairFit]()
        var rejectedPairCount = 0
        var skippedPairCount = 0
        var qualityWeights = [Double]()
        var skinFractions = [Double]()
        var skinProtectionApplied = false
        var pairIssues = Set<StyleLearningIssue>()

        for sample in request.samples {
            try Task.checkCancellation()

            if sample.quality.grade == .rejected {
                rejectedPairCount += 1
                issues.insert(.rejectedPair)
                continue
            }

            let qualityWeight = Self.qualityWeight(sample.quality)
            if sample.quality.grade == .warning {
                issues.insert(.lowQualityPair)
            }

            do {
                let originalImage = try NumericImageLoader.load(
                    sample.original,
                    maximumEdge: configuration.maximumAnalysisEdge
                )
                let editedImage = try NumericImageLoader.load(
                    sample.edited,
                    maximumEdge: configuration.maximumAnalysisEdge
                )
                let originalStats = ImageStatistics.analyze(originalImage)
                let editedStats = ImageStatistics.analyze(editedImage)

                var pairWeight = qualityWeight
                if Self.aspectRatiosMismatch(originalImage, editedImage) {
                    pairWeight *= 0.5
                    issues.insert(.mismatchedPair)
                }

                guard let tone = ToneFitter.fit(
                    original: originalStats,
                    edited: editedStats,
                    qualityWeight: pairWeight,
                    configuration: configuration
                ) else {
                    skippedPairCount += 1
                    issues.insert(.unreadablePair)
                    continue
                }

                let strength = StrengthFitter.fit(
                    original: originalStats,
                    edited: editedStats,
                    signals: request.strengthSignals[sample.id],
                    qualityWeight: pairWeight,
                    configuration: configuration
                )

                guard tone.weight > 1e-6 || strength.weight > 1e-6 else {
                    skippedPairCount += 1
                    continue
                }

                let fit = PairFit(
                    id: sample.id,
                    tone: tone.tone,
                    skin: strength.skin,
                    face: strength.face,
                    body: strength.body,
                    finish: strength.finish,
                    toneWeight: tone.weight,
                    strengthWeight: strength.weight,
                    skinFraction: (originalStats.skinFraction + editedStats.skinFraction) / 2,
                    skinProtectionApplied: tone.skinProtectionApplied,
                    issues: tone.issues.union(strength.issues)
                )
                pairFits.append(fit)
                pairIssues.formUnion(fit.issues)
                qualityWeights.append(Self.qualityWeight(sample.quality))
                skinFractions.append(fit.skinFraction)
                skinProtectionApplied = skinProtectionApplied || fit.skinProtectionApplied
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedPairCount += 1
                issues.insert(.unreadablePair)
            }
        }

        issues.formUnion(pairIssues)
        let answeredCount = request.answers.filter { $0.strengthDelta.isFinite }.count

        if pairFits.isEmpty {
            if !request.samples.isEmpty {
                issues.insert(.noValidPairs)
            }
            if request.samples.isEmpty, answeredCount > 0 {
                issues.insert(.abOnly)
            }
            issues.insert(.holdoutUnavailable)

            let adjustment = ABPreferenceFitter.adjustment(
                answers: request.answers,
                configuration: configuration
            )
            let output = ProfileAssembler.assemble(
                style: .neutral,
                shrinkFactor: 1,
                adjustment: adjustment,
                pairCount: 0,
                confidence: .trial,
                date: dateProvider.now,
                safety: configuration.safety
            )
            if output.safetyClamped {
                issues.insert(.safetyClamped)
            }

            let diagnostics = StyleLearningDiagnostics(
                acceptedPairCount: 0,
                rejectedPairCount: rejectedPairCount,
                skippedPairCount: skippedPairCount,
                answeredCount: answeredCount,
                holdoutError: 1,
                meanQuality: 0,
                shrinkage: 0,
                skinFraction: 0,
                skinProtectionApplied: false,
                issues: Array(issues)
            )
            return StyleLearningResult(profile: output.profile, diagnostics: diagnostics)
        }

        try Task.checkCancellation()

        let safety = configuration.safety
        let aggregated = PairAggregator.aggregate(pairFits, safety: safety)
        if aggregated.outlierCount > 0 {
            issues.insert(.outlierPair)
        }

        let holdout = HoldoutValidator.leaveOneOut(pairs: pairFits, safety: safety)
        if !holdout.isAvailable {
            issues.insert(.holdoutUnavailable)
        }
        if holdout.error > configuration.standardHoldoutError {
            issues.insert(.highHoldoutError)
        }

        let meanQuality = qualityWeights.isEmpty
            ? 0
            : qualityWeights.reduce(0, +) / Double(qualityWeights.count)
        let meanSkin = skinFractions.isEmpty
            ? 0
            : skinFractions.reduce(0, +) / Double(skinFractions.count)
        let shrinkage = ShrinkageModel.factor(
            acceptedPairCount: pairFits.count,
            holdoutError: holdout.error,
            meanQuality: meanQuality
        )
        let confidence = ConfidenceModel.level(
            acceptedPairCount: pairFits.count,
            holdoutError: holdout.error,
            meanQuality: meanQuality,
            configuration: configuration
        )
        let adjustment = ABPreferenceFitter.adjustment(
            answers: request.answers,
            configuration: configuration
        )

        let output = ProfileAssembler.assemble(
            style: aggregated,
            shrinkFactor: shrinkage,
            adjustment: adjustment,
            pairCount: pairFits.count,
            confidence: confidence,
            date: dateProvider.now,
            safety: safety
        )
        if output.safetyClamped {
            issues.insert(.safetyClamped)
        }
        if skinProtectionApplied {
            issues.insert(.skinToneGuarded)
        }

        let diagnostics = StyleLearningDiagnostics(
            acceptedPairCount: pairFits.count,
            rejectedPairCount: rejectedPairCount,
            skippedPairCount: skippedPairCount,
            answeredCount: answeredCount,
            holdoutError: holdout.error,
            meanQuality: meanQuality,
            shrinkage: shrinkage,
            skinFraction: meanSkin,
            skinProtectionApplied: skinProtectionApplied,
            issues: Array(issues)
        )
        return StyleLearningResult(profile: output.profile, diagnostics: diagnostics)
    }

    // MARK: - Helpers

    private static func qualityWeight(_ quality: PairQuality) -> Double {
        let grade: Double
        switch quality.grade {
        case .good:
            grade = 1
        case .warning:
            grade = 0.55
        case .rejected:
            grade = 0
        }
        let confidence = Double(min(max(quality.confidence, 0), 1))
        return LearningMath.unit(grade * confidence)
    }

    private static func aspectRatiosMismatch(_ first: NumericImage, _ second: NumericImage) -> Bool {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0 else {
            return true
        }
        let firstRatio = Double(first.width) / Double(first.height)
        let secondRatio = Double(second.width) / Double(second.height)
        return abs(log(max(firstRatio, 1e-6) / max(secondRatio, 1e-6))) > 0.25
    }
}
