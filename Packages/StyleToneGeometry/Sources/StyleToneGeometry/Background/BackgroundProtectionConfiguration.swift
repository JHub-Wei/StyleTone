import Foundation

/// Tunables and safety rails for the WP-15 background protection constraint.
///
/// Every distance is a normalized image unit measured relative to the image
/// **width** unless stated otherwise; the planner converts y distances with the
/// image aspect ratio so a feather is isotropic in pixels. The configuration is
/// a value type: change a copy, never shared mutable state.
///
/// The defaults are deliberately conservative for portraits:
///
/// - the subject region (person mask, or face/body boxes as a fallback) keeps
///   its full displacement, so face/body/leg slimming is not weakened;
/// - generic background retains 60 % of its displacement to avoid a hard seam
///   at the person silhouette;
/// - a detected straight line retains only 5 % and is additionally forced to
///   move as one rigid segment, so it cannot bend;
/// - text/architecture edges retain 35 %, rectangle interiors 55 %.
public struct BackgroundProtectionConfiguration: Sendable, Equatable {
    // MARK: Detection

    /// Mask values below this 8-bit threshold are treated as "no edge".
    ///
    /// The WP-05 background mask is already dilated and blurred; the threshold
    /// only removes sensor/compression noise.
    public var minimumEdgeValue: UInt8

    /// Evidence value (`0...1`) a cell needs before it can start a line run.
    public var structureThreshold: Float

    /// Minimum length of a straight run, as a fraction of the image extent.
    ///
    /// Door frames, floor tile seams and table edges all easily exceed 15 % of
    /// the frame; short, textured edges are rejected.
    public var minimumLineSpanFraction: Float

    /// Minimum mean-evidence difference between a run and its parallel
    /// neighbours. This is the ridge test that rejects dense texture: a real
    /// line is a thin high-evidence ridge, a textured area is high everywhere.
    public var ridgeContrast: Float

    /// Minimum merged line strength (`0...1`) kept for protection.
    public var minimumLineStrength: Float

    /// Maximum number of straight lines kept per frame. Kept lines are ranked
    /// by span × strength.
    public var maximumLineCount: Int

    /// Maximum number of axis-aligned rectangles kept per frame.
    public var maximumRectangleCount: Int

    /// Minimum rectangle side, as a fraction of the image extent.
    public var minimumRectangleSpanFraction: Float

    /// Minimum rectangle area, as a fraction of the image area.
    public var minimumRectangleAreaFraction: Float

    /// Rectangles larger than this area fraction only contribute their
    /// boundary lines; their interior is not fill-protected. This prevents a
    /// full-frame border from damping the whole picture.
    public var maximumRectangleFillAreaFraction: Float

    /// Structure-analysis grid size. `0` selects `2 ×` the warp grid, clamped
    /// to ``minimumStructureGridDimension``/``maximumStructureGridDimension``.
    public var structureGridDimension: Int

    /// Lower bound for the automatic structure grid.
    public var minimumStructureGridDimension: Int

    /// Upper bound for the automatic structure grid.
    public var maximumStructureGridDimension: Int

    /// Sampling stride for the background edge mask on large images.
    ///
    /// Masks at or below 2 MP are sampled every pixel so the detection is exact
    /// for unit tests and small proxies. Larger masks use at least this stride,
    /// and the stride is raised further when ``maximumMaskSamples`` would be
    /// exceeded. The WP-05 mask is already widened by dilation/blur, so a small
    /// stride cannot lose a line.
    public var maskSamplingStride: Int

    /// Budget for pixels read from the background edge mask per frame.
    public var maximumMaskSamples: Int

    /// Sampling stride for the person mask. Person coverage is a soft area
    /// signal, so a coarser stride is sufficient and halves the mask bandwidth.
    public var subjectMaskSamplingStride: Int

    // MARK: Protection weights

    /// Fraction of displacement retained in generic background outside the
    /// subject support and outside any detected structure.
    public var backgroundRetention: Float

    /// Fraction of displacement retained on the core of a detected straight
    /// line. The line's rigid motion is also scaled by this value.
    public var lineRetention: Float

    /// Fraction of displacement retained on generic (non-line) edges such as
    /// text, window mouldings or curved architecture.
    public var edgeRetention: Float

    /// Fraction of displacement retained inside a detected rectangle
    /// (floor tiles, door panels, table tops).
    public var rectangleRetention: Float

    /// How strongly the rigid-line constraint overrides the damped field.
    /// `1` makes a line core exactly straight, `0` disables rigidity (damping
    /// still applies).
    public var lineRigidity: Float

    /// Distance from a line that is fully protected.
    public var lineCoreRadius: Float

    /// Falloff distance beyond ``lineCoreRadius``.
    public var lineFeather: Float

    /// Maximum protection weight produced by generic edge evidence.
    public var edgeProtectionStrength: Float

    /// Maximum protection weight produced by rectangle interiors.
    public var rectangleFillProtection: Float

    /// Distance inside a rectangle boundary over which the interior fill
    /// protection ramps in. This keeps the fill continuous with the boundary
    /// line protection.
    public var rectangleFillRamp: Float

    /// Weight of a structure cell's peak coverage in the edge evidence.
    public var edgeThinGain: Float

    /// Weight of a structure cell's mean coverage in the edge evidence. Higher
    /// values protect textured areas (foliage, brick) more aggressively.
    public var edgeTextureGain: Float

    /// Lower edge-evidence bound of the protection ramp.
    public var edgeProtectionLow: Float

    /// Upper edge-evidence bound of the protection ramp.
    public var edgeProtectionHigh: Float

    /// Share of a 4-neighbour's edge evidence spread onto a vertex, so a
    /// one-cell edge does not create a one-vertex damping spike.
    public var edgeSpreadWeight: Float

    // MARK: Subject support

    /// Person-mask coverage below this value is treated as background.
    public var personMaskLowerGate: Float

    /// Person-mask coverage at or above this value keeps full displacement.
    public var personMaskUpperGate: Float

    /// A person mask whose coverage is below this fraction of the frame is
    /// treated as a failed segmentation and the face/body fallback is used.
    public var subjectMaskEmptyCoverage: Float

    /// Face bounding-box expansion used by the fallback subject support, as a
    /// fraction of the face width/height. It covers the face pass envelope
    /// (1.22 × half-width) with margin.
    public var faceSupportExpansion: Float

    /// Body-joint bounding-box expansion used by the fallback subject support.
    public var bodySupportMargin: Float

    /// Feather outside a fallback box before support reaches zero.
    public var subjectSupportFeather: Float

    // MARK: Warnings / risk

    /// Displacement magnitude (normalized width) on a structure that is
    /// considered visible and therefore risky.
    public var riskDisplacementThreshold: Float

    /// Number of risky structure vertices at which risk becomes `high`.
    public var riskHighVertexCount: Int

    /// Creates a configuration, clamping every value into a safe range.
    public init(
        minimumEdgeValue: UInt8 = 24,
        structureThreshold: Float = 0.32,
        minimumLineSpanFraction: Float = 0.15,
        ridgeContrast: Float = 0.20,
        minimumLineStrength: Float = 0.18,
        maximumLineCount: Int = 32,
        maximumRectangleCount: Int = 12,
        minimumRectangleSpanFraction: Float = 0.10,
        minimumRectangleAreaFraction: Float = 0.015,
        maximumRectangleFillAreaFraction: Float = 0.35,
        structureGridDimension: Int = 0,
        minimumStructureGridDimension: Int = 48,
        maximumStructureGridDimension: Int = 128,
        maskSamplingStride: Int = 4,
        maximumMaskSamples: Int = 1_500_000,
        subjectMaskSamplingStride: Int = 8,
        backgroundRetention: Float = 0.60,
        lineRetention: Float = 0.05,
        edgeRetention: Float = 0.35,
        rectangleRetention: Float = 0.55,
        lineRigidity: Float = 1.0,
        lineCoreRadius: Float = 0.006,
        lineFeather: Float = 0.05,
        edgeProtectionStrength: Float = 0.85,
        rectangleFillProtection: Float = 0.50,
        rectangleFillRamp: Float = 0.04,
        edgeThinGain: Float = 0.90,
        edgeTextureGain: Float = 2.40,
        edgeProtectionLow: Float = 0.15,
        edgeProtectionHigh: Float = 0.65,
        edgeSpreadWeight: Float = 0.55,
        personMaskLowerGate: Float = 0.25,
        personMaskUpperGate: Float = 0.75,
        subjectMaskEmptyCoverage: Float = 0.005,
        faceSupportExpansion: Float = 0.25,
        bodySupportMargin: Float = 0.06,
        subjectSupportFeather: Float = 0.025,
        riskDisplacementThreshold: Float = 0.008,
        riskHighVertexCount: Int = 8
    ) {
        self.minimumEdgeValue = minimumEdgeValue
        self.structureThreshold = Self.clamp(structureThreshold, 0.01, 1)
        self.minimumLineSpanFraction = Self.clamp(minimumLineSpanFraction, 0.02, 0.9)
        self.ridgeContrast = Self.clamp(ridgeContrast, 0, 1)
        self.minimumLineStrength = Self.clamp(minimumLineStrength, 0, 1)
        self.maximumLineCount = min(max(maximumLineCount, 1), 256)
        self.maximumRectangleCount = min(max(maximumRectangleCount, 0), 128)
        self.minimumRectangleSpanFraction = Self.clamp(minimumRectangleSpanFraction, 0.01, 0.9)
        self.minimumRectangleAreaFraction = Self.clamp(minimumRectangleAreaFraction, 0, 0.9)
        self.maximumRectangleFillAreaFraction = Self.clamp(maximumRectangleFillAreaFraction, 0, 1)
        self.structureGridDimension = min(max(structureGridDimension, 0), 256)
        let resolvedMinimumStructure = min(max(minimumStructureGridDimension, 16), 256)
        self.minimumStructureGridDimension = resolvedMinimumStructure
        self.maximumStructureGridDimension = min(
            max(maximumStructureGridDimension, resolvedMinimumStructure),
            256
        )
        self.maskSamplingStride = min(max(maskSamplingStride, 1), 32)
        self.maximumMaskSamples = min(max(maximumMaskSamples, 10_000), 64_000_000)
        self.subjectMaskSamplingStride = min(max(subjectMaskSamplingStride, 1), 64)
        self.backgroundRetention = Self.clamp(backgroundRetention, 0, 1)
        self.lineRetention = Self.clamp(lineRetention, 0, 1)
        self.edgeRetention = Self.clamp(edgeRetention, 0, 1)
        self.rectangleRetention = Self.clamp(rectangleRetention, 0, 1)
        self.lineRigidity = Self.clamp(lineRigidity, 0, 1)
        self.lineCoreRadius = Self.clamp(lineCoreRadius, 0, 0.25)
        self.lineFeather = Self.clamp(lineFeather, 0.001, 0.25)
        self.edgeProtectionStrength = Self.clamp(edgeProtectionStrength, 0, 1)
        self.rectangleFillProtection = Self.clamp(rectangleFillProtection, 0, 1)
        self.rectangleFillRamp = Self.clamp(rectangleFillRamp, 0.001, 0.25)
        self.edgeThinGain = Self.clamp(edgeThinGain, 0, 2)
        self.edgeTextureGain = Self.clamp(edgeTextureGain, 0, 4)
        let resolvedEdgeLow = Self.clamp(edgeProtectionLow, 0, 0.99)
        self.edgeProtectionLow = resolvedEdgeLow
        self.edgeProtectionHigh = max(
            resolvedEdgeLow + 0.001,
            Self.clamp(edgeProtectionHigh, 0.01, 1)
        )
        self.edgeSpreadWeight = Self.clamp(edgeSpreadWeight, 0, 1)
        let resolvedPersonLow = Self.clamp(personMaskLowerGate, 0, 0.99)
        self.personMaskLowerGate = resolvedPersonLow
        self.personMaskUpperGate = max(
            resolvedPersonLow + 0.001,
            Self.clamp(personMaskUpperGate, 0.01, 1)
        )
        self.subjectMaskEmptyCoverage = Self.clamp(subjectMaskEmptyCoverage, 0, 0.5)
        self.faceSupportExpansion = Self.clamp(faceSupportExpansion, 0, 1)
        self.bodySupportMargin = Self.clamp(bodySupportMargin, 0, 0.5)
        self.subjectSupportFeather = Self.clamp(subjectSupportFeather, 0.001, 0.25)
        self.riskDisplacementThreshold = Self.clamp(riskDisplacementThreshold, 0.0001, 0.5)
        self.riskHighVertexCount = min(max(riskHighVertexCount, 1), 10_000)
    }

    /// Default configuration used by the engine.
    public static let standard = BackgroundProtectionConfiguration()

    private static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }
}
