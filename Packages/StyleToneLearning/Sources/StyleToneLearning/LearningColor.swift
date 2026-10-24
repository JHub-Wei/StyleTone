import Foundation

/// Linear-light sRGB triplet used by the image statistics.
struct LinearRGB: Sendable, Equatable {
    var red: Float
    var green: Float
    var blue: Float

    init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ value: SIMD3<Float>) {
        self.init(red: value.x, green: value.y, blue: value.z)
    }

    var luminance: Float {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    var simd: SIMD3<Float> {
        SIMD3(red, green, blue)
    }
}

/// D65 CIE L*a*b* value with derived chroma and hue.
struct LabValue: Sendable, Equatable {
    var l: Double
    var a: Double
    var b: Double

    var chroma: Double {
        (a * a + b * b).squareRoot()
    }

    /// Hue angle in degrees, `0..<360`. Undefined hues (neutral) return 0.
    var hueDegrees: Double {
        guard chroma > 1e-6 else { return 0 }
        var angle = atan2(b, a) * 180 / .pi
        if angle < 0 { angle += 360 }
        return angle
    }
}

/// Colour conversions used by the tone fitter.
///
/// Imaging owns the render colour pipeline; this file only needs a stable
/// perceptual representation of sampled sRGB pixels. Keeping the math local
/// avoids a `StyleToneLearning -> StyleToneImaging` dependency, which the
/// module graph forbids.
enum LearningColor {
    static let d65: (x: Double, y: Double, z: Double) = (0.95047, 1.0, 1.08883)

    static func srgbToLinear(_ encoded: Double) -> Double {
        let value = min(max(encoded, 0), 1)
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    static func linearToSRGB(_ linear: Double) -> Double {
        let value = min(max(linear, 0), 1)
        if value <= 0.0031308 {
            return value * 12.92
        }
        return 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    static func lab(linear color: LinearRGB) -> LabValue {
        let red = Double(color.red)
        let green = Double(color.green)
        let blue = Double(color.blue)

        let x = 0.4124564 * red + 0.3575761 * green + 0.1804375 * blue
        let y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
        let z = 0.0193339 * red + 0.1191920 * green + 0.9503041 * blue

        let fx = labForward(x / d65.x)
        let fy = labForward(y / d65.y)
        let fz = labForward(z / d65.z)

        return LabValue(
            l: 116 * fy - 16,
            a: 500 * (fx - fy),
            b: 200 * (fy - fz)
        )
    }

    static func lab(encodedRed red: Double, green: Double, blue: Double) -> LabValue {
        lab(
            linear: LinearRGB(
                red: Float(srgbToLinear(red)),
                green: Float(srgbToLinear(green)),
                blue: Float(srgbToLinear(blue))
            )
        )
    }

    /// Weighted circular mean of hue angles in degrees. Returns `0` when all
    /// weights are zero.
    static func circularMeanHue(_ hues: [Double], weights: [Double]) -> Double {
        var sinSum = 0.0
        var cosSum = 0.0
        var weightSum = 0.0
        for (hue, weight) in zip(hues, weights) where hue.isFinite && weight.isFinite && weight > 0 {
            let radians = hue * .pi / 180
            sinSum += sin(radians) * weight
            cosSum += cos(radians) * weight
            weightSum += weight
        }
        guard weightSum > 0, abs(sinSum) + abs(cosSum) > 1e-9 else { return 0 }
        var angle = atan2(sinSum, cosSum) * 180 / .pi
        if angle < 0 { angle += 360 }
        return angle
    }

    private static func labForward(_ value: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        if value > epsilon {
            return cbrt(value)
        }
        return (kappa * value + 16) / 116
    }
}
