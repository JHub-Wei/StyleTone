import Foundation
import StyleToneCore

/// Small numeric helpers shared by the WP-14 leg pass.
///
/// The helpers are internal to `StyleToneGeometry`: the leg pass exposes only
/// configuration, warnings and plans, never geometry internals.
enum LegsMath {
    /// Clamps a finite value into `lower...upper`; non-finite input falls back
    /// to `lower`.
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    /// Float overload used for displacement caps.
    static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    /// Cubic smoothstep; input is clamped to `0...1`.
    static func smoothstep(_ value: Double) -> Double {
        let t = clamp(value, 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Linear interpolation.
    static func lerp(_ start: Double, _ end: Double, _ t: Double) -> Double {
        start + (end - start) * t
    }

    /// Compact lateral bump used for contour slimming.
    ///
    /// `normalizedDistance` is `abs(x - centerX) / halfWidth`. The bump is zero
    /// on the centre line, peaks exactly at the estimated contour (`u == 1`)
    /// and fades to zero over `feather * halfWidth` outside it. The derivative
    /// is zero at the peak, so the contour does not get a visible ridge.
    static func lateralBell(_ normalizedDistance: Double, feather: Double) -> Double {
        let u = abs(normalizedDistance)
        guard u.isFinite else { return 0 }
        if u <= 1 {
            return u * exp(0.5 * (1 - u * u))
        }
        let width = max(feather, 1e-6)
        let t = (u - 1) / width
        guard t < 1 else { return 0 }
        return smoothstep(1 - t)
    }

    /// Distance from a point to a normalized rectangle; `0` inside.
    static func distance(from point: SIMD2<Double>, to rect: NormalizedRect) -> Double {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
