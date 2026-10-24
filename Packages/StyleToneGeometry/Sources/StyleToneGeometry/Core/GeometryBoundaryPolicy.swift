import Foundation

/// Boundary handling applied after every pass and constraint.
///
/// Two independent mechanisms protect the frame:
///
/// 1. **Pinning** – the outer `pinnedBorderVertices` rings are forced to zero
///    displacement. The image edge therefore never moves.
/// 2. **Feathering** – displacement is scaled by a smoothstep ramp over
///    `featherCells` grid cells so that the transition from the pinned border to
///    the interior is continuous. This prevents visible creases or black gaps.
///
/// A final magnitude clamp bounds every offset before it reaches the renderer.
/// The renderer also uses a clamp-to-edge sampler, so even a deliberately large
/// interior displacement cannot expose empty (black/transparent) texels.
public struct GeometryBoundaryPolicy: Sendable, Equatable {
    /// Number of outer vertex rings forced to exactly zero displacement.
    public var pinnedBorderVertices: Int
    /// Number of cells used for the smoothstep feather ramp after pinning.
    public var featherCells: Int
    /// Maximum offset magnitude in normalized image coordinates.
    public var maximumDisplacement: Float

    public init(
        pinnedBorderVertices: Int = 1,
        featherCells: Int = 4,
        maximumDisplacement: Float = 0.25
    ) {
        self.pinnedBorderVertices = max(0, pinnedBorderVertices)
        self.featherCells = max(0, featherCells)
        self.maximumDisplacement = max(0, maximumDisplacement)
    }

    /// Default policy used by preview and export warps.
    public static let standard = GeometryBoundaryPolicy()

    /// Weight applied to a vertex at `(x, y)` in a `width * height` grid.
    ///
    /// The weight is `0` on pinned rings, ramps with smoothstep over
    /// ``featherCells`` and reaches `1` in the interior.
    public func weight(x: Int, y: Int, width: Int, height: Int) -> Float {
        guard width >= 2, height >= 2 else {
            return 0
        }
        let edgeDistance = min(min(x, y), min(width - 1 - x, height - 1 - y))
        guard edgeDistance >= pinnedBorderVertices else {
            return 0
        }
        guard featherCells > 0 else {
            return 1
        }
        let ramp = Float(edgeDistance - pinnedBorderVertices) / Float(featherCells)
        let t = min(max(ramp, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Applies pinning, feathering and the magnitude clamp to `field`.
    ///
    /// - Throws: ``GeometryError`` when the field is structurally invalid.
    public func apply(to field: inout WarpField) throws {
        try field.validate()
        guard !field.offsets.isEmpty else {
            return
        }

        let width = field.width
        let height = field.height
        let limit = maximumDisplacement

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = y * width + x
                let weight = weight(x: x, y: y, width: width, height: height)
                var offset = field.offsets[index]
                if weight <= 0 {
                    field.offsets[index] = .zero
                    continue
                }
                if weight < 1 {
                    offset = offset * weight
                }
                let magnitude = (offset.x * offset.x + offset.y * offset.y).squareRoot()
                if magnitude > limit, magnitude > 0 {
                    offset = offset * (limit / magnitude)
                }
                field.offsets[index] = offset
            }
        }
    }
}
