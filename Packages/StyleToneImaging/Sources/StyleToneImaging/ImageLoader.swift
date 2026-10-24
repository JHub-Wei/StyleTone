import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore

/// Decodes HEIC, JPEG and PNG images into oriented, color-managed
/// ``ImageAsset`` values.
///
/// Decoding always applies the EXIF orientation and normalizes the pixel
/// format to 8 bits per channel with premultiplied alpha. The result is safe
/// to pass across actors.
///
/// Error classification (all values are ``StyleToneError``):
///
/// | Situation | Error |
/// |---|---|
/// | Empty data, unreadable URL, zero-sized image | `.invalidImage` |
/// | Unknown or truncated payload | `.imageDecodingFailed` |
/// | Valid image in an unsupported format (GIF, TIFF, ...) | `.unsupportedFormat` |
/// | Source long edge below `minimumLongEdge` | `.imageTooSmall(minimumLongEdge:)` |
public struct ImageLoader: Sendable {
    public init() {}

    /// Decodes an image from a file URL without blocking the cooperative pool.
    ///
    /// The method checks for task cancellation before and after decoding.
    public func load(
        url: URL,
        options: ImageLoadOptions = .fullResolution
    ) async throws -> ImageAsset {
        try Task.checkCancellation()
        let image = try await Task.detached(priority: .userInitiated) {
            try self.decodeImage(contentsOf: url, options: options)
        }.value
        try Task.checkCancellation()
        return image
    }

    /// Decodes an image from memory without blocking the cooperative pool.
    public func load(
        data: Data,
        options: ImageLoadOptions = .fullResolution
    ) async throws -> ImageAsset {
        try Task.checkCancellation()
        let image = try await Task.detached(priority: .userInitiated) {
            try self.decodeImage(data, options: options)
        }.value
        try Task.checkCancellation()
        return image
    }

    /// Synchronous decode from a file URL.
    ///
    /// Prefer ``load(url:options:)`` from asynchronous code. This entry point
    /// exists for callers that already run on a dedicated decoding queue.
    public func decodeImage(
        contentsOf url: URL,
        options: ImageLoadOptions = .fullResolution
    ) throws -> ImageAsset {
        guard url.isFileURL else {
            throw StyleToneError.invalidImage
        }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            throw StyleToneError.invalidImage
        }
        return try Self.decode(source: source, options: options)
    }

    /// Synchronous decode from memory.
    public func decodeImage(
        _ data: Data,
        options: ImageLoadOptions = .fullResolution
    ) throws -> ImageAsset {
        guard !data.isEmpty else {
            throw StyleToneError.invalidImage
        }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            throw StyleToneError.imageDecodingFailed
        }
        return try Self.decode(source: source, options: options)
    }

    // MARK: - Decoding

    private static func decode(source: CGImageSource, options: ImageLoadOptions) throws -> ImageAsset {
        guard CGImageSourceGetCount(source) > 0 else {
            throw StyleToneError.imageDecodingFailed
        }
        guard let type = CGImageSourceGetType(source) else {
            throw StyleToneError.imageDecodingFailed
        }
        guard ImageFileFormat.detect(type as String) != nil else {
            throw StyleToneError.unsupportedFormat
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              pixelWidth > 0,
              pixelHeight > 0
        else {
            throw StyleToneError.imageDecodingFailed
        }

        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let swapsDimensions = orientation.swapsImageDimensions
        let orientedWidth = swapsDimensions ? pixelHeight : pixelWidth
        let orientedHeight = swapsDimensions ? pixelWidth : pixelHeight

        let sourceLongEdge = max(orientedWidth, orientedHeight)
        guard sourceLongEdge >= options.minimumLongEdge else {
            throw StyleToneError.imageTooSmall(minimumLongEdge: options.minimumLongEdge)
        }

        let requestedLongEdge = options.maximumLongEdge ?? sourceLongEdge
        let maxPixelSize = min(max(1, requestedLongEdge), sourceLongEdge)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw StyleToneError.imageDecodingFailed
        }

        let decodedColorSpace = decodedColorSpace(
            of: thumbnail,
            properties: properties
        )
        let targetColorSpace = options.targetColorSpace ?? decodedColorSpace
        let targetCGColorSpace = targetColorSpace.cgColorSpace
        let normalized = try normalize(thumbnail, to: targetCGColorSpace)
        return ImageAsset(cgImage: normalized, colorSpace: targetCGColorSpace)
    }

    private static func decodedColorSpace(
        of image: CGImage,
        properties: [CFString: Any]
    ) -> ImageColorSpace {
        if let colorSpace = image.colorSpace {
            let detected = ImageColorSpace.detect(colorSpace)
            if detected == .displayP3 {
                return .displayP3
            }
        }
        if let profileName = properties[kCGImagePropertyProfileName] as? String,
           profileName.localizedCaseInsensitiveContains("P3") {
            // Some HEIC/HEIF variants expose the profile name but hand back a
            // nil or generic `CGImage.colorSpace`.
            return .displayP3
        }
        if let colorSpace = image.colorSpace {
            return ImageColorSpace.detect(colorSpace)
        }
        return .sRGB
    }

    private static func normalize(_ image: CGImage, to targetSpace: CGColorSpace) throws -> CGImage {
        let matchesTargetSpace = image.colorSpace.map { CFEqual($0, targetSpace) } ?? false
        if matchesTargetSpace,
           image.bitsPerComponent == 8,
           image.bitsPerPixel == 32,
           image.alphaInfo == .premultipliedLast,
           image.bytesPerRow == image.width * 4 {
            return image
        }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw StyleToneError.invalidImage
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: targetSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StyleToneError.imageDecodingFailed
        }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let normalized = context.makeImage() else {
            throw StyleToneError.imageDecodingFailed
        }
        return normalized
    }
}

private extension CGImagePropertyOrientation {
    /// `true` when applying this orientation swaps the width and height.
    var swapsImageDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        case .up, .upMirrored, .down, .downMirrored:
            return false
        }
    }
}
