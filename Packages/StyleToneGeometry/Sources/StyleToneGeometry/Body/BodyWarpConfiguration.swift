import Foundation

/// How the body pass treats a frame that appears to contain more than one
/// person.
///
/// `PortraitAnalysis` intentionally exposes only one ``BodyObservation``. The
/// person mask is not person-specific either, so the body pass cannot attribute
/// a second silhouette to its own pose. The default is therefore to skip.
public enum BodyMultiplePersonPolicy: String, Sendable, Equatable, Codable {
    /// Do not move anything when a second person is detected.
    case skip
    /// Shape the detected primary body only. The caller accepts that the shared
    /// person mask cannot isolate the two people perfectly.
    case primaryBody
}

/// Tunables for ``BodyWarpContributor``.
///
/// Distances and displacement limits are expressed in **short-side image
/// units**: one unit is the length of the image's shorter edge. This keeps the
/// effect resolution-independent and avoids interpreting pixels as body
/// measurements.
public struct BodyWarpConfiguration: Sendable, Equatable {
    /// Body confidence below which the pass is a no-op.
    public var minimumBodyConfidence: Float
    /// Confidence at which shaping reaches its full configured strength.
    public var fullStrengthConfidence: Float
    /// Minimum average person-mask alpha along a limb/torso centre line.
    public var minimumRegionMaskCoverage: Double
    /// Alpha at which a horizontal mask scan counts as foreground.
    public var minimumContourMaskAlpha: Double
    /// Lower alpha edge of the soft person-mask gate.
    public var maskGateLower: Double
    /// Upper alpha edge of the soft person-mask gate.
    public var maskGateUpper: Double
    /// Hard cap for one arm's displacement, in short-side image units.
    public var maximumArmInset: Double
    /// Hard cap for the waist displacement, in short-side image units.
    public var maximumWaistInset: Double
    /// Hard cap for the combined arm + waist displacement per vertex.
    public var maximumCombinedInset: Double
    /// Additional cap expressed as a fraction of the estimated arm radius.
    public var armInsetFractionOfRadius: Double
    /// Arm radius estimate as a fraction of the shoulder span.
    public var armRadiusToShoulderSpan: Double
    /// Lower bound for the estimated arm radius.
    public var minimumArmRadius: Double
    /// Upper bound for the estimated arm radius.
    public var maximumArmRadius: Double
    /// Influence radius of an arm as a multiple of its estimated radius.
    public var armSupportToRadius: Double
    /// Fraction of the upper arm over which influence fades in at the shoulder.
    public var shoulderGuardFraction: Double
    /// Fraction of the forearm over which influence fades out before the hand.
    public var handGuardFraction: Double
    /// Waist position along the shoulder-centre to hip-centre axis (0...1).
    public var waistCenterFraction: Double
    /// Gaussian sigma of the waist band, as a fraction of torso length.
    public var waistBandSigmaFraction: Double
    /// Waist support radius as a multiple of the measured waist half-width.
    public var waistSupportToHalfWidth: Double
    /// Minimum shoulder-centre to hip-centre distance for a usable torso.
    public var minimumTorsoLength: Double
    /// Minimum measured waist half-width.
    public var minimumWaistHalfWidth: Double
    /// Maximum waist half-width as a fraction of the shoulder span.
    public var maximumWaistToShoulderSpan: Double
    /// Side length of the coarse grid used for the multi-person probe.
    public var multiplePersonProbeSize: Int
    /// Area fraction a connected foreground blob needs to count as a person.
    public var minimumMultiplePersonAreaFraction: Double
    /// Policy for frames that appear to contain multiple people.
    public var multiplePersonPolicy: BodyMultiplePersonPolicy
    /// Extra strength reduction when ``multiplePersonPolicy`` is
    /// ``BodyMultiplePersonPolicy/primaryBody``.
    public var primaryBodyStrengthScale: Double

    public init(
        minimumBodyConfidence: Float = 0.25,
        fullStrengthConfidence: Float = 0.75,
        minimumRegionMaskCoverage: Double = 0.60,
        minimumContourMaskAlpha: Double = 0.45,
        maskGateLower: Double = 0.10,
        maskGateUpper: Double = 0.60,
        maximumArmInset: Double = 0.016,
        maximumWaistInset: Double = 0.024,
        maximumCombinedInset: Double = 0.030,
        armInsetFractionOfRadius: Double = 0.45,
        armRadiusToShoulderSpan: Double = 0.115,
        minimumArmRadius: Double = 0.014,
        maximumArmRadius: Double = 0.055,
        armSupportToRadius: Double = 2.30,
        shoulderGuardFraction: Double = 0.12,
        handGuardFraction: Double = 0.25,
        waistCenterFraction: Double = 0.58,
        waistBandSigmaFraction: Double = 0.12,
        waistSupportToHalfWidth: Double = 1.38,
        minimumTorsoLength: Double = 0.10,
        minimumWaistHalfWidth: Double = 0.030,
        maximumWaistToShoulderSpan: Double = 0.48,
        multiplePersonProbeSize: Int = 48,
        minimumMultiplePersonAreaFraction: Double = 0.04,
        multiplePersonPolicy: BodyMultiplePersonPolicy = .skip,
        primaryBodyStrengthScale: Double = 0.80
    ) {
        let minimumConfidence = BodyWarpMath.clamp(Double(minimumBodyConfidence), to: 0 ... 1)
        self.minimumBodyConfidence = Float(minimumConfidence)
        self.fullStrengthConfidence = Float(
            BodyWarpMath.clamp(Double(fullStrengthConfidence), to: minimumConfidence ... 1)
        )
        self.minimumRegionMaskCoverage = BodyWarpMath.clamp(
            minimumRegionMaskCoverage,
            to: 0 ... 1
        )
        self.minimumContourMaskAlpha = BodyWarpMath.clamp(
            minimumContourMaskAlpha,
            to: 0 ... 1
        )
        let upperGate = BodyWarpMath.clamp(maskGateUpper, to: 0 ... 1)
        self.maskGateUpper = upperGate
        self.maskGateLower = BodyWarpMath.clamp(maskGateLower, to: 0 ... upperGate)
        self.maximumArmInset = max(0, maximumArmInset)
        self.maximumWaistInset = max(0, maximumWaistInset)
        self.maximumCombinedInset = max(0, maximumCombinedInset)
        self.armInsetFractionOfRadius = max(0, armInsetFractionOfRadius)
        self.armRadiusToShoulderSpan = max(0, armRadiusToShoulderSpan)
        let lowerRadius = max(0.001, minimumArmRadius)
        self.minimumArmRadius = lowerRadius
        self.maximumArmRadius = max(lowerRadius, maximumArmRadius)
        self.armSupportToRadius = max(1, armSupportToRadius)
        self.shoulderGuardFraction = BodyWarpMath.clamp(shoulderGuardFraction, to: 0 ... 0.45)
        self.handGuardFraction = BodyWarpMath.clamp(handGuardFraction, to: 0 ... 0.45)
        self.waistCenterFraction = BodyWarpMath.clamp(waistCenterFraction, to: 0.30 ... 0.80)
        self.waistBandSigmaFraction = max(0.02, waistBandSigmaFraction)
        self.waistSupportToHalfWidth = max(1, waistSupportToHalfWidth)
        self.minimumTorsoLength = max(0.01, minimumTorsoLength)
        self.minimumWaistHalfWidth = max(0.001, minimumWaistHalfWidth)
        self.maximumWaistToShoulderSpan = max(0.05, maximumWaistToShoulderSpan)
        self.multiplePersonProbeSize = min(max(8, multiplePersonProbeSize), 96)
        self.minimumMultiplePersonAreaFraction = BodyWarpMath.clamp(
            minimumMultiplePersonAreaFraction,
            to: 0.005 ... 0.50
        )
        self.multiplePersonPolicy = multiplePersonPolicy
        self.primaryBodyStrengthScale = BodyWarpMath.clamp(
            primaryBodyStrengthScale,
            to: 0 ... 1
        )
    }

    /// Defaults tuned for a single full-body or half-body portrait.
    public static let standard = BodyWarpConfiguration()
}
