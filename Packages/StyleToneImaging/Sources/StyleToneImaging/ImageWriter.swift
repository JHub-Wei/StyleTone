import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore

/// Encodes ``ImageAsset`` values as HEIC or JPEG.
///
/// Encoding always starts from a bare `CGImage`, so no source metadata (and in
/// particular no GPS location) can leak into the file: only the color profile
/// implied by `colorSpace` and the lossy quality are written. This satisfies
/// the default "strip location" behavior of the export contract; there is no
/// code path that copies EXIF/GPS from an input file.
///
/// The writer is a stateless value and can be used from any actor.
public struct ImageWriter: Sendable {
    public init() {}

    /// Returns `true` when ImageIO can encode `format` on this platform.
    public func isFormatSupported(_ format: ExportFormat) -> Bool {
        Self.supportedTypeIdentifiers().contains(format.typeIdentifier)
    }

    /// Encodes an image to memory.
    ///
    /// - Throws: `StyleToneError.exportFailed` when the format is unavailable
    ///   or ImageIO cannot finalize the data.
    public func data(
        for image: ImageAsset,
        options: ImageWriteOptions = ImageWriteOptions()
    ) throws -> Data {
        guard isFormatSupported(options.format) else {
            throw StyleToneError.exportFailed
        }
        let prepared = try Self.preparedImage(image, colorSpace: options.colorSpace)
        let opaque = try Self.compositedOverWhite(prepared)
        return try Self.encode(
            opaque,
            format: options.format,
            quality: options.quality
        )
    }

    /// Encodes an image and writes it atomically to `url`.
    ///
    /// - Throws: `StyleToneError.exportFailed` when encoding fails or the file
    ///   cannot be written.
    public func write(
        _ image: ImageAsset,
        to url: URL,
        options: ImageWriteOptions = ImageWriteOptions()
    ) throws -> ExportResult {
        let encoded = try data(for: image, options: options)
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            throw StyleToneError.exportFailed
        }
        return ExportResult(url: url, pixelSize: image.pixelSize, format: options.format)
    }

    /// Convenience overload for the core export contract.
    ///
    /// `ExportOptions.stripLocation` is always honored: the writer never
    /// carries metadata, so GPS is absent regardless of the flag.
    public func write(
        _ image: ImageAsset,
        to url: URL,
        using options: ExportOptions
    ) throws -> ExportResult {
        let writeOptions = ImageWriteOptions(
            format: options.format,
            quality: options.quality,
            colorSpace: .sRGB
        )
        return try write(image, to: url, options: writeOptions)
    }

    // MARK: - Private

    private static func supportedTypeIdentifiers() -> [String] {
        (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    }

    private static func preparedImage(
        _ image: ImageAsset,
        colorSpace: ImageColorSpace
    ) throws -> CGImage {
        let targetSpace = colorSpace.cgColorSpace
        if ImageColorSpace.detect(image.colorSpace) == colorSpace,
           let sourceSpace = image.cgImage.colorSpace,
           CFEqual(sourceSpace, targetSpace) {
            return image.cgImage
        }
        let converted = try ColorPipeline().convert(image, to: colorSpace)
        return converted.cgImage
    }

    /// HEIC and JPEG have no usable alpha channel for photos, so transparent
    /// pixels are composited over white instead of turning black.
    private static func compositedOverWhite(_ image: CGImage) throws -> CGImage {
        if image.alphaInfo == .none
            || image.alphaInfo == .noneSkipFirst
            || image.alphaInfo == .noneSkipLast {
            return image
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw StyleToneError.invalidImage
        }
        let colorSpace = image.colorSpace ?? ImageColorSpace.sRGB.cgColorSpace
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw StyleToneError.exportFailed
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let composited = context.makeImage() else {
            throw StyleToneError.exportFailed
        }
        return composited
    }

    private static func encode(
        _ image: CGImage,
        format: ExportFormat,
        quality: Double
    ) throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0) else {
            throw StyleToneError.exportFailed
        }
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            format.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw StyleToneError.exportFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw StyleToneError.exportFailed
        }
        return mutableData as Data
    }
}
