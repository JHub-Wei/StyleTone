import Foundation

/// Tunables and safety rails for the WP-14 leg slim/lengthen pass.
///
/// All distances are normalized image units unless stated otherwise: `x` is a
/// fraction of the image width, `y` a fraction of the image height. The
/// configuration is immutable after creation so a caller cannot accidentally
/// bypass a safety cap by mutating a shared value.
///
/// The two user-facing strengths come from `BodyParameters`:
/// `leg` (`0...1`, slimming) and `legLength` (`1.00...1.15`, multiplier). This
/// configuration only limits how those requests are mapped to geometry.
public struct LegsWarpConfiguration: Sendable, Equatable {
    /// Hard cap for the effective leg-length multiplier.
    ///
    /// `BodyParameters` already clamps to `1.00...1.15`; this cap is repeated
    /// here so a future caller cannot exceed the frozen range through
    /// ``BodyParameters/legLength``.
    public let maximumLengthening: Double

    /// Maximum inward contour shift for one leg, normalized image x.
    public let maximumLateralDisplacement: Double

    /// Maximum upward content shift of the hip/crotch line, normalized image
    /// y. It is also the safety cap for the leg-length anchor displacement.
    public let maximumVerticalDisplacement: Double

    /// Maximum combined contribution of this pass at one mesh vertex. The
    /// engine's boundary policy applies a second, coarser clamp afterwards.
    public let maximumContribution: Double

    /// Minimum body-pose confidence. Below this value the pass is a safe no-op.
    public let minimumBodyConfidence: Float

    /// Minimum hip-to-ankle vertical length. Shorter chains are treated as a
    /// degenerate/sitting pose.
    public let minimumLegLength: Double

    /// Maximum hip-to-ankle vertical length. Longer chains usually mean a
    /// badly detected pose.
    public let maximumLegLength: Double

    /// Maximum allowed difference between the two hip y coordinates.
    public let maximumHipAsymmetry: Double

    /// Maximum allowed difference between the two ankle y coordinates.
    public let maximumAnkleAsymmetry: Double

    /// Minimum distance between the ankle and the bottom frame edge. If the
    /// feet are cropped, lengthening is skipped so no shoe can be cut.
    public let minimumAnkleMargin: Double

    /// Height above the ankle over which leg influence fades to zero. This
    /// protects ankle straps, shoes and boots.
    public let footGuardHeight: Double

    /// Fraction of the thigh over which slimming fades in below the hip.
    public let hipRampFraction: Double

    /// Fraction of the leg over which slimming fades out above the ankle.
    public let ankleRampFraction: Double

    /// Height of the waist/torso blend above the shifted hip line. The blend
    /// absorbs the upward hip displacement instead of leaving a hard seam.
    public let torsoBlendHeight: Double

    /// Peak inward shift at full slider strength as a fraction of the measured
    /// leg half-width.
    public let lateralReduction: Double

    /// Width of the lateral falloff outside the estimated contour, as a
    /// fraction of the leg half-width.
    public let lateralFeather: Double

    /// How much extra stretch is concentrated near the hip instead of being
    /// distributed uniformly. `0` is a linear scale; higher values lengthen the
    /// upper thigh more than the calf. Kept well below the fold-over limit.
    public let nonlinearity: Double

    /// Clearance around a face bounding box that must remain exactly
    /// undisplaced during lengthening.
    public let faceClearance: Double

    /// Width of the frame-edge taper and of the horizontal silhouette feather.
    public let edgeMargin: Double

    /// Strength multiplier applied when the analysis reports occlusion.
    public let occlusionScale: Double

    /// Lower bound for an estimated leg half-width.
    public let minimumHalfWidth: Double

    /// Upper bound for an estimated leg half-width.
    public let maximumHalfWidth: Double

    /// Fallback half-width as a fraction of the hip separation when no usable
    /// person mask is available.
    public let fallbackWidthFraction: Double

    /// Alpha threshold used when scanning the person mask for a leg contour.
    public let personMaskThreshold: Double

    /// Minimum y separation between the two leg centrelines. Crossing legs are
    /// treated as an unsupported pose.
    public let minimumCentreSeparation: Double

    /// Number of vertical width samples taken between hip and ankle.
    public let widthStationCount: Int

    /// Creates a configuration, clamping every value into a safe range.
    public init(
        maximumLengthening: Double = 1.15,
        maximumLateralDisplacement: Double = 0.030,
        maximumVerticalDisplacement: Double = 0.080,
        maximumContribution: Double = 0.100,
        minimumBodyConfidence: Float = 0.30,
        minimumLegLength: Double = 0.15,
        maximumLegLength: Double = 0.85,
        maximumHipAsymmetry: Double = 0.06,
        maximumAnkleAsymmetry: Double = 0.06,
        minimumAnkleMargin: Double = 0.01,
        footGuardHeight: Double = 0.035,
        hipRampFraction: Double = 0.15,
        ankleRampFraction: Double = 0.20,
        torsoBlendHeight: Double = 0.16,
        lateralReduction: Double = 0.24,
        lateralFeather: Double = 0.45,
        nonlinearity: Double = 0.35,
        faceClearance: Double = 0.015,
        edgeMargin: Double = 0.04,
        occlusionScale: Double = 0.5,
        minimumHalfWidth: Double = 0.025,
        maximumHalfWidth: Double = 0.110,
        fallbackWidthFraction: Double = 0.38,
        personMaskThreshold: Double = 0.35,
        minimumCentreSeparation: Double = 0.02,
        widthStationCount: Int = 24
    ) {
        self.maximumLengthening = LegsMath.clamp(maximumLengthening, 1, 1.15)
        self.maximumLateralDisplacement = LegsMath.clamp(
            maximumLateralDisplacement,
            0,
            0.10
        )
        self.maximumVerticalDisplacement = LegsMath.clamp(
            maximumVerticalDisplacement,
            0,
            0.15
        )
        self.maximumContribution = LegsMath.clamp(maximumContribution, 0, 0.15)
        self.minimumBodyConfidence = LegsMath.clamp(minimumBodyConfidence, 0, 1)
        self.minimumLegLength = LegsMath.clamp(minimumLegLength, 0.05, 0.40)
        self.maximumLegLength = max(
            LegsMath.clamp(maximumLegLength, 0.20, 1.0),
            self.minimumLegLength
        )
        self.maximumHipAsymmetry = LegsMath.clamp(maximumHipAsymmetry, 0, 0.25)
        self.maximumAnkleAsymmetry = LegsMath.clamp(maximumAnkleAsymmetry, 0, 0.25)
        self.minimumAnkleMargin = LegsMath.clamp(minimumAnkleMargin, 0, 0.10)
        self.footGuardHeight = LegsMath.clamp(footGuardHeight, 0, 0.08)
        self.hipRampFraction = LegsMath.clamp(hipRampFraction, 0, 0.40)
        self.ankleRampFraction = LegsMath.clamp(ankleRampFraction, 0, 0.40)
        self.torsoBlendHeight = LegsMath.clamp(torsoBlendHeight, 0.05, 0.30)
        self.lateralReduction = LegsMath.clamp(lateralReduction, 0, 0.35)
        self.lateralFeather = LegsMath.clamp(lateralFeather, 0.10, 1.50)
        self.nonlinearity = LegsMath.clamp(nonlinearity, 0, 0.90)
        self.faceClearance = LegsMath.clamp(faceClearance, 0, 0.05)
        self.edgeMargin = LegsMath.clamp(edgeMargin, 0.005, 0.15)
        self.occlusionScale = LegsMath.clamp(occlusionScale, 0, 1)
        self.minimumHalfWidth = LegsMath.clamp(minimumHalfWidth, 0.010, 0.080)
        self.maximumHalfWidth = max(
            LegsMath.clamp(maximumHalfWidth, self.minimumHalfWidth, 0.20),
            self.minimumHalfWidth
        )
        self.fallbackWidthFraction = LegsMath.clamp(fallbackWidthFraction, 0.10, 0.50)
        self.personMaskThreshold = LegsMath.clamp(personMaskThreshold, 0.05, 0.95)
        self.minimumCentreSeparation = LegsMath.clamp(
            minimumCentreSeparation,
            0.01,
            0.10
        )
        self.widthStationCount = min(max(widthStationCount, 4), 64)
    }

    /// Default configuration used by the engine.
    public static let standard = LegsWarpConfiguration()
}
