import Foundation

/// Tuning for the skin retouch core.
///
/// The defaults are the values used in the quality and performance tests and
/// are intentionally conservative: the maximum smoothing strength still keeps
/// roughly 40 % of the high-frequency skin texture, and evenness may change a
/// pixel's linear luma by at most ``evennessChangeLimit``. Distances are
/// fractions of the image short edge so preview and export render at the same
/// physical scale.
public struct SkinRetouchConfiguration: Sendable, Equatable {
    /// Radius of the fine (pore) frequency band, as a fraction of the short edge.
    public var fineRadiusFraction: Double

    /// Radius of the regional (blotch / shading) frequency band.
    public var regionalRadiusFraction: Double

    /// Guided-filter regularisation in linear luma units. Larger values smooth
    /// more aggressively across low-contrast texture; edges remain because the
    /// self-guided filter follows local variance.
    public var guidedEpsilon: Double

    /// Fraction of fine texture retained at `smoothing == 1`.
    public var fineTextureRetain: Double

    /// Fraction of regional variation retained at `evenness == 1`.
    public var evennessRetain: Double

    /// Hard per-pixel limit for the evenness luma change, in linear light.
    ///
    /// This is what guarantees that evenness cannot brighten or darken the
    /// image: it only redistributes low-frequency energy and never adds a
    /// positive offset.
    public var evennessChangeLimit: Double

    /// Maximum blend of the low-frequency chroma field at `evenness == 1`.
    public var chromaEvenness: Double

    /// Detail amplitude (linear luma) above which low-frequency evenness is
    /// faded out. This protects facial features and other strong edges.
    public var edgeProtectionThreshold: Double

    /// Height of the processing band. Bands overlap by the guided-filter
    /// support so results are independent of tiling.
    public var tileHeight: Int

    /// A skin mask covering fewer than this many pixels is treated as empty.
    public var minimumMaskCoverage: Int

    /// Upper bound applied to `SkinParameters.smoothing`.
    public var maximumSmoothing: Double

    /// Upper bound applied to `SkinParameters.evenness`.
    public var maximumEvenness: Double

    public init(
        fineRadiusFraction: Double = 0.0045,
        regionalRadiusFraction: Double = 0.04,
        guidedEpsilon: Double = 0.0004,
        fineTextureRetain: Double = 0.42,
        evennessRetain: Double = 0.45,
        evennessChangeLimit: Double = 0.035,
        chromaEvenness: Double = 0.40,
        edgeProtectionThreshold: Double = 0.035,
        tileHeight: Int = 384,
        minimumMaskCoverage: Int = 16,
        maximumSmoothing: Double = 1,
        maximumEvenness: Double = 1
    ) {
        self.fineRadiusFraction = fineRadiusFraction
        self.regionalRadiusFraction = regionalRadiusFraction
        self.guidedEpsilon = guidedEpsilon
        self.fineTextureRetain = fineTextureRetain
        self.evennessRetain = evennessRetain
        self.evennessChangeLimit = evennessChangeLimit
        self.chromaEvenness = chromaEvenness
        self.edgeProtectionThreshold = edgeProtectionThreshold
        self.tileHeight = tileHeight
        self.minimumMaskCoverage = minimumMaskCoverage
        self.maximumSmoothing = maximumSmoothing
        self.maximumEvenness = maximumEvenness
    }

    /// Production defaults, also asserted by the quality tests.
    public static let standard = SkinRetouchConfiguration()
}
