import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore

/// An integer pixel rectangle in top-left origin coordinates.
public struct PixelRect: Sendable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width == 0 || height == 0 }
    public var area: Int { width * height }

    public func contains(x pointX: Int, y pointY: Int) -> Bool {
        pointX >= x && pointX < maxX && pointY >= y && pointY < maxY
    }

    public func clamped(width: Int, height: Int) -> PixelRect {
        let clampedX = min(max(x, 0), width)
        let clampedY = min(max(y, 0), height)
        let clampedMaxX = min(max(maxX, clampedX), width)
        let clampedMaxY = min(max(maxY, clampedY), height)
        return PixelRect(
            x: clampedX,
            y: clampedY,
            width: clampedMaxX - clampedX,
            height: clampedMaxY - clampedY
        )
    }

    public static let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)
}

/// A straight (non-premultiplied) 8-bit RGBA pixel.
public struct RGBA8: Sendable, Hashable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(color: RGB8, alpha: UInt8 = 255) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
    }

    public var color: RGB8 {
        RGB8(red: red, green: green, blue: blue)
    }

    public var isOpaque: Bool { alpha == 255 }
}

/// A mutable straight-alpha RGBA8 image buffer in row-major order.
///
/// `PixelBuffer` is the working representation for fixtures and image
/// comparison. It stores *straight* alpha; `makeImageAsset()` converts to the
/// premultiplied representation required by `ImageAsset`.
public struct PixelBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public private(set) var bytes: [UInt8]

    /// Creates an opaque buffer filled with `fill`.
    public init(width: Int, height: Int, fill: RGB8, alpha: UInt8 = 255) throws {
        let byteCount = try Self.byteCount(width: width, height: height)
        var bytes = [UInt8](repeating: alpha, count: byteCount)
        bytes.withUnsafeMutableBufferPointer { buffer in
            var index = 0
            while index < buffer.count {
                buffer[index] = fill.red
                buffer[index + 1] = fill.green
                buffer[index + 2] = fill.blue
                buffer[index + 3] = alpha
                index += 4
            }
        }
        self.init(uncheckedWidth: width, height: height, bytes: bytes)
    }

    /// Wraps existing row-major RGBA8 bytes.
    public init(width: Int, height: Int, rgbaBytes: [UInt8]) throws {
        let expected = try Self.byteCount(width: width, height: height)
        guard rgbaBytes.count == expected else {
            throw GoldenSupportError.invalidPixelBuffer(
                expectedByteCount: expected,
                actualByteCount: rgbaBytes.count
            )
        }
        self.init(uncheckedWidth: width, height: height, bytes: rgbaBytes)
    }

    private init(uncheckedWidth width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    private static func byteCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else {
            throw GoldenSupportError.invalidDimensions(width: width, height: height)
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, byteCount > 0 else {
            throw GoldenSupportError.invalidDimensions(width: width, height: height)
        }
        return byteCount
    }

    /// Decodes any `ImageAsset` into straight-alpha sRGB pixels.
    ///
    /// The conversion goes through a colour-managed sRGB bitmap context so P3
    /// or indexed inputs become deterministic sRGB values.
    public init(image: ImageAsset) throws {
        let cgImage = image.cgImage
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            throw GoldenSupportError.invalidDimensions(width: width, height: height)
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw GoldenSupportError.imageDecodingFailed
        }

        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            throw GoldenSupportError.imageDecodingFailed
        }
        let source = data.assumingMemoryBound(to: UInt8.self)
        let sourceRowBytes = context.bytesPerRow
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let sourceRow = source + y * sourceRowBytes
            let destinationRow = y * width * 4
            for x in 0..<width {
                let sourceIndex = x * 4
                let destinationIndex = destinationRow + x * 4
                let alpha = sourceRow[sourceIndex + 3]
                if alpha == 0 {
                    bytes[destinationIndex] = 0
                    bytes[destinationIndex + 1] = 0
                    bytes[destinationIndex + 2] = 0
                } else if alpha == 255 {
                    bytes[destinationIndex] = sourceRow[sourceIndex]
                    bytes[destinationIndex + 1] = sourceRow[sourceIndex + 1]
                    bytes[destinationIndex + 2] = sourceRow[sourceIndex + 2]
                } else {
                    let scale = 255.0 / Double(alpha)
                    bytes[destinationIndex] = Self.unpremultiply(sourceRow[sourceIndex], scale: scale)
                    bytes[destinationIndex + 1] = Self.unpremultiply(sourceRow[sourceIndex + 1], scale: scale)
                    bytes[destinationIndex + 2] = Self.unpremultiply(sourceRow[sourceIndex + 2], scale: scale)
                }
                bytes[destinationIndex + 3] = alpha
            }
        }
        self.init(uncheckedWidth: width, height: height, bytes: bytes)
    }

    private static func unpremultiply(_ value: UInt8, scale: Double) -> UInt8 {
        let converted = (Double(value) * scale).rounded()
        return UInt8(min(max(converted, 0), 255))
    }

    /// Decodes a PNG (or any ImageIO-decodable format) into straight-alpha sRGB.
    public init(imageData: Data) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw GoldenSupportError.imageDecodingFailed
        }
        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let resolvedColorSpace = colorSpace else {
            throw GoldenSupportError.colorSpaceUnavailable
        }
        try self.init(image: ImageAsset(cgImage: cgImage, colorSpace: resolvedColorSpace))
    }

    public var pixelSize: PixelSize { PixelSize(width: width, height: height) }
    public var pixelCount: Int { width * height }

    /// Bounds-checked access that traps on programming errors (like `Array`).
    public subscript(x: Int, y: Int) -> RGBA8 {
        get {
            precondition(
                x >= 0 && x < width && y >= 0 && y < height,
                "PixelBuffer index (\(x), \(y)) outside \(width)x\(height)"
            )
            let offset = (y * width + x) * 4
            return RGBA8(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            )
        }
        set {
            precondition(
                x >= 0 && x < width && y >= 0 && y < height,
                "PixelBuffer index (\(x), \(y)) outside \(width)x\(height)"
            )
            let offset = (y * width + x) * 4
            bytes[offset] = newValue.red
            bytes[offset + 1] = newValue.green
            bytes[offset + 2] = newValue.blue
            bytes[offset + 3] = newValue.alpha
        }
    }

    /// Safe lookup returning `nil` outside the buffer.
    public func pixel(x: Int, y: Int) -> RGBA8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (y * width + x) * 4
        return RGBA8(
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
            alpha: bytes[offset + 3]
        )
    }

    /// Safe colour lookup returning `nil` outside the buffer.
    public func colorAt(x: Int, y: Int) -> RGB8? {
        pixel(x: x, y: y)?.color
    }

    /// Number of distinct RGBA values (useful for fixture self-checks).
    public var uniqueColorCount: Int {
        var unique = Set<RGBA8>()
        unique.reserveCapacity(min(pixelCount, 1024))
        var index = 0
        while index < bytes.count {
            unique.insert(
                RGBA8(
                    red: bytes[index],
                    green: bytes[index + 1],
                    blue: bytes[index + 2],
                    alpha: bytes[index + 3]
                )
            )
            index += 4
        }
        return unique.count
    }

    /// Mean Rec. 709 luma in `0...255`.
    public var meanLuma: Double {
        guard width > 0, height > 0 else { return 0 }
        var total = 0.0
        var index = 0
        while index < bytes.count {
            total += 0.2126 * Double(bytes[index])
                + 0.7152 * Double(bytes[index + 1])
                + 0.0722 * Double(bytes[index + 2])
            index += 4
        }
        return total / Double(pixelCount)
    }

    /// Copies a sub-rectangle. The rectangle is clamped to the buffer.
    public func cropped(to rect: PixelRect) throws -> PixelBuffer {
        let clamped = rect.clamped(width: width, height: height)
        guard !clamped.isEmpty else {
            throw GoldenSupportError.invalidDimensions(width: clamped.width, height: clamped.height)
        }
        var cropped = [UInt8](repeating: 0, count: clamped.width * clamped.height * 4)
        for y in 0..<clamped.height {
            let sourceOffset = ((clamped.y + y) * width + clamped.x) * 4
            let destinationOffset = y * clamped.width * 4
            for index in 0..<(clamped.width * 4) {
                cropped[destinationOffset + index] = bytes[sourceOffset + index]
            }
        }
        return try PixelBuffer(width: clamped.width, height: clamped.height, rgbaBytes: cropped)
    }

    /// Wraps the buffer in the immutable `ImageAsset` exchange type.
    ///
    /// The buffer stores straight alpha; this method premultiplies it so the
    /// resulting `CGImage` matches the Core pixel format contract.
    public func makeImageAsset() throws -> ImageAsset {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw GoldenSupportError.colorSpaceUnavailable
        }
        var premultiplied = bytes
        premultiplied.withUnsafeMutableBufferPointer { buffer in
            var index = 0
            while index < buffer.count {
                let alpha = buffer[index + 3]
                if alpha != 255 {
                    let scale = Double(alpha) / 255.0
                    buffer[index] = UInt8((Double(buffer[index]) * scale).rounded())
                    buffer[index + 1] = UInt8((Double(buffer[index + 1]) * scale).rounded())
                    buffer[index + 2] = UInt8((Double(buffer[index + 2]) * scale).rounded())
                }
                index += 4
            }
        }

        let data = Data(premultiplied)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw GoldenSupportError.imageCreationFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw GoldenSupportError.imageCreationFailed
        }
        return ImageAsset(cgImage: cgImage, colorSpace: colorSpace)
    }

    /// Encodes the buffer as an 8-bit sRGB PNG.
    public func pngData() throws -> Data {
        let asset = try makeImageAsset()
        guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            throw GoldenSupportError.imageEncodingFailed
        }
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw GoldenSupportError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, asset.cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GoldenSupportError.imageEncodingFailed
        }
        return mutableData as Data
    }

    /// True when both buffers hold identical RGBA bytes.
    public func isIdentical(to other: PixelBuffer) -> Bool {
        width == other.width && height == other.height && bytes == other.bytes
    }
}
