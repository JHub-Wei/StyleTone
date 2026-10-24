import CoreGraphics
import Foundation

/// Immutable image exchanged between modules.
///
/// The image is expected to be oriented before it is wrapped in `ImageAsset`.
/// The `colorSpace` must describe the pixels; consumers must not silently
/// assume sRGB. `CGImage` is immutable; the unchecked Sendable conformance is
/// limited to this wrapper.
public struct ImageAsset: @unchecked Sendable {
    public let cgImage: CGImage
    public let colorSpace: CGColorSpace
    public let pixelSize: PixelSize

    public init(cgImage: CGImage, colorSpace: CGColorSpace) {
        self.cgImage = cgImage
        self.colorSpace = colorSpace
        self.pixelSize = PixelSize(width: cgImage.width, height: cgImage.height)
    }

    public var width: Int { pixelSize.width }
    public var height: Int { pixelSize.height }
}

public enum MaskBufferError: Error, Sendable, Equatable {
    case invalidDimensions(width: Int, height: Int)
    case byteCountMismatch(expected: Int, actual: Int)
}

/// Row-major 8-bit alpha mask with explicit dimensions.
public struct MaskBuffer: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytes: Data

    public init(width: Int, height: Int, bytes: Data) throws {
        guard width > 0, height > 0 else {
            throw MaskBufferError.invalidDimensions(width: width, height: height)
        }

        let (expected, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw MaskBufferError.invalidDimensions(width: width, height: height)
        }
        guard bytes.count == expected else {
            throw MaskBufferError.byteCountMismatch(expected: expected, actual: bytes.count)
        }

        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public var pixelCount: Int { width * height }

    public func value(x: Int, y: Int) -> UInt8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return bytes[y * width + x]
    }

    public func normalizedValue(x: Int, y: Int) -> Double? {
        guard let value = value(x: x, y: y) else { return nil }
        return Double(value) / 255.0
    }
}
