import Foundation
import StyleToneCore

/// Options used by ``ImageWriter`` when encoding an ``ImageAsset``.
public struct ImageWriteOptions: Sendable, Equatable {
    /// Container format to write.
    public var format: ExportFormat

    /// Lossy compression quality in `0...1`; ignored by lossless formats.
    public var quality: Double

    /// Working space the pixels are encoded in.
    ///
    /// The default is sRGB, matching the core export contract. Use
    /// `.displayP3` only when the caller wants a wide-gamut file.
    public var colorSpace: ImageColorSpace

    public init(
        format: ExportFormat = .heic,
        quality: Double = 0.92,
        colorSpace: ImageColorSpace = .sRGB
    ) {
        self.format = format
        self.quality = quality.isFinite ? min(max(quality, 0), 1) : 0.92
        self.colorSpace = colorSpace
    }
}
