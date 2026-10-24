import Foundation

/// Maps an output position to the source position for the mesh warp.
///
/// The renderer keeps the mesh vertices on a regular grid and displaces only
/// the texture coordinates (`uv = gridPosition - offset`). Consequently the
/// output space is a regular grid and the mapping can be evaluated exactly on
/// the CPU without an iterative inverse solve.
///
/// The CPU implementation splits every cell along the same diagonal as the
/// Metal index buffer, so both backends interpolate the same triangle and
/// differ only in floating-point precision.
public enum MeshWarpSampler {
    /// Returns the normalized source position for a normalized output point.
    ///
    /// - Parameters:
    ///   - point: Output position in `0...1` (top-left origin, y down). Values
    ///     outside the image are clamped to the border.
    ///   - field: A structurally valid warp field.
    /// - Returns: Source position in normalized coordinates. The value can be
    ///   outside `0...1`; callers sampling a texture must clamp it.
    public static func sourcePosition(
        for point: SIMD2<Float>,
        field: WarpField
    ) -> SIMD2<Float> {
        guard field.width >= 2, field.height >= 2,
              field.offsets.count == field.width * field.height
        else {
            return point
        }

        let clamped = SIMD2<Float>(
            min(max(point.x, 0), 1),
            min(max(point.y, 0), 1)
        )
        let gridX = clamped.x * Float(field.width - 1)
        let gridY = clamped.y * Float(field.height - 1)
        let cellX = min(Int(gridX), field.width - 2)
        let cellY = min(Int(gridY), field.height - 2)
        let fractionX = gridX - Float(cellX)
        let fractionY = gridY - Float(cellY)

        let topLeft = field.offsets[cellY * field.width + cellX]
        let topRight = field.offsets[cellY * field.width + cellX + 1]
        let bottomLeft = field.offsets[(cellY + 1) * field.width + cellX]
        let bottomRight = field.offsets[(cellY + 1) * field.width + cellX + 1]

        let interpolated: SIMD2<Float>
        if fractionX + fractionY <= 1 {
            // Triangle (topLeft, topRight, bottomLeft).
            interpolated = topLeft * (1 - fractionX - fractionY)
                + topRight * fractionX
                + bottomLeft * fractionY
        } else {
            // Triangle (topRight, bottomRight, bottomLeft).
            let bottomRightWeight = fractionX + fractionY - 1
            interpolated = bottomRight * bottomRightWeight
                + bottomLeft * (1 - fractionX)
                + topRight * (1 - fractionY)
        }
        return clamped - interpolated
    }

    /// Returns the normalized source position for a pixel center.
    public static func sourcePosition(
        forPixelX pixelX: Int,
        pixelY: Int,
        width: Int,
        height: Int,
        field: WarpField
    ) -> SIMD2<Float> {
        let point = SIMD2<Float>(
            (Float(pixelX) + 0.5) / Float(max(width, 1)),
            (Float(pixelY) + 0.5) / Float(max(height, 1))
        )
        return sourcePosition(for: point, field: field)
    }
}
