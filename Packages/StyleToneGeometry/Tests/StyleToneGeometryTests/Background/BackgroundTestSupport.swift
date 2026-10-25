import Foundation
import StyleToneCore
import TestShared
@testable import StyleToneGeometry

/// Deterministic synthetic analyses, masks and warp fields for the WP-15 tests.
///
/// All backgrounds are synthetic line drawings (door frames, tile seams, table
/// edges). No real photo, face image or facial landmark derived from a photo is
/// used.
enum BackgroundTestSupport {
    static let size = PixelSize(width: 240, height: 180)
    static let compactSize = PixelSize(width: 160, height: 120)
    static let defaultGrid = 32

    // MARK: Masks

    /// Draws horizontal and vertical lines into an 8-bit edge mask.
    ///
    /// Tuples are `(position, start, end)` in normalized top-left coordinates.
    static func edgeMask(
        size: PixelSize = size,
        horizontal: [(Double, Double, Double)] = [],
        vertical: [(Double, Double, Double)] = [],
        thickness: Int = 2,
        value: UInt8 = 255
    ) throws -> MaskBuffer {
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        let lineThickness = max(1, thickness)

        for line in horizontal {
            let position = Int((line.0 * Double(size.height)).rounded())
            let start = max(0, Int((line.1 * Double(size.width)).rounded(.down)))
            let end = min(size.width, Int((line.2 * Double(size.width)).rounded(.up)))
            let low = max(0, position - lineThickness / 2)
            let high = min(size.height, low + lineThickness)
            guard start < end else { continue }
            for y in low ..< high {
                let row = y * size.width
                for x in start ..< end {
                    bytes[row + x] = value
                }
            }
        }

        for line in vertical {
            let position = Int((line.0 * Double(size.width)).rounded())
            let start = max(0, Int((line.1 * Double(size.height)).rounded(.down)))
            let end = min(size.height, Int((line.2 * Double(size.height)).rounded(.up)))
            let low = max(0, position - lineThickness / 2)
            let high = min(size.width, low + lineThickness)
            guard start < end, low < high else { continue }
            for x in low ..< high {
                for y in start ..< end {
                    bytes[y * size.width + x] = value
                }
            }
        }

        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }

    /// A regular floor-tile / window-grid pattern.
    static func gridMask(
        size: PixelSize = size,
        spacing: Double = 0.2,
        inset: Double = 0.1,
        thickness: Int = 2
    ) throws -> MaskBuffer {
        var horizontal: [(Double, Double, Double)] = []
        var vertical: [(Double, Double, Double)] = []
        var position = spacing
        while position < 1 - 1e-9 {
            horizontal.append((position, inset, 1 - inset))
            vertical.append((position, inset, 1 - inset))
            position += spacing
        }
        return try edgeMask(
            size: size,
            horizontal: horizontal,
            vertical: vertical,
            thickness: thickness
        )
    }

    /// Door frame: two full-height jambs, a lintel and a threshold.
    static func doorFrameMask(size: PixelSize = size) throws -> MaskBuffer {
        try edgeMask(
            size: size,
            horizontal: [(0.10, 0.22, 0.78), (0.90, 0.22, 0.78)],
            vertical: [(0.22, 0.10, 0.90), (0.78, 0.10, 0.90)]
        )
    }

    /// A single table edge running across the lower half of the frame.
    static func tableEdgeMask(size: PixelSize = size) throws -> MaskBuffer {
        try edgeMask(
            size: size,
            horizontal: [(0.58, 0.12, 0.88)],
            thickness: 3
        )
    }

    /// A diagonal edge (not detected as a line, must still get edge damping).
    static func diagonalMask(size: PixelSize = size) throws -> MaskBuffer {
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        let steps = size.width * 3
        for step in 0 ... steps {
            let t = Double(step) / Double(steps)
            let x = Int((0.15 + t * 0.7) * Double(size.width))
            let y = Int((0.15 + t * 0.7) * Double(size.height))
            for deltaY in -1 ... 1 {
                for deltaX in -1 ... 1 {
                    let px = x + deltaX
                    let py = y + deltaY
                    guard px >= 0, py >= 0, px < size.width, py < size.height else { continue }
                    bytes[py * size.width + px] = 255
                }
            }
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }

    /// Dense texture: every pixel is an edge. A line detector must reject it
    /// because there is no thin ridge.
    static func denseTextureMask(size: PixelSize = size) throws -> MaskBuffer {
        try MaskBuffer(
            width: size.width,
            height: size.height,
            bytes: Data(repeating: 255, count: size.width * size.height)
        )
    }

    /// Sparse isolated edges: edges exist but no long run.
    static func sparseEdgeMask(size: PixelSize = size) throws -> MaskBuffer {
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        for index in 0 ..< 90 {
            let x = (index * 37 + 11) % size.width
            let y = (index * 53 + 7) % size.height
            bytes[y * size.width + x] = 255
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }

    /// A soft elliptical person mask (no real person image).
    static func personMask(
        size: PixelSize = size,
        rect: NormalizedRect = NormalizedRect(x: 0.14, y: 0.08, width: 0.72, height: 0.84),
        feather: Double = 0.10
    ) throws -> MaskBuffer {
        try MockMaskFactory.ellipse(size: size, rect: rect, feather: feather)
    }

    // MARK: Analysis

    static func analysis(
        size: PixelSize = size,
        faces: [FaceObservation] = [],
        body: BodyObservation? = nil,
        personMask: MaskBuffer? = nil,
        edgeMask: MaskBuffer? = nil
    ) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: size,
            faces: faces,
            body: body,
            personMask: personMask,
            skinMask: nil,
            backgroundEdgeMask: edgeMask,
            warnings: []
        )
    }

    /// A mock portrait face with all landmarks; not derived from a photo.
    static func face(
        boundingBox: NormalizedRect = MockPortraitAnalysisFactory.defaultFaceRect,
        confidence: Float = 0.95
    ) -> FaceObservation {
        MockPortraitAnalysisFactory.faceObservation(
            boundingBox: boundingBox,
            confidence: confidence
        )
    }

    /// A plausible standing pose built from normalized joints.
    static func body(confidence: Float = 0.9) -> BodyObservation {
        MockPortraitAnalysisFactory.bodyObservation(confidence: confidence)
    }

    // MARK: Fields

    /// Builds a field from a closure over normalized `(x, y)`.
    static func field(
        dimension: Int = defaultGrid,
        offset: (Double, Double) -> SIMD2<Float>
    ) throws -> WarpField {
        var field = try WarpField(width: dimension, height: dimension)
        for y in 0 ..< dimension {
            let ny = Double(y) / Double(dimension - 1)
            let row = y * dimension
            for x in 0 ..< dimension {
                let nx = Double(x) / Double(dimension - 1)
                field.offsets[row + x] = offset(nx, ny)
            }
        }
        return field
    }

    /// Horizontal sine wave: a vertical background line would bend with it.
    static func horizontalWaveField(
        dimension: Int = defaultGrid,
        amplitude: Float = 0.02,
        cycles: Double = 1,
        phase: Double = 0
    ) throws -> WarpField {
        try field(dimension: dimension) { _, y in
            let value = sin(2 * Double.pi * cycles * y + phase) * Double(amplitude)
            return SIMD2<Float>(Float(value), 0)
        }
    }

    /// Vertical Gaussian bump: a horizontal background line would bend with it.
    static func verticalBumpField(
        dimension: Int = defaultGrid,
        amplitude: Float = 0.02,
        centerX: Double = 0.5,
        centerY: Double = 0.58,
        sigma: Double = 0.10
    ) throws -> WarpField {
        try field(dimension: dimension) { x, y in
            let dx = (x - centerX) / sigma
            let dy = (y - centerY) / sigma
            let value = exp(-0.5 * (dx * dx + dy * dy)) * Double(amplitude)
            return SIMD2<Float>(0, Float(value))
        }
    }

    /// A constant horizontal shift, used for retention ratios.
    static func constantField(
        dimension: Int = defaultGrid,
        offset: SIMD2<Float> = SIMD2<Float>(0.01, 0)
    ) throws -> WarpField {
        try field(dimension: dimension) { _, _ in offset }
    }

    /// A face slim/jaw field produced by the real WP-12 pass.
    static func faceField(
        analysis: PortraitAnalysis,
        dimension: Int = 64,
        slim: Double = 0.85,
        jaw: Double = 0.75
    ) throws -> WarpField {
        var field = try WarpField(width: dimension, height: dimension)
        try FaceWarpContributor().contribute(
            to: &field,
            analysis: analysis,
            parameters: GeometryParameters(
                face: FaceParameters(slim: slim, jaw: jaw)
            )
        )
        return field
    }

    // MARK: Metrics helpers

    static func magnitude(_ offset: SIMD2<Float>) -> Float {
        (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    /// Mean displacement magnitude over the face bounding box.
    static func meanMagnitude(
        _ field: WarpField,
        in rect: NormalizedRect
    ) -> Float {
        var sum: Float = 0
        var count = 0
        for y in 0 ..< field.height {
            let ny = Float(y) / Float(field.height - 1)
            guard Float(rect.minY) <= ny, ny <= Float(rect.maxY) else { continue }
            for x in 0 ..< field.width {
                let nx = Float(x) / Float(field.width - 1)
                guard Float(rect.minX) <= nx, nx <= Float(rect.maxX) else { continue }
                sum += magnitude(field.offsets[y * field.width + x])
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return sum / Float(count)
    }

    static func maximumMagnitude(_ field: WarpField) -> Float {
        field.maxMagnitude
    }
}
