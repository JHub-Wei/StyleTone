import CoreGraphics
import Foundation
import StyleToneCore

/// Converts between encoded 8-bit images and extended linear sRGB.
///
/// The pipeline is the single place where the module changes color spaces:
///
/// - Input may be sRGB or Display P3; Display P3 is converted to extended
///   linear sRGB, keeping out-of-gamut values negative or greater than one.
/// - Output is gamut-mapped into the requested working space before being
///   quantized to 8 bits, so no channel silently clips or shifts hue.
/// - Alpha is straight in ``LinearImage`` and premultiplied again on output,
///   matching the core exchange format.
///
/// The type is a stateless value; instances are cheap and `Sendable`.
public struct ColorPipeline: Sendable {
    public init() {}

    // MARK: - Transfer functions

    /// Converts one sRGB-encoded component (nominally `0...1`) to linear light.
    public static func linearValue(fromSRGBEncoded value: Float) -> Float {
        ColorScience.eotf(value)
    }

    /// Converts one linear-light component back to the sRGB transfer curve.
    public static func srgbEncodedValue(fromLinear value: Float) -> Float {
        ColorScience.oetf(value)
    }

    // MARK: - Decode to linear

    /// Converts an exchange image into extended linear sRGB.
    public func linearize(_ image: ImageAsset) throws -> LinearImage {
        let region = PixelRegion(
            x: 0,
            y: 0,
            width: image.cgImage.width,
            height: image.cgImage.height
        )
        return try linearize(image, region: region)
    }

    /// Converts a rectangular region of an exchange image into linear sRGB.
    ///
    /// Only the requested region is drawn, which keeps memory bounded for
    /// export tiles.
    public func linearize(_ image: ImageAsset, region: PixelRegion) throws -> LinearImage {
        try Task.checkCancellation()
        let imageWidth = image.cgImage.width
        let imageHeight = image.cgImage.height
        guard region.width > 0,
              region.height > 0,
              region.x >= 0,
              region.y >= 0
        else {
            throw StyleToneError.invalidImage
        }
        let maxX = region.x.addingReportingOverflow(region.width)
        let maxY = region.y.addingReportingOverflow(region.height)
        guard !maxX.overflow,
              !maxY.overflow,
              maxX.partialValue <= imageWidth,
              maxY.partialValue <= imageHeight
        else {
            throw StyleToneError.invalidImage
        }

        let source: CGImage
        if region.x == 0,
           region.y == 0,
           region.width == imageWidth,
           region.height == imageHeight {
            source = image.cgImage
        } else {
            guard let cropped = image.cgImage.cropping(
                to: CGRect(
                    x: region.x,
                    y: region.y,
                    width: region.width,
                    height: region.height
                )
            ) else {
                throw StyleToneError.invalidImage
            }
            source = cropped
        }

        let sourceColorSpace = ImageColorSpace.detect(image.colorSpace)
        let bytes = try Self.renderRGBA8(
            source,
            width: region.width,
            height: region.height,
            colorSpace: sourceColorSpace
        )

        let count = region.width * region.height
        var pixels = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0),
            count: count
        )
        let decodeLUT = ColorScience.eotfLUT
        let isDisplayP3 = sourceColorSpace == .displayP3

        for index in 0 ..< count {
            let base = index * 4
            let alpha = Float(bytes[base + 3]) / 255.0
            var red: Float = 0
            var green: Float = 0
            var blue: Float = 0

            if alpha >= 1 {
                red = decodeLUT[Int(bytes[base])]
                green = decodeLUT[Int(bytes[base + 1])]
                blue = decodeLUT[Int(bytes[base + 2])]
            } else if alpha > 0 {
                let inverseAlpha = 1 / alpha
                red = ColorScience.eotf(
                    min(Float(bytes[base]) / 255.0 * inverseAlpha, 1)
                )
                green = ColorScience.eotf(
                    min(Float(bytes[base + 1]) / 255.0 * inverseAlpha, 1)
                )
                blue = ColorScience.eotf(
                    min(Float(bytes[base + 2]) / 255.0 * inverseAlpha, 1)
                )
            }

            if isDisplayP3 {
                let converted = ColorScience.linearSRGB(
                    fromLinearDisplayP3: SIMD3<Float>(red, green, blue)
                )
                red = converted.x
                green = converted.y
                blue = converted.z
            }

            pixels[index] = SIMD4<Float>(red, green, blue, alpha)
        }

        return try LinearImage(width: region.width, height: region.height, pixels: pixels)
    }

    /// Streams the image to the caller in horizontal tiles.
    ///
    /// Use this instead of ``linearize(_:)`` when the full linear buffer would
    /// exceed the memory budget. Each tile is a standalone ``LinearImage``
    /// whose pixel `(0, 0)` corresponds to `region.x`/`region.y`.
    public func forEachTile(
        in image: ImageAsset,
        tileHeight: Int,
        _ body: (LinearImage, PixelRegion) throws -> Void
    ) throws {
        guard tileHeight > 0, image.cgImage.height > 0, image.cgImage.width > 0 else {
            throw StyleToneError.invalidImage
        }
        var y = 0
        while y < image.cgImage.height {
            try Task.checkCancellation()
            let height = min(tileHeight, image.cgImage.height - y)
            let region = PixelRegion(
                x: 0,
                y: y,
                width: image.cgImage.width,
                height: height
            )
            let tile = try linearize(image, region: region)
            try body(tile, region)
            y += height
        }
    }

    // MARK: - Encode from linear

    /// Encodes an extended linear sRGB image into an 8-bit exchange image.
    ///
    /// - Parameter colorSpace: Output working space. `.sRGB` is the default
    ///   and matches the core exchange baseline.
    public func makeImage(
        from linear: LinearImage,
        colorSpace: ImageColorSpace = .sRGB
    ) throws -> ImageAsset {
        try Task.checkCancellation()
        let targetSpace = colorSpace.cgColorSpace
        let count = linear.pixelCount
        var bytes = [UInt8](repeating: 0, count: count * 4)
        let isDisplayP3 = colorSpace == .displayP3

        bytes.withUnsafeMutableBufferPointer { buffer in
            for index in 0 ..< count {
                let pixel = linear.pixels[index]
                let alpha = min(max(pixel.w, 0), 1)
                var rgb = SIMD3<Float>(pixel.x, pixel.y, pixel.z)
                if isDisplayP3 {
                    rgb = ColorScience.linearDisplayP3(fromLinearSRGB: rgb)
                }
                rgb = ColorScience.gamutMap(rgb, in: colorSpace)
                let base = index * 4
                buffer[base] = ColorScience.premultipliedByte(rgb.x, alpha: alpha)
                buffer[base + 1] = ColorScience.premultipliedByte(rgb.y, alpha: alpha)
                buffer[base + 2] = ColorScience.premultipliedByte(rgb.z, alpha: alpha)
                buffer[base + 3] = ColorScience.alphaByte(alpha)
            }
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw StyleToneError.invalidImage
        }
        guard let cgImage = CGImage(
            width: linear.width,
            height: linear.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: linear.width * 4,
            space: targetSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw StyleToneError.invalidImage
        }
        return ImageAsset(cgImage: cgImage, colorSpace: targetSpace)
    }

    /// Converts an exchange image into another working space.
    ///
    /// When the image already carries exactly the requested color space it is
    /// returned unchanged, avoiding a lossy round-trip through 8 bits.
    public func convert(
        _ image: ImageAsset,
        to colorSpace: ImageColorSpace
    ) throws -> ImageAsset {
        if ImageColorSpace.detect(image.colorSpace) == colorSpace,
           let cgColorSpace = image.cgImage.colorSpace,
           CFEqual(cgColorSpace, colorSpace.cgColorSpace) {
            return image
        }
        let linear = try linearize(image)
        return try makeImage(from: linear, colorSpace: colorSpace)
    }

    // MARK: - Private

    private static func renderRGBA8(
        _ image: CGImage,
        width: Int,
        height: Int,
        colorSpace: ImageColorSpace
    ) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace.cgColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard drawn else {
            throw StyleToneError.invalidImage
        }
        return bytes
    }
}
