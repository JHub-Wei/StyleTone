import Foundation
import StyleToneCore

/// Errors thrown by the GoldenSupport test harness.
///
/// Messages are intentionally free of user data: this module only ever sees
/// synthetic fixtures and test artifact paths, never photographs.
public enum GoldenSupportError: Error, Sendable, Equatable {
    /// A pixel buffer or image was requested with non-positive dimensions.
    case invalidDimensions(width: Int, height: Int)
    /// Raw bytes did not match `width * height * 4`.
    case invalidPixelBuffer(expectedByteCount: Int, actualByteCount: Int)
    /// The sRGB colour space could not be created on this platform.
    case colorSpaceUnavailable
    /// `CGImage` creation from a prepared pixel buffer failed.
    case imageCreationFailed
    /// Image decoding (PNG) failed.
    case imageDecodingFailed
    /// Image encoding (PNG) failed.
    case imageEncodingFailed
    /// A fixture entry was malformed or inconsistent with its pattern.
    case invalidFixture(id: String, reason: String)
    /// A fixture manifest failed validation.
    case invalidManifest(reason: String)
    /// Two images of different sizes were compared.
    case imageSizeMismatch(expected: PixelSize, actual: PixelSize)
    /// The golden image file does not exist.
    case goldenImageMissing(name: String)
    /// A golden image name was empty or attempted to escape the store directory.
    case invalidGoldenName(name: String)
    /// A performance budget or harness argument was invalid.
    case invalidConfiguration(reason: String)
    /// A filesystem operation failed while writing test artifacts.
    case fileOperationFailed(reason: String)
}

extension GoldenSupportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidDimensions(width, height):
            return "Invalid image dimensions: \(width)x\(height)"
        case let .invalidPixelBuffer(expected, actual):
            return "Pixel buffer has \(actual) bytes, expected \(expected)"
        case .colorSpaceUnavailable:
            return "sRGB colour space is unavailable on this platform"
        case .imageCreationFailed:
            return "Could not create a CGImage from the pixel buffer"
        case .imageDecodingFailed:
            return "Could not decode the image data"
        case .imageEncodingFailed:
            return "Could not encode the image as PNG"
        case let .invalidFixture(id, reason):
            return "Invalid fixture '\(id)': \(reason)"
        case let .invalidManifest(reason):
            return "Invalid fixture manifest: \(reason)"
        case let .imageSizeMismatch(expected, actual):
            return "Image size mismatch: expected \(expected.width)x\(expected.height), "
                + "actual \(actual.width)x\(actual.height)"
        case let .goldenImageMissing(name):
            return "Golden image '\(name)' is missing"
        case let .invalidGoldenName(name):
            return "Invalid golden image name '\(name)'"
        case let .invalidConfiguration(reason):
            return "Invalid configuration: \(reason)"
        case let .fileOperationFailed(reason):
            return "File operation failed: \(reason)"
        }
    }
}
