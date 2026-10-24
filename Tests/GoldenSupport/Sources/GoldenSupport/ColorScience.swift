import Foundation

/// CIE XYZ tristimulus values (D65).
public struct XYZColor: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// CIE L*a*b* colour with a D65 white point.
public struct LabColor: Sendable, Equatable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }
}

/// Colour conversions and perceptual difference metrics used by the harness.
///
/// The implementation follows IEC 61966-2-1 (sRGB), CIE 15:2004 (XYZ/Lab) and
/// Sharma et al. (2005) for CIEDE2000. Reference values from the Sharma test
/// data are asserted in `ColorScienceTests`.
public enum ColorScience {
    /// D65 white point normalised to Y = 1.
    public static let d65WhitePoint = XYZColor(x: 0.95047, y: 1.0, z: 1.08883)

    /// sRGB transfer function: encoded 0...1 to linear light.
    public static func srgbToLinear(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        if clamped <= 0.04045 {
            return clamped / 12.92
        }
        return pow((clamped + 0.055) / 1.055, 2.4)
    }

    /// Inverse sRGB transfer function: linear light to encoded 0...1.
    public static func linearToSRGB(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        if clamped <= 0.0031308 {
            return clamped * 12.92
        }
        return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }

    /// Converts an 8-bit sRGB colour to D65 XYZ.
    public static func xyz(_ color: RGB8) -> XYZColor {
        xyz(
            red: srgbToLinear(Double(color.red) / 255.0),
            green: srgbToLinear(Double(color.green) / 255.0),
            blue: srgbToLinear(Double(color.blue) / 255.0)
        )
    }

    /// Converts linear sRGB components to D65 XYZ.
    public static func xyz(red: Double, green: Double, blue: Double) -> XYZColor {
        XYZColor(
            x: 0.4124564 * red + 0.3575761 * green + 0.1804375 * blue,
            y: 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue,
            z: 0.0193339 * red + 0.1191920 * green + 0.9503041 * blue
        )
    }

    /// Converts D65 XYZ to Lab.
    public static func lab(_ xyz: XYZColor) -> LabColor {
        let white = d65WhitePoint
        let fx = labForward(xyz.x / white.x)
        let fy = labForward(xyz.y / white.y)
        let fz = labForward(xyz.z / white.z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Converts an 8-bit sRGB colour to Lab.
    public static func lab(_ color: RGB8) -> LabColor {
        lab(xyz(color))
    }

    /// Converts Lab back to D65 XYZ.
    public static func xyz(_ lab: LabColor) -> XYZColor {
        let white = d65WhitePoint
        let fy = (lab.l + 16) / 116
        let fx = fy + lab.a / 500
        let fz = fy - lab.b / 200
        return XYZColor(
            x: white.x * labInverse(fx),
            y: white.y * labInverse(fy),
            z: white.z * labInverse(fz)
        )
    }

    /// CIEDE2000 colour difference between two Lab colours.
    ///
    /// Implements the full Sharma et al. formulation, including the hue
    /// discontinuity handling and the rotation term.
    public static func deltaE00(_ first: LabColor, _ second: LabColor) -> Double {
        let l1 = first.l
        let a1 = first.a
        let b1 = first.b
        let l2 = second.l
        let a2 = second.a
        let b2 = second.b

        let c1 = (a1 * a1 + b1 * b1).squareRoot()
        let c2 = (a2 * a2 + b2 * b2).squareRoot()
        let cBar = (c1 + c2) / 2
        let cBarPower = power(cBar, 7)
        let g = 0.5 * (1 - (cBarPower / (cBarPower + power(25, 7))).squareRoot())

        let a1Prime = (1 + g) * a1
        let a2Prime = (1 + g) * a2
        let c1Prime = (a1Prime * a1Prime + b1 * b1).squareRoot()
        let c2Prime = (a2Prime * a2Prime + b2 * b2).squareRoot()
        let h1Prime = hueAngle(a: a1Prime, b: b1)
        let h2Prime = hueAngle(a: a2Prime, b: b2)

        let deltaLPrime = l2 - l1
        let deltaCPrime = c2Prime - c1Prime

        let deltaHPrime: Double
        if c1Prime * c2Prime == 0 {
            deltaHPrime = 0
        } else {
            var delta = h2Prime - h1Prime
            if delta > 180 {
                delta -= 360
            } else if delta < -180 {
                delta += 360
            }
            deltaHPrime = 2 * (c1Prime * c2Prime).squareRoot() * sin(radians(delta / 2))
        }

        let lBarPrime = (l1 + l2) / 2
        let cBarPrime = (c1Prime + c2Prime) / 2

        let hBarPrime: Double
        if c1Prime * c2Prime == 0 {
            hBarPrime = h1Prime + h2Prime
        } else if abs(h1Prime - h2Prime) <= 180 {
            hBarPrime = (h1Prime + h2Prime) / 2
        } else if h1Prime + h2Prime < 360 {
            hBarPrime = (h1Prime + h2Prime + 360) / 2
        } else {
            hBarPrime = (h1Prime + h2Prime - 360) / 2
        }

        let t = 1
            - 0.17 * cos(radians(hBarPrime - 30))
            + 0.24 * cos(radians(2 * hBarPrime))
            + 0.32 * cos(radians(3 * hBarPrime + 6))
            - 0.20 * cos(radians(4 * hBarPrime - 63))

        let deltaTheta = 30 * exp(-power((hBarPrime - 275) / 25, 2))
        let cBarPrimePower = power(cBarPrime, 7)
        let rotation = 2 * (cBarPrimePower / (cBarPrimePower + power(25, 7))).squareRoot()

        let lOffset = lBarPrime - 50
        let sL = 1 + (0.015 * lOffset * lOffset) / (20 + lOffset * lOffset).squareRoot()
        let sC = 1 + 0.045 * cBarPrime
        let sH = 1 + 0.015 * cBarPrime * t
        let rT = -sin(radians(2 * deltaTheta)) * rotation

        let lTerm = deltaLPrime / sL
        let cTerm = deltaCPrime / sC
        let hTerm = deltaHPrime / sH
        return (lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rT * cTerm * hTerm).squareRoot()
    }

    /// CIEDE2000 difference between two 8-bit sRGB colours.
    public static func deltaE00(_ first: RGB8, _ second: RGB8) -> Double {
        deltaE00(lab(first), lab(second))
    }

    /// CIE76 difference (cheap baseline, mostly useful in diagnostics).
    public static func deltaE76(_ first: LabColor, _ second: LabColor) -> Double {
        let dl = first.l - second.l
        let da = first.a - second.a
        let db = first.b - second.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    // MARK: - Helpers

    private static func labForward(_ value: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        if value > epsilon {
            return cbrt(value)
        }
        return (kappa * value + 16) / 116
    }

    private static func labInverse(_ value: Double) -> Double {
        let cube = value * value * value
        let epsilon = 216.0 / 24389.0
        if cube > epsilon {
            return cube
        }
        return (116 * value - 16) / (24389.0 / 27.0)
    }

    private static func hueAngle(a: Double, b: Double) -> Double {
        if a == 0 && b == 0 {
            return 0
        }
        var angle = atan2(b, a) * 180 / Double.pi
        if angle < 0 {
            angle += 360
        }
        return angle
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180
    }

    private static func power(_ base: Double, _ exponent: Double) -> Double {
        pow(base, exponent)
    }
}
