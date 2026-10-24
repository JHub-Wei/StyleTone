import Foundation
import GoldenSupport
import StyleToneCore
import TestShared

/// Deterministic synthetic skin used by the retouch quality tests.
///
/// The image contains three texture scales that matter to WP-07:
///
/// - a broad 20–40 px shading/blotch pattern,
/// - a 3–4 px pore pattern,
/// - optional smooth blemishes and a hard step edge.
///
/// It is intentionally generated in sRGB space like a camera JPEG, then the
/// production code converts it to linear light through `ColorPipeline`.
enum SyntheticSkin {
    struct Tone {
        let name: String
        let color: RGB8
    }

    static let tones: [Tone] = [
        Tone(name: "I", color: RGB8(red: 255, green: 224, blue: 208)),
        Tone(name: "II", color: RGB8(red: 241, green: 194, blue: 165)),
        Tone(name: "III", color: RGB8(red: 224, green: 172, blue: 130)),
        Tone(name: "IV", color: RGB8(red: 198, green: 134, blue: 89)),
        Tone(name: "V", color: RGB8(red: 141, green: 85, blue: 54)),
        Tone(name: "VI", color: RGB8(red: 75, green: 46, blue: 33))
    ]

    static func image(
        size: PixelSize,
        tone: RGB8,
        blemishes: [BlemishPoint] = [],
        stepEdge: Bool = false,
        seed: UInt64 = 1
    ) throws -> PixelBuffer {
        guard size.width > 0, size.height > 0 else {
            throw GoldenSupportError.invalidDimensions(
                width: size.width,
                height: size.height
            )
        }
        let width = size.width
        let height = size.height
        var buffer = try PixelBuffer(width: width, height: height, fill: tone)
        let shortEdge = Double(min(width, height))

        for y in 0 ..< height {
            let yy = Double(y) + 0.5
            for x in 0 ..< width {
                let xx = Double(x) + 0.5
                let low = 0.028 * sin(2 * Double.pi * xx / 37 + 0.7) *
                    sin(2 * Double.pi * yy / 41 + 1.3) +
                    0.018 * sin(2 * Double.pi * xx / 19 - 0.2) *
                    cos(2 * Double.pi * yy / 23 + 0.9)
                let noise = hashNoise(x: x, y: y, seed: seed)
                let pore = 0.65 * noise +
                    0.35 * sin(2 * Double.pi * xx / 3.2) *
                    sin(2 * Double.pi * yy / 3.7)
                let texture = 2.4 * pore

                var red = Double(tone.red) / 255 + low + texture * 1.1 / 255
                var green = Double(tone.green) / 255 + low * 0.9 + texture / 255
                var blue = Double(tone.blue) / 255 + low * 0.8 + texture * 0.85 / 255

                if stepEdge {
                    let offset = x >= width / 2 ? 0.10 : 0
                    red += offset
                    green += offset
                    blue += offset
                }

                for blemish in blemishes {
                    let centerX = blemish.point.x * Double(width)
                    let centerY = blemish.point.y * Double(height)
                    let radius = blemish.radius * shortEdge
                    let dx = xx - centerX
                    let dy = yy - centerY
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < radius {
                        let falloff = 1 - (distance / radius) * (distance / radius)
                        red -= 38.0 / 255 * falloff
                        green -= 30.0 / 255 * falloff
                        blue -= 26.0 / 255 * falloff
                    }
                }

                buffer[x, y] = RGBA8(
                    red: byte(red),
                    green: byte(green),
                    blue: byte(blue)
                )
            }
        }
        return buffer
    }

    static func analysis(
        size: PixelSize,
        mask: MaskBuffer?,
        faces: [FaceObservation] = []
    ) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: size,
            faces: faces,
            body: nil,
            personMask: nil,
            skinMask: mask,
            backgroundEdgeMask: nil,
            warnings: []
        )
    }

    static func fullMask(size: PixelSize) throws -> MaskBuffer {
        try MockMaskFactory.solid(value: 255, size: size)
    }

    static func emptyMask(size: PixelSize) throws -> MaskBuffer {
        try MockMaskFactory.solid(value: 0, size: size)
    }

    // MARK: - Metrics

    static func meanSaturation(_ buffer: PixelBuffer) -> Double {
        var total = 0.0
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                let pixel = buffer[x, y]
                let maximum = Double(max(max(pixel.red, pixel.green), pixel.blue))
                let minimum = Double(min(min(pixel.red, pixel.green), pixel.blue))
                if maximum > 0 {
                    total += (maximum - minimum) / maximum
                }
            }
        }
        return total / Double(buffer.pixelCount)
    }

    /// Mean CIELAB hue angle in degrees; the magnitude is ignored.
    static func meanHueDegrees(_ buffer: PixelBuffer) -> Double {
        var a = 0.0
        var b = 0.0
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                let lab = ColorScience.lab(buffer[x, y].color)
                a += lab.a
                b += lab.b
            }
        }
        return atan2(b, a) * 180 / Double.pi
    }

    /// RMS difference from the 4-neighbour luma average, in 0...255 units.
    static func highFrequencyStd(_ buffer: PixelBuffer) -> Double {
        guard buffer.width > 2, buffer.height > 2 else { return 0 }
        var luma = [Double](repeating: 0, count: buffer.pixelCount)
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                luma[y * buffer.width + x] = buffer[x, y].color.luma
            }
        }
        var total = 0.0
        var count = 0
        for y in 1 ..< (buffer.height - 1) {
            for x in 1 ..< (buffer.width - 1) {
                let index = y * buffer.width + x
                let average = (
                    luma[index - 1] + luma[index + 1] +
                        luma[index - buffer.width] + luma[index + buffer.width]
                ) / 4
                let difference = luma[index] - average
                total += difference * difference
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return (total / Double(count)).squareRoot()
    }

    /// Standard deviation of 8×8 block mean luma, in 0...255 units.
    static func lowFrequencyStd(_ buffer: PixelBuffer) -> Double {
        var blockMeans: [Double] = []
        var blockY = 0
        while blockY < buffer.height {
            let endY = min(blockY + 8, buffer.height)
            var blockX = 0
            while blockX < buffer.width {
                let endX = min(blockX + 8, buffer.width)
                var total = 0.0
                for y in blockY ..< endY {
                    for x in blockX ..< endX {
                        total += buffer[x, y].color.luma
                    }
                }
                blockMeans.append(total / Double((endX - blockX) * (endY - blockY)))
                blockX = endX
            }
            blockY = endY
        }
        guard !blockMeans.isEmpty else { return 0 }
        let mean = blockMeans.reduce(0, +) / Double(blockMeans.count)
        let variance = blockMeans.reduce(0) { partial, value in
            partial + (value - mean) * (value - mean)
        } / Double(blockMeans.count)
        return variance.squareRoot()
    }

    /// Luma difference between the left and right side of a vertical step.
    static func edgeContrast(_ buffer: PixelBuffer) -> Double {
        let inset = max(2, buffer.width / 20)
        let split = buffer.width / 2
        var left = 0.0
        var leftCount = 0
        for y in 0 ..< buffer.height {
            for x in 0 ..< max(0, split - inset) {
                left += buffer[x, y].color.luma
                leftCount += 1
            }
        }
        var right = 0.0
        var rightCount = 0
        for y in 0 ..< buffer.height {
            for x in min(buffer.width - 1, split + inset) ..< buffer.width {
                right += buffer[x, y].color.luma
                rightCount += 1
            }
        }
        guard leftCount > 0, rightCount > 0 else { return 0 }
        return right / Double(rightCount) - left / Double(leftCount)
    }

    static func meanLuma(
        _ buffer: PixelBuffer,
        center: NormalizedPoint,
        radius: Double
    ) -> Double {
        let centerX = center.x * Double(buffer.width)
        let centerY = center.y * Double(buffer.height)
        let radiusPixels = radius * Double(min(buffer.width, buffer.height))
        var total = 0.0
        var count = 0
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                let dx = Double(x) + 0.5 - centerX
                let dy = Double(y) + 0.5 - centerY
                if dx * dx + dy * dy < radiusPixels * radiusPixels {
                    total += buffer[x, y].color.luma
                    count += 1
                }
            }
        }
        guard count > 0 else { return 0 }
        return total / Double(count)
    }

    static func ringLuma(
        _ buffer: PixelBuffer,
        center: NormalizedPoint,
        innerRadius: Double,
        outerRadius: Double
    ) -> Double {
        let centerX = center.x * Double(buffer.width)
        let centerY = center.y * Double(buffer.height)
        let shortEdge = Double(min(buffer.width, buffer.height))
        let inner = innerRadius * shortEdge
        let outer = outerRadius * shortEdge
        var total = 0.0
        var count = 0
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                let dx = Double(x) + 0.5 - centerX
                let dy = Double(y) + 0.5 - centerY
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance >= inner, distance <= outer {
                    total += buffer[x, y].color.luma
                    count += 1
                }
            }
        }
        guard count > 0 else { return 0 }
        return total / Double(count)
    }

    /// Maximum per-channel difference outside a disk, in 0...255.
    static func maximumDifferenceOutside(
        _ first: PixelBuffer,
        _ second: PixelBuffer,
        center: NormalizedPoint,
        radius: Double
    ) -> Int {
        guard first.width == second.width, first.height == second.height else {
            return 255
        }
        let centerX = center.x * Double(first.width)
        let centerY = center.y * Double(first.height)
        let radiusPixels = radius * Double(min(first.width, first.height))
        var maximum = 0
        for y in 0 ..< first.height {
            for x in 0 ..< first.width {
                let dx = Double(x) + 0.5 - centerX
                let dy = Double(y) + 0.5 - centerY
                if dx * dx + dy * dy <= radiusPixels * radiusPixels {
                    continue
                }
                let lhs = first[x, y]
                let rhs = second[x, y]
                maximum = max(
                    maximum,
                    max(
                        abs(Int(lhs.red) - Int(rhs.red)),
                        max(
                            abs(Int(lhs.green) - Int(rhs.green)),
                            abs(Int(lhs.blue) - Int(rhs.blue))
                        )
                    )
                )
            }
        }
        return maximum
    }

    // MARK: - Generation helpers

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max((value * 255).rounded(), 0), 255))
    }

    private static func hashNoise(x: Int, y: Int, seed: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        value ^= seed &* 0x1656_67B1_9E37_79F9
        value ^= value >> 30
        value = value &* 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value = value &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0xFFFF) / 65535.0 * 2 - 1
    }
}
