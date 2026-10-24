import Foundation

/// Internal color math shared by ``ColorPipeline``.
///
/// Matrices follow IEC 61966-2-1 (sRGB), SMPTE EG 432-1 (Display P3) and
/// Björn Ottosson's OKLab, all with a D65 white point. The transfer function
/// of Display P3 is the sRGB curve, so the same lookup table applies to both
/// input spaces.
enum ColorScience {
    // MARK: - Matrices

    struct Matrix3: Sendable {
        let row0: SIMD3<Float>
        let row1: SIMD3<Float>
        let row2: SIMD3<Float>

        func apply(_ value: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(
                row0.x * value.x + row0.y * value.y + row0.z * value.z,
                row1.x * value.x + row1.y * value.y + row1.z * value.z,
                row2.x * value.x + row2.y * value.y + row2.z * value.z
            )
        }
    }

    struct Matrix3D: Sendable {
        let row0: SIMD3<Double>
        let row1: SIMD3<Double>
        let row2: SIMD3<Double>

        func apply(_ value: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3<Double>(
                row0.x * value.x + row0.y * value.y + row0.z * value.z,
                row1.x * value.x + row1.y * value.y + row1.z * value.z,
                row2.x * value.x + row2.y * value.y + row2.z * value.z
            )
        }
    }

    /// Linear Display P3 -> linear extended sRGB.
    static let displayP3ToLinearSRGB = Matrix3(
        row0: SIMD3<Float>(1.22474504, -0.22490431, 0.00000007),
        row1: SIMD3<Float>(-0.04205781, 1.04208096, -0.00000006),
        row2: SIMD3<Float>(-0.01964229, -0.07865489, 1.09853723)
    )

    /// Linear sRGB -> linear Display P3.
    static let linearSRGBToDisplayP3 = Matrix3(
        row0: SIMD3<Float>(0.82259286, 0.17753395, -0.00000001),
        row1: SIMD3<Float>(0.03319952, 0.96678355, 0.00000003),
        row2: SIMD3<Float>(0.01708535, 0.07239572, 0.91030145)
    )

    private static let sRGBToXYZ = Matrix3D(
        row0: SIMD3<Double>(0.4124564, 0.3575761, 0.1804375),
        row1: SIMD3<Double>(0.2126729, 0.7151522, 0.0721750),
        row2: SIMD3<Double>(0.0193339, 0.1191920, 0.9503041)
    )

    private static let xyzToSRGB = Matrix3D(
        row0: SIMD3<Double>(3.2404542, -1.5371385, -0.4985314),
        row1: SIMD3<Double>(-0.9692660, 1.8760108, 0.0415560),
        row2: SIMD3<Double>(0.0556434, -0.2040259, 1.0572252)
    )

    private static let displayP3ToXYZ = Matrix3D(
        row0: SIMD3<Double>(0.4865709, 0.2656677, 0.1982173),
        row1: SIMD3<Double>(0.2289746, 0.6917385, 0.0792869),
        row2: SIMD3<Double>(0.0000000, 0.0451134, 1.0439444)
    )

    private static let xyzToDisplayP3 = Matrix3D(
        row0: SIMD3<Double>(2.4934973215, -0.9313838122, -0.4027108833),
        row1: SIMD3<Double>(-0.8294892631, 1.7626642312, 0.0236247634),
        row2: SIMD3<Double>(0.0358458563, -0.0761724250, 0.9568844917)
    )

    private static let oklabM1 = Matrix3D(
        row0: SIMD3<Double>(0.8189330101, 0.3618667424, -0.1288597137),
        row1: SIMD3<Double>(0.0329845436, 0.9293118715, 0.0361456387),
        row2: SIMD3<Double>(0.0482003018, 0.2643662691, 0.6338517070)
    )

    private static let oklabM1Inverse = Matrix3D(
        row0: SIMD3<Double>(1.2270138511, -0.5577999807, 0.2812561490),
        row1: SIMD3<Double>(-0.0405801784, 1.1122568696, -0.0716766787),
        row2: SIMD3<Double>(-0.0763812845, -0.4214819784, 1.5861632204)
    )

    private static let oklabM2 = Matrix3D(
        row0: SIMD3<Double>(0.2104542553, 0.7936177850, -0.0040720468),
        row1: SIMD3<Double>(1.9779984951, -2.4285922050, 0.4505937099),
        row2: SIMD3<Double>(0.0259040371, 0.7827717662, -0.8086757660)
    )

    private static let oklabM2Inverse = Matrix3D(
        row0: SIMD3<Double>(0.9999999985, 0.3963377922, 0.2158037581),
        row1: SIMD3<Double>(1.0000000089, -0.1055613423, -0.0638541748),
        row2: SIMD3<Double>(1.0000000547, -0.0894841821, -1.2914855379)
    )

    // MARK: - Transfer functions

    /// sRGB electro-optical transfer function (encoded -> linear light).
    ///
    /// Negative inputs are mirrored so that extended-range values round-trip.
    static func eotf(_ value: Float) -> Float {
        if value < 0 {
            return -eotf(-value)
        }
        if value <= 0.04045 {
            return value / 12.92
        }
        return Float(pow(Double((value + 0.055) / 1.055), 2.4))
    }

    /// sRGB opto-electronic transfer function (linear light -> encoded).
    static func oetf(_ value: Float) -> Float {
        if value < 0 {
            return -oetf(-value)
        }
        if value <= 0.0031308 {
            return value * 12.92
        }
        return Float(1.055 * pow(Double(value), 1.0 / 2.4) - 0.055)
    }

    /// Exact 8-bit decode table, shared by sRGB and Display P3 sources.
    static let eotfLUT: [Float] = (0 ... 255).map { index in
        eotf(Float(index) / 255.0)
    }

    /// 8-bit encode table over the 0...1 range (4097 samples).
    static let oetfByteLUT: [UInt8] = (0 ... 4096).map { index in
        let encoded = oetf(Float(index) / 4096.0) * 255.0
        return UInt8(min(max(Int(encoded.rounded()), 0), 255))
    }

    /// Encodes a linear value in the 0...1 range to an 8-bit sRGB code.
    static func encodeByte(_ linear: Float) -> UInt8 {
        guard linear.isFinite else {
            return 0
        }
        let clamped = min(max(linear, 0), 1)
        let index = Int((clamped * 4096).rounded())
        return oetfByteLUT[min(max(index, 0), 4096)]
    }

    /// Encodes linear light, then premultiplies by `alpha` for 8-bit storage.
    static func premultipliedByte(_ linear: Float, alpha: Float) -> UInt8 {
        let encoded = Float(encodeByte(linear)) * min(max(alpha, 0), 1)
        return UInt8(min(max(Int(encoded.rounded()), 0), 255))
    }

    /// 8-bit alpha code.
    static func alphaByte(_ alpha: Float) -> UInt8 {
        UInt8(min(max(Int((min(max(alpha, 0), 1) * 255).rounded()), 0), 255))
    }

    // MARK: - Wide gamut

    static func linearSRGB(fromLinearDisplayP3 value: SIMD3<Float>) -> SIMD3<Float> {
        displayP3ToLinearSRGB.apply(value)
    }

    static func linearDisplayP3(fromLinearSRGB value: SIMD3<Float>) -> SIMD3<Float> {
        linearSRGBToDisplayP3.apply(value)
    }

    // MARK: - Gamut mapping

    /// Maps a linear-light color into the target gamut while holding OKLab
    /// lightness and hue and reducing chroma just enough to fit.
    ///
    /// Values already inside the gamut are only clamped, which keeps normal
    /// sRGB images untouched.
    static func gamutMap(_ value: SIMD3<Float>, in space: ImageColorSpace) -> SIMD3<Float> {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            return SIMD3<Float>(0, 0, 0)
        }
        let linear = SIMD3<Double>(Double(value.x), Double(value.y), Double(value.z))
        if isInGamut(linear) {
            return SIMD3<Float>(
                clamp01(linear.x),
                clamp01(linear.y),
                clamp01(linear.z)
            )
        }

        let xyz = toXYZMatrix(for: space).apply(linear)
        let lab = oklab(fromXYZ: xyz)
        let lightness = min(max(lab.x, 0), 1)
        let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
        guard chroma > 1e-9 else {
            let gray = Float(lightness)
            return SIMD3<Float>(gray, gray, gray)
        }
        let hue = atan2(lab.z, lab.y)

        var lower = 0.0
        var upper = chroma
        for _ in 0 ..< 24 {
            let mid = (lower + upper) * 0.5
            let candidateLab = SIMD3<Double>(lightness, mid * cos(hue), mid * sin(hue))
            let candidate = fromXYZMatrix(for: space).apply(xyz(fromOKLab: candidateLab))
            if isInGamut(candidate) {
                lower = mid
            } else {
                upper = mid
            }
        }

        let mappedLab = SIMD3<Double>(lightness, lower * cos(hue), lower * sin(hue))
        let mapped = fromXYZMatrix(for: space).apply(xyz(fromOKLab: mappedLab))
        return SIMD3<Float>(
            clamp01(mapped.x),
            clamp01(mapped.y),
            clamp01(mapped.z)
        )
    }

    private static func isInGamut(_ value: SIMD3<Double>) -> Bool {
        let tolerance = 1e-6
        return value.x >= -tolerance && value.x <= 1 + tolerance
            && value.y >= -tolerance && value.y <= 1 + tolerance
            && value.z >= -tolerance && value.z <= 1 + tolerance
    }

    private static func clamp01(_ value: Double) -> Float {
        Float(min(max(value, 0), 1))
    }

    private static func toXYZMatrix(for space: ImageColorSpace) -> Matrix3D {
        space == .sRGB ? sRGBToXYZ : displayP3ToXYZ
    }

    private static func fromXYZMatrix(for space: ImageColorSpace) -> Matrix3D {
        space == .sRGB ? xyzToSRGB : xyzToDisplayP3
    }

    private static func oklab(fromXYZ xyz: SIMD3<Double>) -> SIMD3<Double> {
        let lms = oklabM1.apply(xyz)
        let lRoot = cbrt(lms.x)
        let mRoot = cbrt(lms.y)
        let sRoot = cbrt(lms.z)
        return oklabM2.apply(SIMD3<Double>(lRoot, mRoot, sRoot))
    }

    private static func xyz(fromOKLab lab: SIMD3<Double>) -> SIMD3<Double> {
        let roots = oklabM2Inverse.apply(lab)
        let lms = SIMD3<Double>(
            roots.x * roots.x * roots.x,
            roots.y * roots.y * roots.y,
            roots.z * roots.z * roots.z
        )
        return oklabM1Inverse.apply(lms)
    }
}
