import Foundation
import StyleToneCore

/// Renders the deterministic synthetic fixtures described by
/// ``FixtureManifestEntry``.
///
/// Every pattern uses integer arithmetic (the face outline additionally uses
/// symmetric floating-point ellipse tests), so the same entry always produces
/// byte-identical pixels. The Python generator in
/// `Tests/GoldenSupport/Tools/generate_fixtures.py` mirrors these algorithms to
/// produce the committed reference PNGs.
public enum FixtureRenderer {
    /// Renders one entry, validating its kind-specific parameters first.
    public static func render(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        try validate(entry)
        switch entry.kind {
        case .solidColor:
            return try renderSolid(entry)
        case .linearGradient:
            return try renderGradient(entry)
        case .checkerboard:
            return try renderCheckerboard(entry)
        case .colorChart:
            return try renderColorChart(entry)
        case .noise:
            return try renderNoise(entry)
        case .verticalEdge:
            return try renderVerticalEdge(entry)
        case .grid:
            return try renderGrid(entry)
        case .faceSilhouette:
            return try renderFaceSilhouette(entry)
        }
    }

    /// Validates dimensions, colours and kind-specific parameters.
    public static func validate(_ entry: FixtureManifestEntry) throws {
        guard entry.width > 0, entry.height > 0 else {
            throw failure(entry, "dimensions must be positive")
        }
        guard !entry.colors.isEmpty, entry.rgbColors.count == entry.colors.count else {
            throw failure(entry, "colours must be #RRGGBB values")
        }
        let colors = entry.rgbColors

        switch entry.kind {
        case .solidColor:
            guard colors.count == 1 else { throw failure(entry, "solidColor needs 1 colour") }
        case .linearGradient:
            guard colors.count == 2 else { throw failure(entry, "linearGradient needs 2 colours") }
            guard entry.axis != nil else { throw failure(entry, "linearGradient needs an axis") }
        case .checkerboard:
            guard colors.count == 2 else { throw failure(entry, "checkerboard needs 2 colours") }
            guard let cellSize = entry.cellSize, cellSize >= 1 else {
                throw failure(entry, "checkerboard needs cellSize >= 1")
            }
        case .colorChart:
            guard let columns = entry.columns, columns >= 1, columns <= colors.count else {
                throw failure(entry, "colorChart needs 1 <= columns <= colours.count")
            }
            let geometry = try colorChartGeometry(entry, columns: columns, colorCount: colors.count)
            guard geometry.patchWidth > 0, geometry.patchHeight > 0 else {
                throw failure(entry, "colorChart patches do not fit")
            }
        case .noise:
            guard colors.count == 1 else { throw failure(entry, "noise needs 1 base colour") }
            guard let amplitude = entry.amplitude, (1...127).contains(amplitude) else {
                throw failure(entry, "noise needs 1 <= amplitude <= 127")
            }
        case .verticalEdge:
            guard colors.count == 2 else { throw failure(entry, "verticalEdge needs 2 colours") }
            guard let edgeX = entry.edgeX, edgeX >= 1, edgeX < entry.width else {
                throw failure(entry, "verticalEdge needs 1 <= edgeX < width")
            }
        case .grid:
            guard colors.count == 2 else { throw failure(entry, "grid needs 2 colours") }
            guard let spacing = entry.spacing, spacing >= 2 else {
                throw failure(entry, "grid needs spacing >= 2")
            }
            guard let lineWidth = entry.lineWidth, lineWidth >= 1, lineWidth < spacing else {
                throw failure(entry, "grid needs 1 <= lineWidth < spacing")
            }
        case .faceSilhouette:
            guard colors.count == 6 else {
                throw failure(entry, "faceSilhouette needs 6 colours (skin, hair, background, eye, lips, shirt)")
            }
        }
    }

    // MARK: - Patterns

    private static func renderSolid(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        let raster = FixtureRaster(width: entry.width, height: entry.height, background: entry.rgbColors[0])
        return try raster.makeBuffer()
    }

    private static func renderGradient(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let axis = entry.axis else {
            throw failure(entry, "linearGradient needs an axis")
        }
        let start = entry.rgbColors[0]
        let end = entry.rgbColors[1]
        var raster = FixtureRaster(width: entry.width, height: entry.height, background: start)

        switch axis {
        case .horizontal:
            for x in 0..<entry.width {
                let color = RGB8(
                    red: gradientValue(from: start.red, to: end.red, index: x, count: entry.width),
                    green: gradientValue(from: start.green, to: end.green, index: x, count: entry.width),
                    blue: gradientValue(from: start.blue, to: end.blue, index: x, count: entry.width)
                )
                for y in 0..<entry.height {
                    raster.setPixel(x: x, y: y, color: color)
                }
            }
        case .vertical:
            for y in 0..<entry.height {
                let color = RGB8(
                    red: gradientValue(from: start.red, to: end.red, index: y, count: entry.height),
                    green: gradientValue(from: start.green, to: end.green, index: y, count: entry.height),
                    blue: gradientValue(from: start.blue, to: end.blue, index: y, count: entry.height)
                )
                for x in 0..<entry.width {
                    raster.setPixel(x: x, y: y, color: color)
                }
            }
        }
        return try raster.makeBuffer()
    }

    private static func renderCheckerboard(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let cellSize = entry.cellSize else {
            throw failure(entry, "checkerboard needs cellSize")
        }
        let light = entry.rgbColors[0]
        let dark = entry.rgbColors[1]
        var raster = FixtureRaster(width: entry.width, height: entry.height, background: light)
        for y in 0..<entry.height {
            for x in 0..<entry.width {
                if ((x / cellSize) + (y / cellSize)) % 2 == 1 {
                    raster.setPixel(x: x, y: y, color: dark)
                }
            }
        }
        return try raster.makeBuffer()
    }

    private static func renderColorChart(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let columns = entry.columns else {
            throw failure(entry, "colorChart needs columns")
        }
        let colors = entry.rgbColors
        let geometry = try colorChartGeometry(entry, columns: columns, colorCount: colors.count)
        var raster = FixtureRaster(
            width: entry.width,
            height: entry.height,
            background: RGB8.midGray
        )
        for (index, color) in colors.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = colorChartMargin + column * (geometry.patchWidth + colorChartGap)
            let y = colorChartMargin + row * (geometry.patchHeight + colorChartGap)
            raster.fillRect(
                x: x,
                y: y,
                width: geometry.patchWidth,
                height: geometry.patchHeight,
                color: color
            )
        }
        return try raster.makeBuffer()
    }

    private static func renderNoise(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let amplitude = entry.amplitude else {
            throw failure(entry, "noise needs amplitude")
        }
        let base = entry.rgbColors[0]
        let span = UInt64(2 * amplitude + 1)
        var generator = SplitMix64(seed: entry.seed)
        var raster = FixtureRaster(width: entry.width, height: entry.height, background: base)
        let baseChannels = [base.red, base.green, base.blue]

        for y in 0..<entry.height {
            for x in 0..<entry.width {
                var channels = [UInt8](repeating: 0, count: 3)
                for channel in 0..<3 {
                    let offset = Int(generator.next() % span) - amplitude
                    channels[channel] = UInt8(
                        clamping: Int(baseChannels[channel]) + offset
                    )
                }
                raster.setPixel(
                    x: x,
                    y: y,
                    color: RGB8(red: channels[0], green: channels[1], blue: channels[2])
                )
            }
        }
        return try raster.makeBuffer()
    }

    private static func renderVerticalEdge(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let edgeX = entry.edgeX else {
            throw failure(entry, "verticalEdge needs edgeX")
        }
        let left = entry.rgbColors[0]
        let right = entry.rgbColors[1]
        var raster = FixtureRaster(width: entry.width, height: entry.height, background: right)
        raster.fillRect(x: 0, y: 0, width: edgeX, height: entry.height, color: left)
        return try raster.makeBuffer()
    }

    private static func renderGrid(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        guard let spacing = entry.spacing, let lineWidth = entry.lineWidth else {
            throw failure(entry, "grid needs spacing and lineWidth")
        }
        let background = entry.rgbColors[0]
        let line = entry.rgbColors[1]
        var raster = FixtureRaster(width: entry.width, height: entry.height, background: background)
        for y in 0..<entry.height {
            for x in 0..<entry.width {
                if x % spacing < lineWidth || y % spacing < lineWidth {
                    raster.setPixel(x: x, y: y, color: line)
                }
            }
        }
        return try raster.makeBuffer()
    }

    private static func renderFaceSilhouette(_ entry: FixtureManifestEntry) throws -> PixelBuffer {
        let colors = entry.rgbColors
        let skin = colors[0]
        let hair = colors[1]
        let background = colors[2]
        let eye = colors[3]
        let lips = colors[4]
        let shirt = colors[5]

        let width = entry.width
        let height = entry.height
        let widthScale = Double(width)
        let heightScale = Double(height)
        let centerX = widthScale / 2.0
        var raster = FixtureRaster(width: width, height: height, background: background)

        // Hair sits behind the face; neck and torso fill the lower third.
        raster.fillEllipse(
            centerX: centerX,
            centerY: 0.40 * heightScale,
            radiusX: 0.30 * widthScale,
            radiusY: 0.30 * heightScale,
            color: hair
        )
        raster.fillCenteredRect(
            centerX: centerX,
            halfWidth: 0.08 * widthScale,
            y0: roundHalfUp(0.62 * heightScale),
            y1: roundHalfUp(0.80 * heightScale),
            color: skin
        )
        raster.fillCenteredRect(
            centerX: centerX,
            halfWidth: 0.50 * widthScale,
            y0: roundHalfUp(0.78 * heightScale),
            y1: height,
            color: shirt
        )
        raster.fillEllipse(
            centerX: centerX,
            centerY: 0.42 * heightScale,
            radiusX: 0.24 * widthScale,
            radiusY: 0.27 * heightScale,
            color: skin
        )

        let eyeOffsetX = 0.095 * widthScale
        let eyeY = 0.40 * heightScale
        let eyeRadiusX = 0.045 * widthScale
        let eyeRadiusY = 0.025 * heightScale
        raster.fillEllipse(
            centerX: centerX - eyeOffsetX,
            centerY: eyeY,
            radiusX: eyeRadiusX,
            radiusY: eyeRadiusY,
            color: eye
        )
        raster.fillEllipse(
            centerX: centerX + eyeOffsetX,
            centerY: eyeY,
            radiusX: eyeRadiusX,
            radiusY: eyeRadiusY,
            color: eye
        )

        let browY = roundHalfUp(0.345 * heightScale)
        let browHeight = max(2, roundHalfUp(0.014 * heightScale))
        let browHalfWidth = 0.05 * widthScale
        let browWidth = roundHalfUp(2 * browHalfWidth)
        raster.fillRect(
            x: roundHalfUp(centerX - eyeOffsetX - browHalfWidth),
            y: browY,
            width: browWidth,
            height: browHeight,
            color: hair
        )
        raster.fillRect(
            x: roundHalfUp(centerX + eyeOffsetX - browHalfWidth),
            y: browY,
            width: browWidth,
            height: browHeight,
            color: hair
        )

        raster.fillEllipse(
            centerX: centerX,
            centerY: 0.545 * heightScale,
            radiusX: 0.075 * widthScale,
            radiusY: 0.022 * heightScale,
            color: lips
        )
        return try raster.makeBuffer()
    }

    // MARK: - Geometry helpers

    private static let colorChartMargin = 10
    private static let colorChartGap = 6

    private struct ColorChartGeometry {
        let patchWidth: Int
        let patchHeight: Int
    }

    private static func colorChartGeometry(
        _ entry: FixtureManifestEntry,
        columns: Int,
        colorCount: Int
    ) throws -> ColorChartGeometry {
        let rows = (colorCount + columns - 1) / columns
        let patchWidth = (entry.width - 2 * colorChartMargin - (columns - 1) * colorChartGap) / columns
        let patchHeight = (entry.height - 2 * colorChartMargin - (rows - 1) * colorChartGap) / rows
        guard patchWidth > 0, patchHeight > 0 else {
            throw failure(entry, "colorChart patches do not fit")
        }
        return ColorChartGeometry(patchWidth: patchWidth, patchHeight: patchHeight)
    }

    /// Integer gradient ramp shared with the Python generator.
    private static func gradientValue(from start: UInt8, to end: UInt8, index: Int, count: Int) -> UInt8 {
        guard count > 1 else { return start }
        let numerator = Int(start) * (count - 1 - index) + Int(end) * index + (count - 1) / 2
        return UInt8(numerator / (count - 1))
    }

    /// Rounds half away from zero for the non-negative geometry values used here.
    static func roundHalfUp(_ value: Double) -> Int {
        Int(value.rounded())
    }

    private static func failure(_ entry: FixtureManifestEntry, _ reason: String) -> GoldenSupportError {
        .invalidFixture(id: entry.id, reason: reason)
    }
}

// MARK: - Probes

/// A single expected colour at a known pixel coordinate.
public struct FixtureColorProbe: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let color: RGB8

    public init(x: Int, y: Int, color: RGB8) {
        self.x = x
        self.y = y
        self.color = color
    }
}

/// Structural probes used by the fixture self-check and available to module
/// tests that want a cheap sanity check without a golden image.
///
/// Reference and generated images are expected to match these probes exactly.
public enum FixtureProbes {
    public static func colorProbes(for entry: FixtureManifestEntry) throws -> [FixtureColorProbe] {
        try FixtureRenderer.validate(entry)
        let colors = entry.rgbColors
        let width = entry.width
        let height = entry.height

        switch entry.kind {
        case .solidColor:
            return [
                FixtureColorProbe(x: 0, y: 0, color: colors[0]),
                FixtureColorProbe(x: width - 1, y: height - 1, color: colors[0]),
                FixtureColorProbe(x: width / 2, y: height / 2, color: colors[0])
            ]
        case .linearGradient:
            if entry.axis == .vertical {
                return [
                    FixtureColorProbe(x: width / 2, y: 0, color: colors[0]),
                    FixtureColorProbe(x: width / 2, y: height - 1, color: colors[1])
                ]
            }
            return [
                FixtureColorProbe(x: 0, y: height / 2, color: colors[0]),
                FixtureColorProbe(x: width - 1, y: height / 2, color: colors[1])
            ]
        case .checkerboard:
            guard let cellSize = entry.cellSize else { return [] }
            return [
                FixtureColorProbe(x: 0, y: 0, color: colors[0]),
                FixtureColorProbe(x: cellSize, y: 0, color: colors[1]),
                FixtureColorProbe(x: 0, y: cellSize, color: colors[1]),
                FixtureColorProbe(x: cellSize, y: cellSize, color: colors[0])
            ]
        case .colorChart:
            guard let columns = entry.columns else { return [] }
            let rows = (colors.count + columns - 1) / columns
            let patchWidth = (width - 2 * 10 - (columns - 1) * 6) / columns
            let patchHeight = (height - 2 * 10 - (rows - 1) * 6) / rows
            var probes = [FixtureColorProbe(x: 0, y: 0, color: .midGray)]
            for (index, color) in colors.enumerated() {
                let row = index / columns
                let column = index % columns
                probes.append(
                    FixtureColorProbe(
                        x: 10 + column * (patchWidth + 6) + patchWidth / 2,
                        y: 10 + row * (patchHeight + 6) + patchHeight / 2,
                        color: color
                    )
                )
            }
            return probes
        case .noise:
            return []
        case .verticalEdge:
            guard let edgeX = entry.edgeX else { return [] }
            return [
                FixtureColorProbe(x: 0, y: height / 2, color: colors[0]),
                FixtureColorProbe(x: edgeX - 1, y: height / 2, color: colors[0]),
                FixtureColorProbe(x: edgeX, y: height / 2, color: colors[1])
            ]
        case .grid:
            guard let spacing = entry.spacing, let lineWidth = entry.lineWidth else { return [] }
            return [
                FixtureColorProbe(x: 0, y: 0, color: colors[1]),
                FixtureColorProbe(x: spacing, y: 0, color: colors[1]),
                FixtureColorProbe(
                    x: spacing / 2 + lineWidth,
                    y: spacing / 2 + lineWidth,
                    color: colors[0]
                )
            ]
        case .faceSilhouette:
            return [
                FixtureColorProbe(x: 2, y: 2, color: colors[2]),
                FixtureColorProbe(
                    x: width / 2,
                    y: FixtureRenderer.roundHalfUp(0.22 * Double(height)),
                    color: colors[0]
                ),
                FixtureColorProbe(
                    x: FixtureRenderer.roundHalfUp(Double(width) / 2 - 0.095 * Double(width)),
                    y: FixtureRenderer.roundHalfUp(0.40 * Double(height)),
                    color: colors[3]
                ),
                FixtureColorProbe(
                    x: width / 2,
                    y: FixtureRenderer.roundHalfUp(0.545 * Double(height)),
                    color: colors[4]
                ),
                FixtureColorProbe(x: width / 2, y: height - 4, color: colors[5])
            ]
        }
    }

    /// True when every row is a mirror image of itself.
    public static func isMirrorSymmetric(_ buffer: PixelBuffer) -> Bool {
        for y in 0..<buffer.height {
            for x in 0..<(buffer.width / 2) {
                if buffer[x, y] != buffer[buffer.width - 1 - x, y] {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - Raster

private struct FixtureRaster {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, background: RGB8) {
        self.width = width
        self.height = height
        self.bytes = [UInt8](repeating: 255, count: width * height * 4)
        fillRect(x: 0, y: 0, width: width, height: height, color: background)
    }

    mutating func setPixel(x: Int, y: Int, color: RGB8) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = (y * width + x) * 4
        bytes[offset] = color.red
        bytes[offset + 1] = color.green
        bytes[offset + 2] = color.blue
        bytes[offset + 3] = 255
    }

    mutating func fillRect(x: Int, y: Int, width rectWidth: Int, height rectHeight: Int, color: RGB8) {
        let startX = max(0, x)
        let startY = max(0, y)
        let endX = min(width, x + rectWidth)
        let endY = min(height, y + rectHeight)
        guard startX < endX, startY < endY else { return }
        for row in startY..<endY {
            var offset = (row * width + startX) * 4
            for _ in startX..<endX {
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = 255
                offset += 4
            }
        }
    }

    mutating func fillCenteredRect(
        centerX: Double,
        halfWidth: Double,
        y0: Int,
        y1: Int,
        color: RGB8
    ) {
        let left = FixtureRenderer.roundHalfUp(centerX - halfWidth)
        let right = width - left
        fillRect(x: left, y: y0, width: right - left, height: y1 - y0, color: color)
    }

    mutating func fillEllipse(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double,
        color: RGB8
    ) {
        guard radiusX > 0, radiusY > 0 else { return }
        let minX = max(0, Int((centerX - radiusX).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + radiusX).rounded(.up)))
        let minY = max(0, Int((centerY - radiusY).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + radiusY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            let normalizedY = ((Double(y) + 0.5) - centerY) / radiusY
            for x in minX...maxX {
                let normalizedX = ((Double(x) + 0.5) - centerX) / radiusX
                if normalizedX * normalizedX + normalizedY * normalizedY <= 1.0 {
                    setPixel(x: x, y: y, color: color)
                }
            }
        }
    }

    func makeBuffer() throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, rgbaBytes: bytes)
    }
}

/// Deterministic PRNG shared with the Python generator (SplitMix64).
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
