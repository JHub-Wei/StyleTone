import Foundation

/// Options controlling decoding, orientation handling and downsampling.
public struct ImageLoadOptions: Sendable, Equatable {
    /// Maximum length of the longer edge of the decoded image.
    ///
    /// `nil` keeps the source resolution. The aspect ratio is preserved and the
    /// image is never upscaled. Use ``preview`` for the 2048 px preview proxy
    /// required by the editing pipeline.
    public var maximumLongEdge: Int?

    /// Minimum acceptable length of the longer edge of the *source* image.
    ///
    /// The check runs against the oriented source size, before downsampling.
    /// Use `1` (the default) to disable the check.
    public var minimumLongEdge: Int

    /// Target color space of the decoded image.
    ///
    /// `nil` preserves sRGB and Display P3 sources and converts any other
    /// space to sRGB. Pass `.sRGB` to force the strict core exchange baseline.
    public var targetColorSpace: ImageColorSpace?

    public init(
        maximumLongEdge: Int? = nil,
        minimumLongEdge: Int = 1,
        targetColorSpace: ImageColorSpace? = nil
    ) {
        self.maximumLongEdge = maximumLongEdge.map { max(1, $0) }
        self.minimumLongEdge = max(1, minimumLongEdge)
        self.targetColorSpace = targetColorSpace
    }

    /// Full source resolution, orientation applied, source color space kept.
    public static let fullResolution = ImageLoadOptions()

    /// 2048 px long-edge proxy used for interactive previews.
    public static let preview = ImageLoadOptions(maximumLongEdge: 2048)
}
