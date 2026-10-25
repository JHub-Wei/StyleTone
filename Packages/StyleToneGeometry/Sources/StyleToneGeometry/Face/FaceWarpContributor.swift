import Foundation
import StyleToneCore

/// Face slim/jaw displacement pass (WP-12).
///
/// The pass reads `PortraitAnalysis.faces` and `GeometryParameters.face`, then
/// adds a horizontal, mirror-symmetric inward displacement around every usable
/// face. It implements the frozen ``GeometryPass`` contract from
/// `contracts.md` section 4.1; it does not touch the mesh density, the boundary
/// policy or the background constraint (WP-15 owns those).
///
/// ## Displacement strategy
///
/// - The symmetry axis is the midpoint of the two eye centres. All geometry is
///   symmetric about it; feature guards are mirrored as well, so asymmetric
///   detections still produce a symmetric field.
/// - `slim` drives a cheek band (just below the eyes through the mid-face) and
///   `jaw` drives a lower band (jaw line through the chin). Both move content
///   towards the axis, which narrows the visible face.
/// - The lateral envelope is zero on the centre line, peaks over the cheek and
///   fades out just outside the face contour. The vertical envelope is zero on
///   and above the eye line (hairline/forehead) and fades out below the chin.
/// - Eyes, eyebrows, nose, outer lips and inner lips (teeth) are protected by
///   hard-zero guards with a smooth falloff. No strength can move those
///   features.
/// - The combined displacement is capped by
///   ``FaceWarpConfiguration/maximumCombinedDisplacementFraction`` * face width
///   and by ``FaceWarpConfiguration/maximumAbsoluteDisplacement``.
/// - Faces are processed largest-bounding-box first, up to
///   ``FaceWarpConfiguration/maximumFaceCount``. Overlapping contributions are
///   blended instead of summed.
///
/// ## Warnings
///
/// ``GeometryPass`` has no warning return channel. Call
/// ``plan(for:parameters:gridWidth:gridHeight:)`` directly to obtain the same
/// displacement plus ``FaceWarpPlan/warnings`` and per-face metrics; the editor
/// can use that for scene warnings. The pass itself never throws for a missing
/// face, an unusable face or missing landmarks: it silently contributes nothing
/// for that face so one bad detection cannot fail the frame.
public struct FaceWarpContributor: GeometryPass {
    /// Stable pass identifier used by diagnostics and ordering tests.
    public static let passIdentifier = "face.slim"

    /// Stable pass identifier used by diagnostics and ordering tests.
    public let identifier = FaceWarpContributor.passIdentifier

    /// Safety rails and tuning values used by the planner.
    public let configuration: FaceWarpConfiguration

    /// Creates the pass.
    ///
    /// - Parameter configuration: Safety rails; defaults to
    ///   ``FaceWarpConfiguration/standard``.
    public init(configuration: FaceWarpConfiguration = .standard) {
        self.configuration = configuration
    }

    /// Builds the displacement plan without touching a ``WarpField``.
    ///
    /// Callers that need warnings or per-face metrics (for example the editor
    /// warning strip) use this method and pass the plan to
    /// ``FaceWarpPlan/applying(to:)`` themselves. The returned plan has the
    /// requested mesh density and has not yet been boundary-pinned.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the mesh
    ///   density is smaller than 2 vertices per axis.
    public func plan(
        for analysis: PortraitAnalysis,
        parameters: FaceParameters,
        gridWidth: Int,
        gridHeight: Int
    ) throws -> FaceWarpPlan {
        try FaceWarpPlanner(configuration: configuration).makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    /// Square-grid convenience for ``plan(for:parameters:gridWidth:gridHeight:)``.
    ///
    /// Preview uses 32 and export uses 64 vertices per axis; see
    /// ``GeometryQuality``.
    public func plan(
        for analysis: PortraitAnalysis,
        parameters: FaceParameters,
        gridDimension: Int
    ) throws -> FaceWarpPlan {
        try plan(
            for: analysis,
            parameters: parameters,
            gridWidth: gridDimension,
            gridHeight: gridDimension
        )
    }

    /// Adds the face contribution to `field`.
    ///
    /// The field's density is used for planning, so preview and export frames
    /// automatically get 32x32 and 64x64 plans. The method never resizes the
    /// field and leaves it untouched when no face is usable.
    public func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        try Task.checkCancellation()
        let plan = try plan(
            for: analysis,
            parameters: parameters.face,
            gridWidth: field.width,
            gridHeight: field.height
        )
        try plan.applying(to: &field)
    }
}
