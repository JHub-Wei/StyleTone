import Foundation
import GoldenSupport
import StyleToneCore

/// A deterministic edit applied to the synthetic portrait.
///
/// The values are intentionally simple photo-style operations: exposure and
/// white-balance gains, contrast around mid-grey, saturation around luma and an
/// optional box blur on the whole frame (used as a smoothing proxy).
struct SyntheticEdit: Sendable {
    var exposure: Double = 1
    var redGain: Double = 1
    var greenGain: Double = 1
    var blueGain: Double = 1
    var contrast: Double = 1
    var saturation: Double = 1
    var blurRadius: Int = 0
}

/// Builds synthetic portrait pairs for WP-11 tests.
///
/// The scene is a 160×160 gradient background with a soft skin-coloured oval,
/// deterministic pore noise and dark hair. It is not a real face and contains
/// no identity information; it only gives the tone and texture estimators
/// plausible skin/background distributions.
enum SyntheticPairFactory {
    static let width = 160
    static let height = 160

    static func quality(
        _ grade: PairQualityGrade,
        confidence: Float = 1
    ) -> PairQuality {
        PairQuality(
            grade: grade,
            reasons: [grade.rawValue],
            confidence: confidence
        )
    }

    static func pair(
        edit: SyntheticEdit,
        quality: PairQuality = quality(.good),
        id: UUID = UUID()
    ) throws -> PairSample {
        let original = try asset(edit: SyntheticEdit())
        let edited = try asset(edit: edit)
        return PairSample(
            id: id,
            original: original,
            edited: edited,
            quality: quality
        )
    }

    static func pairs(
        count: Int,
        edit: SyntheticEdit,
        quality: PairQuality = quality(.good)
    ) throws -> [PairSample] {
        try (0..<count).map { _ in
            try pair(edit: edit, quality: quality)
        }
    }

    /// A solid pair with independent sizes, for mismatch/degradation tests.
    static func solidPair(
        originalSize: PixelSize,
        editedSize: PixelSize,
        quality: PairQuality = quality(.good)
    ) throws -> PairSample {
        let color = RGB8(red: 205, green: 160, blue: 132)
        let original = try PixelBuffer(
            width: originalSize.width,
            height: originalSize.height,
            fill: color
        ).makeImageAsset()
        let edited = try PixelBuffer(
            width: editedSize.width,
            height: editedSize.height,
            fill: color
        ).makeImageAsset()
        return PairSample(
            id: UUID(),
            original: original,
            edited: edited,
            quality: quality
        )
    }

    // MARK: - Scene

    private struct EncodedScene {
        var red: [Double]
        var green: [Double]
        var blue: [Double]
        var skin: [Double]
    }

    private static func asset(edit: SyntheticEdit) throws -> ImageAsset {
        var scene = makeScene()
        apply(edit: edit, to: &scene)
        if edit.blurRadius > 0 {
            scene.red = blur(scene.red, radius: edit.blurRadius)
            scene.green = blur(scene.green, radius: edit.blurRadius)
            scene.blue = blur(scene.blue, radius: edit.blurRadius)
        }
        return try makeAsset(scene)
    }

    private static func makeScene() -> EncodedScene {
        let count = width * height
        var red = [Double](repeating: 0, count: count)
        var green = [Double](repeating: 0, count: count)
        var blue = [Double](repeating: 0, count: count)
        var skin = [Double](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let nx = (Double(x) + 0.5) / Double(width)
                let ny = (Double(y) + 0.5) / Double(height)
                let noise = pixelNoise(x, y) - 0.5

                let backgroundBase = 0.17 + 0.24 * nx
                let backgroundRed = backgroundBase + 0.018 * noise
                let backgroundGreen = backgroundBase + 0.015 * noise
                let backgroundBlue = backgroundBase + 0.050 + 0.012 * noise

                let dx = (nx - 0.50) / 0.225
                let dy = (ny - 0.53) / 0.290
                let distance = (dx * dx + dy * dy).squareRoot()
                let skinBlend = 1 - smoothstep(0.90, 1.02, distance)

                let shade = 1 - 0.18 * min(distance, 1)
                let skinRed = 0.82 * shade + 0.045 * noise
                let skinGreen = 0.62 * shade + 0.035 * noise
                let skinBlue = 0.50 * shade + 0.025 * noise

                var pixelRed = backgroundRed * (1 - skinBlend) + skinRed * skinBlend
                var pixelGreen = backgroundGreen * (1 - skinBlend) + skinGreen * skinBlend
                var pixelBlue = backgroundBlue * (1 - skinBlend) + skinBlue * skinBlend
                var pixelSkin = skinBlend

                let hairX = (nx - 0.50) / 0.245
                let hairY = (ny - 0.245) / 0.115
                let hairDistance = (hairX * hairX + hairY * hairY).squareRoot()
                if hairDistance < 1 {
                    let hairBlend = 1 - smoothstep(0.82, 1.0, hairDistance)
                    pixelRed = 0.10 * hairBlend + pixelRed * (1 - hairBlend)
                    pixelGreen = 0.085 * hairBlend + pixelGreen * (1 - hairBlend)
                    pixelBlue = 0.070 * hairBlend + pixelBlue * (1 - hairBlend)
                    pixelSkin *= 1 - hairBlend
                }

                red[index] = clamp01(pixelRed)
                green[index] = clamp01(pixelGreen)
                blue[index] = clamp01(pixelBlue)
                skin[index] = clamp01(pixelSkin)
            }
        }

        return EncodedScene(red: red, green: green, blue: blue, skin: skin)
    }

    private static func apply(edit: SyntheticEdit, to scene: inout EncodedScene) {
        let count = scene.red.count
        for index in 0..<count {
            var red = (scene.red[index] - 0.5) * edit.contrast + 0.5
            var green = (scene.green[index] - 0.5) * edit.contrast + 0.5
            var blue = (scene.blue[index] - 0.5) * edit.contrast + 0.5

            red *= edit.exposure * edit.redGain
            green *= edit.exposure * edit.greenGain
            blue *= edit.exposure * edit.blueGain

            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            red = luma + (red - luma) * edit.saturation
            green = luma + (green - luma) * edit.saturation
            blue = luma + (blue - luma) * edit.saturation

            scene.red[index] = clamp01(red)
            scene.green[index] = clamp01(green)
            scene.blue[index] = clamp01(blue)
        }
    }

    private static func makeAsset(_ scene: EncodedScene) throws -> ImageAsset {
        let count = width * height
        var bytes = [UInt8](repeating: 255, count: count * 4)
        for index in 0..<count {
            let offset = index * 4
            bytes[offset] = byte(scene.red[index])
            bytes[offset + 1] = byte(scene.green[index])
            bytes[offset + 2] = byte(scene.blue[index])
        }
        return try PixelBuffer(width: width, height: height, rgbaBytes: bytes)
            .makeImageAsset()
    }

    private static func blur(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0 else { return values }
        var output = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                var samples = 0
                for dy in -radius...radius {
                    let sampleY = min(max(y + dy, 0), height - 1)
                    for dx in -radius...radius {
                        let sampleX = min(max(x + dx, 0), width - 1)
                        sum += values[sampleY * width + sampleX]
                        samples += 1
                    }
                }
                output[y * width + x] = sum / Double(samples)
            }
        }
        return output
    }

    private static func pixelNoise(_ x: Int, _ y: Int) -> Double {
        let mixed = UInt64(truncatingIfNeeded: x &* 73856093 &+ y &* 19349663)
        let shifted = (mixed ^ (mixed >> 13)) &* 1274126177
        return Double((shifted ^ (shifted >> 16)) & 0xFFFF) / 65535
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max(Int((value * 255).rounded()), 0), 255))
    }
}
