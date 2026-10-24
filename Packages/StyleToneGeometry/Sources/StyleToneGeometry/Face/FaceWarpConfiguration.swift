import Foundation

/// Tunables for the face slim/jaw geometry pass (WP-12).
///
/// Displacement distances are expressed as a fraction of the face width so the
/// same slider value behaves consistently for a close-up and for a face in a
/// group photo. Protection distances use normalized image units (`0...1`).
///
/// Every limit is a safety rail rather than a style choice: the planner clamps
/// the combined displacement to ``maximumCombinedDisplacementFraction`` * face
/// width and to ``maximumAbsoluteDisplacement`` in normalized image units. The
/// engine's ``GeometryBoundaryPolicy`` applies a second, coarser clamp after all
/// passes have contributed.
public struct FaceWarpConfiguration: Sendable, Equatable {
    /// Faces whose detection confidence is below this value are skipped and
    /// reported through ``FaceWarpWarning/lowConfidence(faceIndex:confidence:)``.
    public var minimumFaceConfidence: Float

    /// Faces whose bounding-box area is below this fraction of the image are
    /// skipped and reported through ``FaceWarpWarning/faceTooSmall(faceIndex:areaFraction:)``.
    ///
    /// The default (`0.0025`, i.e. 0.25 % of the frame) removes background
    /// bystanders while still accepting small faces in a group portrait.
    public var minimumFaceAreaFraction: Float

    /// Maximum number of faces processed per frame. Faces are ordered by
    /// bounding-box area, largest first, so the primary subject is always kept.
    public var maximumFaceCount: Int

    /// Peak inward displacement of the cheek band for `FaceParameters.slim == 1`,
    /// as a fraction of the face width.
    public var slimDisplacementFraction: Float

    /// Peak inward displacement of the jaw band for `FaceParameters.jaw == 1`,
    /// as a fraction of the face width.
    public var jawDisplacementFraction: Float

    /// Upper bound for the combined slim + jaw displacement, as a fraction of
    /// the face width. Reached at high slider values before the absolute cap.
    public var maximumCombinedDisplacementFraction: Float

    /// Absolute displacement cap in normalized image units. This keeps a very
    /// large face (or a badly estimated bounding box) from producing a large
    /// pixel shift even when the fractional cap would allow one.
    public var maximumAbsoluteDisplacement: Float

    /// Minimum margin, in normalized image units, added on every side of a
    /// facial-feature guard.
    ///
    /// The planner raises the effective margin to at least one full mesh cell
    /// (`1.05 / (gridDimension - 1)`) so that every grid vertex surrounding a
    /// feature is inside the hard-zero core. Bilinear sampling at the feature
    /// point is then exactly zero at both 32x32 preview and 64x64 export
    /// density. This value can only make the guard stronger.
    public var featureProtectionMargin: Float

    /// Width of the smoothstep falloff outside a feature guard, in normalized
    /// image units. Inside the guard the displacement is exactly zero; it ramps
    /// to full strength outside guard + feather.
    public var featureProtectionFeather: Float

    /// Creates a configuration, clamping every value into a safe range.
    public init(
        minimumFaceConfidence: Float = 0.35,
        minimumFaceAreaFraction: Float = 0.0025,
        maximumFaceCount: Int = 4,
        slimDisplacementFraction: Float = 0.045,
        jawDisplacementFraction: Float = 0.035,
        maximumCombinedDisplacementFraction: Float = 0.065,
        maximumAbsoluteDisplacement: Float = 0.04,
        featureProtectionMargin: Float = 0.02,
        featureProtectionFeather: Float = 0.02
    ) {
        self.minimumFaceConfidence = min(max(minimumFaceConfidence, 0), 1)
        self.minimumFaceAreaFraction = max(minimumFaceAreaFraction, 0)
        self.maximumFaceCount = max(maximumFaceCount, 1)
        self.slimDisplacementFraction = max(slimDisplacementFraction, 0)
        self.jawDisplacementFraction = max(jawDisplacementFraction, 0)
        self.maximumCombinedDisplacementFraction = max(
            maximumCombinedDisplacementFraction,
            0
        )
        self.maximumAbsoluteDisplacement = max(maximumAbsoluteDisplacement, 0)
        self.featureProtectionMargin = max(featureProtectionMargin, 0)
        self.featureProtectionFeather = max(featureProtectionFeather, 0)
    }

    /// Default configuration used by the engine.
    public static let standard = FaceWarpConfiguration()
}
