import Foundation
import StyleToneCore

/// Non-fatal issues found while planning the leg slim/lengthen contribution.
///
/// The frozen ``GeometryPass`` protocol has no warning return channel. Callers
/// that need user feedback (the editor warning strip, for example) use
/// ``LegsWarpContributor/makePlan(analysis:parameters:gridWidth:gridHeight:)``
/// and read ``LegsWarpPlan/warnings``. The pass itself applies the same plan.
///
/// Warnings contain no paths, image identifiers or other PII.
public enum LegsWarpWarning: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// No ``BodyObservation`` was supplied. The pass is a safe no-op.
    case noBody
    /// The body observation or the analysis reports low confidence.
    case lowConfidence
    /// A required hip/knee/ankle joint is missing.
    case incompletePose
    /// Joint geometry is non-finite, inverted or crossing.
    case degeneratePose
    /// The ankles are too close to the bottom of the frame (feet may be cut).
    case feetOutsideFrame
    /// Both sliders are at their neutral values.
    case neutralParameters
    /// No vertex received a displacement (for example the person mask does not
    /// cover the legs).
    case noUsableRegion
    /// No person mask was available; the planner used the pose-derived leg
    /// width fallback. The contribution is still applied.
    case noPersonMask
    /// The analysis reported occlusion; strengths were reduced by
    /// ``LegsWarpConfiguration/occlusionScale``.
    case occlusionReduced
    /// A configured displacement cap reduced the requested strength.
    case strengthLimited
}

/// Why a leg plan contains no displacement.
///
/// A skipped plan is a normal, non-throwing result: the body may be absent, the
/// pose may be unusable, the feet may be cropped or both sliders may be
/// neutral. The pass leaves the field untouched in all of those cases.
public enum LegsWarpSkipReason: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// ``PortraitAnalysis/body`` was `nil`.
    case noBody
    /// Body confidence was below the configured minimum, or the analysis
    /// reported `lowConfidence`.
    case lowConfidence
    /// One or more of hip, knee and ankle joints are missing.
    case incompletePose
    /// The pose is non-finite, inverted, too asymmetric or the legs cross.
    case degeneratePose
    /// An ankle is too close to the frame edge for safe foot preservation.
    case feetOutsideFrame
    /// Both `BodyParameters.leg` and `BodyParameters.legLength` are neutral.
    case neutralParameters
    /// The parameters were non-neutral but no vertex received displacement.
    case noUsableRegion
}

/// The complete, inspectable output of the leg planner.
///
/// Offsets use the ``WarpField`` sign convention: content displacement in
/// normalized image coordinates, positive `x` right and positive `y` down. A
/// leg is slimmed by moving content towards its centreline; lengthening moves
/// leg content upward while the ankle/foot region stays fixed.
///
/// The plan is not boundary-pinned. The WP-06 pipeline applies its boundary
/// policy after all passes have contributed.
public struct LegsWarpPlan: Sendable, Equatable {
    /// Grid width the plan was computed for.
    public let width: Int
    /// Grid height the plan was computed for.
    public let height: Int
    /// Row-major normalized content offsets, length `width * height`.
    public let offsets: [SIMD2<Float>]
    /// Diagnostics in stable order.
    public let warnings: [LegsWarpWarning]
    /// Set when the plan deliberately contains no displacement.
    public let skipReason: LegsWarpSkipReason?
    /// Effective `BodyParameters.leg` strength after occlusion scaling.
    public let effectiveSlimStrength: Double
    /// Effective `BodyParameters.legLength` multiplier after caps. `1.0` means
    /// the leg length was not changed.
    public let effectiveLegLength: Double
    /// Largest per-vertex offset magnitude in normalized image units.
    public let peakDisplacement: Float
    /// Number of vertices with a non-zero offset.
    public let deformedVertexCount: Int
    /// `true` when the per-vertex contribution cap changed at least one offset.
    public let didClampToLimit: Bool

    /// `true` when the plan contains no displacement.
    public var isEmpty: Bool {
        skipReason != nil || deformedVertexCount == 0
    }

    /// Offset of one vertex, or `nil` when out of bounds.
    public func offset(x: Int, y: Int) -> SIMD2<Float>? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }
        return offsets[y * width + x]
    }

    /// Adds this plan's offsets to an existing field.
    ///
    /// The field must use the same mesh density as the plan.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the field
    ///   density differs, or
    ///   ``GeometryError/offsetCountMismatch(expected:actual:)`` when the
    ///   arrays do not line up.
    public func applying(to field: inout WarpField) throws {
        guard field.width == width, field.height == height else {
            throw GeometryError.invalidGrid(width: width, height: height)
        }
        guard field.offsets.count == offsets.count else {
            throw GeometryError.offsetCountMismatch(
                expected: field.offsets.count,
                actual: offsets.count
            )
        }
        for index in offsets.indices {
            field.offsets[index] += offsets[index]
        }
    }

    init(
        width: Int,
        height: Int,
        offsets: [SIMD2<Float>],
        warnings: [LegsWarpWarning],
        skipReason: LegsWarpSkipReason?,
        effectiveSlimStrength: Double,
        effectiveLegLength: Double,
        peakDisplacement: Float,
        deformedVertexCount: Int,
        didClampToLimit: Bool
    ) {
        self.width = width
        self.height = height
        self.offsets = offsets
        self.warnings = warnings
        self.skipReason = skipReason
        self.effectiveSlimStrength = effectiveSlimStrength
        self.effectiveLegLength = effectiveLegLength
        self.peakDisplacement = peakDisplacement
        self.deformedVertexCount = deformedVertexCount
        self.didClampToLimit = didClampToLimit
    }

    /// Builds a deliberately empty plan for a safe skip.
    static func skipped(
        _ reason: LegsWarpSkipReason,
        warnings: [LegsWarpWarning],
        width: Int,
        height: Int,
        slimStrength: Double,
        legLength: Double
    ) -> LegsWarpPlan {
        LegsWarpPlan(
            width: width,
            height: height,
            offsets: Array(repeating: SIMD2<Float>(0, 0), count: width * height),
            warnings: warnings,
            skipReason: reason,
            effectiveSlimStrength: slimStrength,
            effectiveLegLength: legLength,
            peakDisplacement: 0,
            deformedVertexCount: 0,
            didClampToLimit: false
        )
    }
}
