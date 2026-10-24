import Foundation

/// Small numerical helpers shared by the learning stages.
///
/// The module intentionally depends only on Foundation/CoreGraphics so it can
/// be unit-tested with synthetic images without importing Imaging or Vision.
enum LearningMath {
    /// Clamps `value` into `range`. Non-finite input returns the lower bound for
    /// signed parameters; callers that prefer neutral pass a symmetric range.
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    /// Clamps into `0...1`; non-finite becomes 0.
    static func unit(_ value: Double) -> Double {
        clamp(value, 0, 1)
    }

    /// Signed unit clamp; non-finite becomes 0.
    static func signedUnit(_ value: Double) -> Double {
        clamp(value, -1, 1)
    }

    static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return quantile(sorted: values.sorted(), probability: 0.5)
    }

    /// Linear-interpolated quantile of a sorted array. `probability` is
    /// clamped to `0...1`.
    static func quantile(sorted values: [Double], probability: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        if values.count == 1 { return values[0] }
        let p = clamp(probability, 0, 1)
        let position = p * Double(values.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, values.count - 1)
        let fraction = position - Double(lower)
        return values[lower] * (1 - fraction) + values[upper] * fraction
    }

    static func quantile(of values: [Double], probability: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        return quantile(sorted: values.sorted(), probability: probability)
    }

    /// Weighted median with positive weights. Zero/invalid weights are ignored;
    /// when no usable weight remains the unweighted median is returned.
    static func weightedMedian(_ samples: [(value: Double, weight: Double)]) -> Double {
        let usable = samples
            .filter { $0.value.isFinite && $0.weight.isFinite && $0.weight > 0 }
            .sorted { $0.value < $1.value }
        guard !usable.isEmpty else {
            return median(samples.map { $0.value }.filter { $0.isFinite })
        }

        let total = usable.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return median(usable.map { $0.value }) }

        let halfway = total / 2
        var accumulated = 0.0
        for sample in usable {
            accumulated += sample.weight
            if accumulated >= halfway {
                return sample.value
            }
        }
        return usable[usable.count - 1].value
    }

    static func weightedMean(_ samples: [(value: Double, weight: Double)]) -> Double {
        var numerator = 0.0
        var denominator = 0.0
        for sample in samples where sample.value.isFinite && sample.weight.isFinite && sample.weight > 0 {
            numerator += sample.value * sample.weight
            denominator += sample.weight
        }
        return denominator > 0 ? numerator / denominator : 0
    }

    /// Weighted mean absolute deviation around `center`.
    static func weightedMAD(
        _ samples: [(value: Double, weight: Double)],
        around center: Double
    ) -> Double {
        weightedMean(
            samples.map { sample in
                (value: abs(sample.value - center), weight: sample.weight)
            }
        )
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(values.count)
        return variance.squareRoot()
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Shortest absolute distance between two hue angles in degrees.
    static func hueDistance(_ first: Double, _ second: Double) -> Double {
        guard first.isFinite, second.isFinite else { return 0 }
        var delta = (first - second).truncatingRemainder(dividingBy: 360)
        if delta < -180 { delta += 360 }
        if delta > 180 { delta -= 360 }
        return abs(delta)
    }

    static func safeLog2(_ value: Double) -> Double {
        log2(max(value, 1e-6))
    }

    static func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        let safeDenominator = max(abs(denominator), 1e-6)
        return numerator / safeDenominator
    }
}
