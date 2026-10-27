import CoreGraphics
import Foundation
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import TestShared

/// Deterministic images and analyses used by the performance suite.
///
/// All fixtures are synthetic. No real photo, file name or user data enters the
/// repository or the test logs.
enum PerformanceFixtures {
    /// A 12 MP-class RGB gradient with vertical stripes.
    ///
    /// The pattern is intentionally cheap for the codec but produces enough
    /// high-frequency detail that a resample or warp cannot be optimized away.
    static func gradientImage(size: PixelSize) throws -> ImageAsset {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw PerformanceFixtureError.imageCreationFailed
        }
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw PerformanceFixtureError.imageCreationFailed
        }

        let start = try makeColor(
            colorSpace: colorSpace,
            red: 0.10,
            green: 0.12,
            blue: 0.22
        )
        let end = try makeColor(
            colorSpace: colorSpace,
            red: 0.92,
            green: 0.72,
            blue: 0.48
        )
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [start, end] as CFArray,
            locations: [0, 1]
        ) else {
            throw PerformanceFixtureError.imageCreationFailed
        }
        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        let stripe = try makeColor(
            colorSpace: colorSpace,
            red: 0.75,
            green: 0.35,
            blue: 0.22
        )
        context.setFillColor(stripe)
        for x in stride(from: 0, to: size.width, by: 24) {
            context.fill(CGRect(x: x, y: 0, width: 6, height: size.height))
        }

        guard let image = context.makeImage() else {
            throw PerformanceFixtureError.imageCreationFailed
        }
        return ImageAsset(cgImage: image, colorSpace: colorSpace)
    }

    /// Encodes a 12 MP image to JPEG bytes for the first-frame decode test.
    static func jpegData(size: PixelSize, quality: Double = 0.9) throws -> Data {
        let image = try gradientImage(size: size)
        return try ImageWriter().data(
            for: image,
            options: ImageWriteOptions(format: .jpeg, quality: quality)
        )
    }

    /// A synthetic portrait scene for the learning budget.
    ///
    /// The pixel statistics are similar to the WP-11 synthetic pair (skin oval,
    /// hair, background gradient, deterministic pore noise) but this fixture
    /// lives in the performance target so it cannot drift with module tests.
    static func portraitScene(
        size: PixelSize = PixelSize(width: 160, height: 160),
        exposure: Double = 1.0
    ) throws -> ImageAsset {
        var bytes = [UInt8](repeating: 255, count: size.width * size.height * 4)
        for y in 0 ..< size.height {
            for x in 0 ..< size.width {
                let nx = (Double(x) + 0.5) / Double(size.width)
                let ny = (Double(y) + 0.5) / Double(size.height)
                let noise = pixelNoise(x, y) - 0.5

                let background = 0.17 + 0.24 * nx
                var red = background + 0.018 * noise
                var green = background + 0.015 * noise
                var blue = background + 0.050 + 0.012 * noise

                let dx = (nx - 0.50) / 0.225
                let dy = (ny - 0.53) / 0.290
                let distance = (dx * dx + dy * dy).squareRoot()
                let skinBlend = 1 - smoothstep(0.90, 1.02, distance)
                let shade = 1 - 0.18 * min(distance, 1)
                let skinRed = 0.82 * shade + 0.045 * noise
                let skinGreen = 0.62 * shade + 0.035 * noise
                let skinBlue = 0.50 * shade + 0.025 * noise

                red = mix(background: red, skin: skinRed, blend: skinBlend)
                green = mix(background: green, skin: skinGreen, blend: skinBlend)
                blue = mix(background: blue, skin: skinBlue, blend: skinBlend)

                let hairX = (nx - 0.50) / 0.245
                let hairY = (ny - 0.245) / 0.115
                let hairDistance = (hairX * hairX + hairY * hairY).squareRoot()
                if hairDistance < 1 {
                    let hairBlend = 1 - smoothstep(0.82, 1.0, hairDistance)
                    red = mix(background: red, skin: 0.10, blend: hairBlend)
                    green = mix(background: green, skin: 0.085, blend: hairBlend)
                    blue = mix(background: blue, skin: 0.070, blend: hairBlend)
                }

                let index = (y * size.width + x) * 4
                bytes[index] = byte(clamp01(red * exposure))
                bytes[index + 1] = byte(clamp01(green * exposure))
                bytes[index + 2] = byte(clamp01(blue * exposure))
                bytes[index + 3] = 255
            }
        }
        return try PixelBuffer(
            width: size.width,
            height: size.height,
            rgbaBytes: bytes
        ).makeImageAsset()
    }

    /// A good-quality original/edited pair for the learning scenario.
    static func portraitPair(
        size: PixelSize = PixelSize(width: 160, height: 160),
        editedExposure: Double = 1.10
    ) throws -> PairSample {
        PairSample(
            original: try portraitScene(size: size, exposure: 1.0),
            edited: try portraitScene(size: size, exposure: editedExposure),
            quality: PairQuality(grade: .good, reasons: [], confidence: 1)
        )
    }

    /// Analysis matching `size`; masks are optional because 12 MP masks are
    /// deliberately outside the preview memory scenario.
    static func analysis(
        size: PixelSize,
        includesMasks: Bool = false
    ) throws -> PortraitAnalysis {
        try MockPortraitAnalysisFactory.portrait(
            size: size,
            faceCount: 1,
            includesBody: true,
            includesMasks: includesMasks
        )
    }

    /// Style with non-zero offsets so the render plan is never a no-op.
    static func style() -> StyleProfile {
        MockStyleProfileFactory.standard()
    }

    // MARK: - Helpers

    private static func makeColor(
        colorSpace: CGColorSpace,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CGColor {
        guard let color = CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, 1]
        ) else {
            throw PerformanceFixtureError.imageCreationFailed
        }
        return color
    }

    private static func pixelNoise(_ x: Int, _ y: Int) -> Double {
        let mixed = UInt64(truncatingIfNeeded: x &* 73_856_093 &+ y &* 19_349_663)
        let shifted = (mixed ^ (mixed >> 13)) &* 1_274_126_177
        return Double((shifted ^ (shifted >> 16)) & 0xFFFF) / 65_535
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(background: Double, skin: Double, blend: Double) -> Double {
        background * (1 - blend) + skin * blend
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max(Int((value * 255).rounded()), 0), 255))
    }
}

enum PerformanceFixtureError: Error, Equatable {
    case imageCreationFailed
}
