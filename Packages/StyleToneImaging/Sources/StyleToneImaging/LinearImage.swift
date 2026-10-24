import Foundation
import StyleToneCore

/// Integer pixel rectangle in the coordinate space of an image.
///
/// The origin is the top-left pixel; `width` and `height` are pixel counts.
public struct PixelRegion: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Size of the region.
    public var pixelSize: PixelSize {
        PixelSize(width: width, height: height)
    }
}

/// Linear-light RGBA image used for color math.
///
/// Components are **straight** (not premultiplied) alpha in extended linear
/// sRGB, `0...1` for the sRGB gamut and outside that range for wide-gamut
/// values. Use ``ColorPipeline`` to create or consume instances; the pixel
/// buffer is immutable and `Sendable`.
public struct LinearImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major RGBA pixels, length == `width * height`.
    public let pixels: [SIMD4<Float>]

    /// Creates a linear image after validating its dimensions.
    ///
    /// - Throws: `StyleToneError.invalidImage` when a dimension is not
    ///   positive or the pixel count does not match.
    public init(width: Int, height: Int, pixels: [SIMD4<Float>]) throws {
        guard width > 0, height > 0 else {
            throw StyleToneError.invalidImage
        }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, count == pixels.count else {
            throw StyleToneError.invalidImage
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Number of pixels in the image.
    public var pixelCount: Int {
        width * height
    }

    /// Returns the pixel at `(x, y)` or `nil` when out of bounds.
    public func pixel(x: Int, y: Int) -> SIMD4<Float>? {
        guard x >= 0, y >= 0, x < width, y < height else {
            return nil
        }
        return pixels[y * width + x]
    }
}
