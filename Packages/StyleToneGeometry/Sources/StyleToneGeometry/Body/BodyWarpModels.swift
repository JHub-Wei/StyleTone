import Foundation

/// A diagnostic raised by the body pass.
///
/// The frozen ``GeometryPass`` protocol has no warning return value. Call
/// ``BodyWarpContributor/makePlan(analysis:parameters:gridWidth:gridHeight:)``
/// when the caller needs warnings for a preview/UI; ``BodyWarpContributor``'s
/// contribution itself remains a pure, stateless pass.
public enum BodyWarpWarning: String, Sendable, Hashable, CaseIterable, Codable {
    /// No ``BodyObservation`` was supplied.
    case noBody
    /// Shaping was requested but no person mask is available.
    case noSegmentation
    /// The body observation confidence is low, or the analysis reports low
    /// confidence.
    case lowConfidence
    /// The analysis reports occlusion, or the person mask does not cover a
    /// required body region.
    case occlusion
    /// A second person was detected and the policy skipped or downgraded.
    case multiplePeople
    /// A required joint is missing; unaffected regions may still be shaped.
    case incompletePose
    /// A limb/torso has zero-length or implausible segments.
    case degeneratePose
    /// The person mask exists, but not enough contour evidence was found.
    case weakSegmentation
    /// A configured displacement cap was reached.
    case strengthLimited
}

/// Body regions that received a non-zero contribution in a plan.
public enum BodyWarpRegion: String, Sendable, Hashable, CaseIterable, Codable {
    /// The subject's left arm, as labelled by the pose detector.
    case leftArm
    /// The subject's right arm.
    case rightArm
    /// The waist band between shoulder centre and hip centre.
    case waist
}

/// The complete, inspectable output of the body planner.
///
/// Offsets use the ``WarpField`` sign convention (content displacement in
/// normalized image coordinates). The field is *not* boundary-pinned; the
/// WP-06 pipeline applies its boundary policy after all passes.
public struct BodyWarpPlan: Sendable, Equatable {
    /// Grid width the plan was computed for.
    public let width: Int
    /// Grid height the plan was computed for.
    public let height: Int
    /// Row-major normalized content offsets, length `width * height`.
    public let offsets: [SIMD2<Float>]
    /// Diagnostics in stable order.
    public let warnings: [BodyWarpWarning]
    /// Regions that received a non-zero contribution.
    public let appliedRegions: Set<BodyWarpRegion>
    /// Largest offset in short-side image units.
    public let peakDisplacement: Double
    /// `true` when the combined per-vertex cap changed at least one offset.
    public let didClampToLimit: Bool

    /// `true` when no body region received displacement.
    public var isEmpty: Bool {
        appliedRegions.isEmpty
    }

    /// Adds the planned offsets to an existing field.
    ///
    /// The field density must match the plan. The method never resizes the field
    /// and does not apply boundary pinning.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the field
    ///   density differs, or
    ///   ``GeometryError/offsetCountMismatch(expected:actual:)`` when the arrays
    ///   do not line up.
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
        warnings: [BodyWarpWarning],
        appliedRegions: Set<BodyWarpRegion>,
        peakDisplacement: Double,
        didClampToLimit: Bool
    ) {
        self.width = width
        self.height = height
        self.offsets = offsets
        self.warnings = warnings
        self.appliedRegions = appliedRegions
        self.peakDisplacement = peakDisplacement
        self.didClampToLimit = didClampToLimit
    }
}
