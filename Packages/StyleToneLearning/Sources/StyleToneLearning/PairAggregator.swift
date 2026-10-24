import Foundation
import StyleToneCore

/// Combined per-pair estimate used by aggregation and hold-out validation.
struct PairFit: Sendable {
    let id: UUID
    let tone: ToneParameters
    let skin: SkinParameters
    let face: FaceParameters
    let body: BodyParameters
    let finish: FinishParameters
    let toneWeight: Double
    let strengthWeight: Double
    let skinFraction: Double
    let skinProtectionApplied: Bool
    let issues: Set<StyleLearningIssue>
}

/// Aggregated, unshrunk parameters.
struct AggregatedStyle: Sendable, Equatable {
    var tone: ToneParameters
    var skin: SkinParameters
    var face: FaceParameters
    var body: BodyParameters
    var finish: FinishParameters
    var outlierCount: Int

    static let neutral = AggregatedStyle(
        tone: .neutral,
        skin: .neutral,
        face: .neutral,
        body: .neutral,
        finish: .neutral,
        outlierCount: 0
    )
}

/// Robust aggregation across pairs.
///
/// The estimator starts with quality-weighted means, then performs four
/// reweighting passes: a pair whose parameter vector is far from the current
/// consensus gets an exponentially smaller weight. Unlike a plain median, this
/// stays symmetric when the user has two equally supported looks, while a
/// single mis-edited export is still down-weighted almost to zero. Warning
/// pairs keep their reduced base weight.
enum PairAggregator {
    static func aggregate(
        _ pairs: [PairFit],
        safety: StyleSafetyRanges
    ) -> AggregatedStyle {
        let usable = pairs.filter {
            $0.toneWeight > 1e-8 || $0.strengthWeight > 1e-8
        }
        guard !usable.isEmpty else { return .neutral }

        var factors = Dictionary(
            uniqueKeysWithValues: usable.map { ($0.id, 1.0) }
        )
        var aggregate = values(of: usable, factors: factors, safety: safety)

        for _ in 0..<4 {
            var updated: [UUID: Double] = [:]
            updated.reserveCapacity(usable.count)
            for pair in usable {
                let distance = normalizedDistance(
                    pair: pair,
                    aggregate: aggregate,
                    safety: safety
                )
                let factor = 1 / (1 + pow(distance / 0.6, 2))
                updated[pair.id] = max(factor, 0.05)
            }
            factors = updated
            aggregate = values(of: usable, factors: factors, safety: safety)
        }

        let outlierCount = factors.values.filter { $0 < 0.4 }.count
        aggregate.outlierCount = outlierCount
        return aggregate
    }

    /// Normalised RMS distance between one pair and an aggregate, `0...2`-ish.
    /// Each component is divided by its safety range so tone and strength
    /// parameters contribute comparably.
    static func normalizedDistance(
        pair: PairFit,
        aggregate: AggregatedStyle,
        safety: StyleSafetyRanges
    ) -> Double {
        let toneScales = [
            safety.exposure,
            safety.contrast,
            safety.highlights,
            safety.shadows,
            safety.temperature,
            safety.tint,
            safety.saturation
        ].map { max($0, 0.01) }
        let toneDifferences = [
            abs(pair.tone.exposure - aggregate.tone.exposure) / toneScales[0],
            abs(pair.tone.contrast - aggregate.tone.contrast) / toneScales[1],
            abs(pair.tone.highlights - aggregate.tone.highlights) / toneScales[2],
            abs(pair.tone.shadows - aggregate.tone.shadows) / toneScales[3],
            abs(pair.tone.temperature - aggregate.tone.temperature) / toneScales[4],
            abs(pair.tone.tint - aggregate.tone.tint) / toneScales[5],
            abs(pair.tone.saturation - aggregate.tone.saturation) / toneScales[6]
        ]
        let strengthScales = [
            safety.smoothing,
            safety.evenness,
            safety.blemish,
            safety.faceSlim,
            safety.jaw,
            safety.arm,
            safety.waist,
            safety.leg,
            max(safety.legLengthMax - 1, 0.01),
            safety.grain,
            abs(safety.vignetteMin)
        ].map { max($0, 0.01) }
        let strengthDifferences = [
            abs(pair.skin.smoothing - aggregate.skin.smoothing) / strengthScales[0],
            abs(pair.skin.evenness - aggregate.skin.evenness) / strengthScales[1],
            abs(pair.skin.blemish - aggregate.skin.blemish) / strengthScales[2],
            abs(pair.face.slim - aggregate.face.slim) / strengthScales[3],
            abs(pair.face.jaw - aggregate.face.jaw) / strengthScales[4],
            abs(pair.body.arm - aggregate.body.arm) / strengthScales[5],
            abs(pair.body.waist - aggregate.body.waist) / strengthScales[6],
            abs(pair.body.leg - aggregate.body.leg) / strengthScales[7],
            abs(pair.body.legLength - aggregate.body.legLength) / strengthScales[8],
            abs(pair.finish.grain - aggregate.finish.grain) / strengthScales[9],
            abs(pair.finish.vignette - aggregate.finish.vignette) / strengthScales[10]
        ]

        let all = (toneDifferences + strengthDifferences).map { min(max($0, 0), 2) }
        let top = all.sorted(by: >).prefix(5)
        let meanSquare = top.reduce(0) { $0 + $1 * $1 } / Double(top.count)
        return meanSquare.squareRoot()
    }

    // MARK: - Weighted parameter values

    private static func values(
        of pairs: [PairFit],
        factors: [UUID: Double],
        safety: StyleSafetyRanges
    ) -> AggregatedStyle {
        let tone = ToneParameters(
            exposure: mean(pairs.map { ($0.tone.exposure, $0.toneWeight * factor($0, factors)) }),
            contrast: mean(pairs.map { ($0.tone.contrast, $0.toneWeight * factor($0, factors)) }),
            highlights: mean(pairs.map { ($0.tone.highlights, $0.toneWeight * factor($0, factors)) }),
            shadows: mean(pairs.map { ($0.tone.shadows, $0.toneWeight * factor($0, factors)) }),
            temperature: mean(pairs.map { ($0.tone.temperature, $0.toneWeight * factor($0, factors)) }),
            tint: mean(pairs.map { ($0.tone.tint, $0.toneWeight * factor($0, factors)) }),
            saturation: mean(pairs.map { ($0.tone.saturation, $0.toneWeight * factor($0, factors)) })
        )
        let skin = SkinParameters(
            smoothing: mean(pairs.map { ($0.skin.smoothing, $0.strengthWeight * factor($0, factors)) }),
            evenness: mean(pairs.map { ($0.skin.evenness, $0.strengthWeight * factor($0, factors)) }),
            blemish: mean(pairs.map { ($0.skin.blemish, $0.strengthWeight * factor($0, factors)) })
        )
        let face = FaceParameters(
            slim: mean(pairs.map { ($0.face.slim, $0.strengthWeight * factor($0, factors)) }),
            jaw: mean(pairs.map { ($0.face.jaw, $0.strengthWeight * factor($0, factors)) })
        )
        let body = BodyParameters(
            arm: mean(pairs.map { ($0.body.arm, $0.strengthWeight * factor($0, factors)) }),
            waist: mean(pairs.map { ($0.body.waist, $0.strengthWeight * factor($0, factors)) }),
            leg: mean(pairs.map { ($0.body.leg, $0.strengthWeight * factor($0, factors)) }),
            legLength: 1 + mean(pairs.map { ($0.body.legLength - 1, $0.strengthWeight * factor($0, factors)) })
        )
        let finish = FinishParameters(
            grain: mean(pairs.map { ($0.finish.grain, $0.strengthWeight * factor($0, factors)) }),
            vignette: mean(pairs.map { ($0.finish.vignette, $0.strengthWeight * factor($0, factors)) })
        )

        return AggregatedStyle(
            tone: safety.clamped(tone: tone),
            skin: safety.clamped(skin: skin),
            face: safety.clamped(face: face),
            body: safety.clamped(body: body),
            finish: safety.clamped(finish: finish),
            outlierCount: 0
        )
    }

    private static func factor(_ pair: PairFit, _ factors: [UUID: Double]) -> Double {
        max(factors[pair.id] ?? 1, 0.01)
    }

    private static func mean(_ samples: [(Double, Double)]) -> Double {
        LearningMath.weightedMean(
            samples.map { (value: $0.0, weight: $0.1) }
        )
    }
}

/// Leave-one-out validation in parameter space.
///
/// For each accepted pair the remaining pairs are aggregated and compared with
/// the held-out pair's own estimate. The error therefore measures how
/// consistent the user's edits are, not how well the current profile matches
/// pixels. Single outliers are down-weighted by the same robust factor used in
/// aggregation, so one bad export lowers confidence only when the inconsistency
/// is broad.
enum HoldoutValidator {
    struct Result: Sendable, Equatable {
        let error: Double
        let isAvailable: Bool
    }

    static func leaveOneOut(
        pairs: [PairFit],
        safety: StyleSafetyRanges
    ) -> Result {
        guard pairs.count >= 3 else {
            return Result(error: 1, isAvailable: false)
        }

        let full = PairAggregator.aggregate(pairs, safety: safety)
        var weightedError = 0.0
        var totalWeight = 0.0

        for index in pairs.indices {
            var others: [PairFit] = []
            others.reserveCapacity(pairs.count - 1)
            for candidate in pairs.indices where candidate != index {
                others.append(pairs[candidate])
            }
            let training = PairAggregator.aggregate(others, safety: safety)
            let distance = PairAggregator.normalizedDistance(
                pair: pairs[index],
                aggregate: training,
                safety: safety
            )
            let baseWeight = max(
                (pairs[index].toneWeight + pairs[index].strengthWeight) / 2,
                0.01
            )
            let distanceFromFull = PairAggregator.normalizedDistance(
                pair: pairs[index],
                aggregate: full,
                safety: safety
            )
            let robustFactor = 1 / (1 + pow(distanceFromFull / 0.6, 2))
            let weight = baseWeight * max(robustFactor, 0.05)
            weightedError += distance * weight
            totalWeight += weight
        }

        let error = totalWeight > 0 ? weightedError / totalWeight : 1
        return Result(error: LearningMath.unit(error), isAvailable: true)
    }
}
