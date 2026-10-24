import Foundation
import StyleToneCore

/// Leg slim/lengthen displacement pass (WP-14).
///
/// The pass reads `PortraitAnalysis.body` and `GeometryParameters.body`, then
/// adds a bounded contribution to the shared ``WarpField``. It implements the
/// frozen ``GeometryPass`` contract from `contracts.md` section 4.1 and does not
/// touch the mesh density, boundary policy or the background constraint
/// (WP-15 owns those).
///
/// ## Displacement strategy
///
/// - **Anchors.** The hip, knee and ankle joints define a two-segment
///   centreline. The ankle is the fixed anchor for lengthening: content at and
///   below the ankle does not move, so feet and shoes cannot be stretched or
///   cropped by construction. The knee and hip move upward by the requested
///   non-linear scale, and a smooth waist blend above the shifted hip returns
///   the field to zero.
/// - **Slimming.** Two compact lateral bumps move content towards each leg
///   centreline. The bump peaks on the estimated contour and is zero on the
///   centreline and outside the contour feather. Contour width comes from the
///   person mask when available and from hip separation otherwise.
/// - **Foot protection.** Leg influence fades to zero over
///   ``LegsWarpConfiguration/footGuardHeight`` above the ankle and is exactly
///   zero below it. Cropped ankles make the pass a safe no-op.
/// - **Faces.** Every detected face bounding box is a hard-zero guard during
///   lengthening, so the waist blend cannot pull a chin or jaw.
/// - **Frame edges.** Lateral and vertical contributions taper to zero at the
///   left/right frame edges. Residual sampling at the frame uses WP-06's
///   clamp-to-edge sampler, which is the pixel-level edge extension/fill. The
///   pass therefore never introduces a black border.
/// - **Strength limits.** Lateral displacement is capped by
///   ``LegsWarpConfiguration/maximumLateralDisplacement`` and the contribution
///   is capped by ``LegsWarpConfiguration/maximumContribution``. Lengthening is
///   capped by ``LegsWarpConfiguration/maximumVerticalDisplacement`` and by the
///   frozen `1.00...1.15` range.
///
/// ## Warnings
///
/// ``GeometryPass`` has no warning return channel. Callers that need scene
/// warnings call ``makePlan(analysis:parameters:gridWidth:gridHeight:)`` and
/// read ``LegsWarpPlan/warnings`` and ``LegsWarpPlan/skipReason``. The pass
/// itself never throws for a missing body, an incomplete pose or cropped feet;
/// it contributes nothing and lets the rest of the frame render normally.
public struct LegsWarpContributor: GeometryPass {
    /// Stable pass identifier used by diagnostics and ordering tests.
    public static let passIdentifier = "legs.slim-lengthen"

    /// Stable pass identifier used by diagnostics and ordering tests.
    public let identifier: String

    /// Safety rails and tuning values used by the planner.
    public let configuration: LegsWarpConfiguration

    /// Creates the pass.
    ///
    /// - Parameters:
    ///   - identifier: Stable diagnostics identifier.
    ///   - configuration: Safety rails; defaults to
    ///     ``LegsWarpConfiguration/standard``.
    public init(
        identifier: String = LegsWarpContributor.passIdentifier,
        configuration: LegsWarpConfiguration = .standard
    ) {
        self.identifier = identifier
        self.configuration = configuration
    }

    /// Builds the displacement plan without touching a ``WarpField``.
    ///
    /// The plan contains warnings, the effective strengths and the per-vertex
    /// offsets for the requested mesh density. It has not been boundary-pinned.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when either grid
    ///   axis is smaller than 2.
    public func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridWidth: Int,
        gridHeight: Int
    ) throws -> LegsWarpPlan {
        try LegsWarpPlanner(configuration: configuration).makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    /// Square-grid convenience for ``makePlan(analysis:parameters:gridWidth:gridHeight:)``.
    public func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridDimension: Int
    ) throws -> LegsWarpPlan {
        try makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridDimension,
            gridHeight: gridDimension
        )
    }

    /// Adds the leg contribution to `field`.
    ///
    /// The field uses the plan's density, so preview and export frames
    /// automatically get the correct 32x32 and 64x64 plans. The method never
    /// resizes the field and leaves it untouched when no body, no usable pose
    /// or cropped feet make the pass unsafe.
    public func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        try Task.checkCancellation()
        let plan = try makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: field.width,
            gridHeight: field.height
        )
        try plan.applying(to: &field)
    }
}
