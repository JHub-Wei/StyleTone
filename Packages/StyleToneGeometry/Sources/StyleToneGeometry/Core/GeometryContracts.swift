import Foundation
import StyleToneCore

/// Parameters shared by all geometry passes and constraints.
///
/// This mirrors the frozen internal contract in `contracts.md` §4.1. WP-06 owns
/// the type; WP-12/13/14/15 read it but must not change it.
public struct GeometryParameters: Sendable {
    /// Face shaping strengths.
    public var face: FaceParameters
    /// Body shaping strengths.
    public var body: BodyParameters
    /// When `true`, the registered background constraint runs after the passes.
    public var backgroundProtection: Bool

    public init(
        face: FaceParameters = .neutral,
        body: BodyParameters = .neutral,
        backgroundProtection: Bool = true
    ) {
        self.face = face
        self.body = body
        self.backgroundProtection = backgroundProtection
    }

    /// Neutral parameters: no displacement contributions and background
    /// protection enabled.
    public static let neutral = GeometryParameters()
}

/// A regular grid displacement field.
///
/// The grid has `width * height` vertices, row-major, with vertex `(0, 0)` at
/// normalized image position `(0, 0)` (top-left) and vertex
/// `(width - 1, height - 1)` at `(1, 1)`. `offsets` is always
/// `width * height` long and uses normalized image coordinates.
///
/// **Sign convention:** an offset is the *content* displacement at that vertex.
/// A positive `x` moves content to the right, a positive `y` moves it down.
/// The renderer therefore samples the source image at `position - offset`.
/// This keeps the mapping single-valued (no holes) and makes boundary pinning
/// straightforward.
///
/// The struct is intentionally mutable because passes add their contributions
/// in place. Call ``validate()`` before handing a field to a renderer if the
/// field was assembled outside ``GeometryPipeline``.
public struct WarpField: Sendable {
    /// Number of grid vertices along the horizontal axis (at least 2).
    public var width: Int
    /// Number of grid vertices along the vertical axis (at least 2).
    public var height: Int
    /// Row-major offsets, length `width * height`, normalized image units.
    public var offsets: [SIMD2<Float>]

    /// Creates a zero displacement field.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when either
    ///   dimension is smaller than 2.
    public init(width: Int, height: Int) throws {
        let count = try Self.vertexCount(width: width, height: height)
        try self.init(
            width: width,
            height: height,
            offsets: Array(repeating: SIMD2<Float>(0, 0), count: count)
        )
    }

    /// Wraps caller-provided offsets after validating the grid.
    public init(width: Int, height: Int, offsets: [SIMD2<Float>]) throws {
        self.width = width
        self.height = height
        self.offsets = offsets
        try validate()
    }

    /// Number of vertices in the field.
    public var vertexCount: Int {
        width * height
    }

    /// Row-major index of a vertex, or `nil` when out of bounds.
    public func index(x: Int, y: Int) -> Int? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }
        return y * width + x
    }

    /// Offset of one vertex, or `nil` when out of bounds.
    public func offset(x: Int, y: Int) -> SIMD2<Float>? {
        guard let index = index(x: x, y: y) else {
            return nil
        }
        return offsets[index]
    }

    /// Sets one vertex offset.
    ///
    /// - Returns: `false` when the coordinate is outside the grid.
    @discardableResult
    public mutating func setOffset(_ offset: SIMD2<Float>, x: Int, y: Int) -> Bool {
        guard let index = index(x: x, y: y) else {
            return false
        }
        offsets[index] = offset
        return true
    }

    /// Adds a displacement to one vertex.
    ///
    /// - Returns: `false` when the coordinate is outside the grid.
    @discardableResult
    public mutating func addOffset(_ delta: SIMD2<Float>, x: Int, y: Int) -> Bool {
        guard let index = index(x: x, y: y) else {
            return false
        }
        offsets[index] += delta
        return true
    }

    /// Validates dimensions, offset count and finiteness.
    ///
    /// - Throws: ``GeometryError`` with a diagnostic case that contains no PII.
    public func validate() throws {
        let (expected, overflow) = width.multipliedReportingOverflow(by: height)
        guard width >= 2, height >= 2, !overflow else {
            throw GeometryError.invalidGrid(width: width, height: height)
        }
        guard offsets.count == expected else {
            throw GeometryError.offsetCountMismatch(
                expected: expected,
                actual: offsets.count
            )
        }
        for (index, offset) in offsets.enumerated() {
            guard offset.x.isFinite, offset.y.isFinite else {
                throw GeometryError.nonFiniteOffset(index: index)
            }
        }
    }

    /// `true` when every offset is at most `epsilon` in absolute value.
    public func isZero(epsilon: Float = 1e-6) -> Bool {
        let limit = abs(epsilon)
        return offsets.allSatisfy { offset in
            abs(offset.x) <= limit && abs(offset.y) <= limit
        }
    }

    /// Largest offset magnitude in the field, in normalized image units.
    public var maxMagnitude: Float {
        var maximum: Float = 0
        for offset in offsets {
            let magnitude = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            maximum = max(maximum, magnitude)
        }
        return maximum
    }

    /// Bilinearly interpolates the field at a normalized image position.
    ///
    /// Positions outside `0...1` are clamped to the border, matching the
    /// clamp-to-edge behaviour of the renderer. This is the field-space
    /// interpolation helper used by analysis/debug code; the renderer uses the
    /// exact triangle interpolation in ``MeshWarpSampler`` so CPU and Metal
    /// paths agree.
    public func bilinearOffset(at point: SIMD2<Float>) -> SIMD2<Float> {
        guard width >= 2, height >= 2, offsets.count == width * height else {
            return .zero
        }
        let clamped = SIMD2<Float>(
            min(max(point.x, 0), 1),
            min(max(point.y, 0), 1)
        )
        let gridX = clamped.x * Float(width - 1)
        let gridY = clamped.y * Float(height - 1)
        let x0 = min(Int(gridX), width - 2)
        let y0 = min(Int(gridY), height - 2)
        let x1 = x0 + 1
        let y1 = y0 + 1
        let tx = gridX - Float(x0)
        let ty = gridY - Float(y0)

        let topLeft = offsets[y0 * width + x0]
        let topRight = offsets[y0 * width + x1]
        let bottomLeft = offsets[y1 * width + x0]
        let bottomRight = offsets[y1 * width + x1]
        let top = topLeft * (1 - tx) + topRight * tx
        let bottom = bottomLeft * (1 - tx) + bottomRight * tx
        return top * (1 - ty) + bottom * ty
    }

    private static func vertexCount(width: Int, height: Int) throws -> Int {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width >= 2, height >= 2, !overflow else {
            throw GeometryError.invalidGrid(width: width, height: height)
        }
        return count
    }
}

/// Execution phase of a geometry pass.
///
/// The engine always runs phases in this order regardless of registration
/// order: face, body, legs. Constraints run afterwards.
public enum GeometryPassPhase: Int, Sendable, CaseIterable, Comparable {
    case face = 0
    case body = 1
    case legs = 2

    public static func < (lhs: GeometryPassPhase, rhs: GeometryPassPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Registers a pass with the phase that controls its execution order.
///
/// WP-12/13/14 create one entry each. Keeping the phase outside the frozen
/// `GeometryPass` protocol means the shared contract does not need a change.
public struct GeometryPassEntry: Sendable {
    public let phase: GeometryPassPhase
    public let pass: any GeometryPass

    public init(phase: GeometryPassPhase, pass: any GeometryPass) {
        self.phase = phase
        self.pass = pass
    }
}

/// A source of displacement for the mesh warp.
///
/// Implementations live in the Face/Body/Legs subdirectories. A pass may read
/// all parameters but must only contribute its own phase.
public protocol GeometryPass: Sendable {
    /// Stable identifier used for diagnostics and ordering tests.
    var identifier: String { get }
    /// Adds the pass displacement to `field`.
    func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws
}

/// A post-pass constraint over the combined field.
///
/// WP-15 implements the background protection constraint. Constraints run
/// after every pass and before boundary pinning/feathering.
public protocol GeometryConstraint: Sendable {
    /// Stable identifier used for diagnostics and ordering tests.
    var identifier: String { get }
    /// Rewrites `field` in place.
    func constrain(
        _ field: inout WarpField,
        analysis: PortraitAnalysis
    ) throws
}

/// Geometry failures that can be raised before or during a warp.
///
/// Cases deliberately carry no paths, image identifiers or user data. Callers
/// map this to `StyleToneError.warpingFailed` at the module boundary.
public enum GeometryError: Error, Sendable, Equatable {
    /// Grid dimensions must both be at least 2 and must not overflow.
    case invalidGrid(width: Int, height: Int)
    /// `offsets.count` does not equal `width * height`.
    case offsetCountMismatch(expected: Int, actual: Int)
    /// A pass produced a NaN or infinite offset.
    case nonFiniteOffset(index: Int)
    /// The source image has no pixels.
    case imageTooSmall(width: Int, height: Int)
    /// Metal is not available on this device.
    case metalUnavailable
    /// The embedded Metal shader library failed to compile.
    case shaderCompilationFailed
    /// A Metal pipeline state could not be created.
    case pipelineCreationFailed
    /// A Metal texture or buffer could not be allocated.
    case resourceCreationFailed
    /// A command buffer failed to encode or complete.
    case commandEncodingFailed
    /// An internal measurement/budget argument was invalid.
    case invalidMeasurement
}

extension GeometryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidGrid(width, height):
            return "Invalid geometry grid \(width)x\(height); both axes need at least 2 vertices."
        case let .offsetCountMismatch(expected, actual):
            return "Warp field expected \(expected) offsets but received \(actual)."
        case let .nonFiniteOffset(index):
            return "Warp field contains a non-finite offset at index \(index)."
        case let .imageTooSmall(width, height):
            return "Image is too small for geometry warping (\(width)x\(height))."
        case .metalUnavailable:
            return "Metal is not available on this device."
        case .shaderCompilationFailed:
            return "The geometry Metal shader failed to compile."
        case .pipelineCreationFailed:
            return "The geometry Metal pipeline could not be created."
        case .resourceCreationFailed:
            return "The geometry renderer could not allocate a GPU resource."
        case .commandEncodingFailed:
            return "The geometry GPU command failed."
        case .invalidMeasurement:
            return "The geometry performance measurement arguments were invalid."
        }
    }
}
