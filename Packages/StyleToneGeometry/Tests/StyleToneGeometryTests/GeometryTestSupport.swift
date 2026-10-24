import CoreGraphics
import Foundation
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import XCTest
@testable import StyleToneGeometry

enum GeometryTestSupport {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Builds an opaque (or straight-alpha) RGBA image with a custom painter.
    static func makeImage(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = sRGB,
        pixel: (Int, Int) -> RGBA8
    ) throws -> ImageAsset {
        var premultiplied = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let source = pixel(x, y)
                let offset = (y * width + x) * 4
                let alpha = source.alpha
                if alpha == 0 {
                    premultiplied[offset] = 0
                    premultiplied[offset + 1] = 0
                    premultiplied[offset + 2] = 0
                } else if alpha == 255 {
                    premultiplied[offset] = source.red
                    premultiplied[offset + 1] = source.green
                    premultiplied[offset + 2] = source.blue
                } else {
                    let scale = Double(alpha) / 255.0
                    premultiplied[offset] = UInt8((Double(source.red) * scale).rounded())
                    premultiplied[offset + 1] = UInt8((Double(source.green) * scale).rounded())
                    premultiplied[offset + 2] = UInt8((Double(source.blue) * scale).rounded())
                }
                premultiplied[offset + 3] = alpha
            }
        }
        guard let provider = CGDataProvider(data: Data(premultiplied) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            throw GoldenSupportError.imageCreationFailed
        }
        return ImageAsset(cgImage: cgImage, colorSpace: colorSpace)
    }

    /// A horizontal gradient with a distinct coloured border, useful for
    /// detecting black gaps and shifts.
    static func gradientWithBorder(
        width: Int,
        height: Int,
        border: Int = 2
    ) throws -> ImageAsset {
        try makeImage(width: width, height: height) { x, y in
            if x < border || y < border || x >= width - border || y >= height - border {
                return RGBA8(red: 240, green: 32, blue: 24)
            }
            let value = UInt8((Double(x) / Double(max(width - 1, 1)) * 255).rounded())
            return RGBA8(red: value, green: UInt8(255 - value), blue: 128)
        }
    }

    /// A regular checkerboard for translation/shift checks.
    static func checkerboard(width: Int, height: Int, cell: Int = 4) throws -> ImageAsset {
        try makeImage(width: width, height: height) { x, y in
            let isLight = ((x / cell) + (y / cell)) % 2 == 0
            return isLight
                ? RGBA8(red: 230, green: 230, blue: 230)
                : RGBA8(red: 30, green: 30, blue: 30)
        }
    }

    static func constantField(
        width: Int = 32,
        height: Int = 32,
        offset: SIMD2<Float>
    ) throws -> WarpField {
        var field = try WarpField(width: width, height: height)
        for index in field.offsets.indices {
            field.offsets[index] = offset
        }
        return field
    }

    /// A field with a constant offset, feathered to zero on the border by the
    /// standard policy.
    static func featheredField(
        width: Int = 32,
        height: Int = 32,
        offset: SIMD2<Float>,
        policy: GeometryBoundaryPolicy = .standard
    ) throws -> WarpField {
        var field = try constantField(width: width, height: height, offset: offset)
        try policy.apply(to: &field)
        return field
    }

    static func pixels(of image: ImageAsset) throws -> PixelBuffer {
        try PixelBuffer(image: image)
    }

    /// Asserts that a frame has no transparent or pure-black border pixels.
    /// The test fixture must not contain black on its border.
    static func assertNoBlackBorder(
        _ image: ImageAsset,
        border: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let buffer = try PixelBuffer(image: image)
        for y in 0 ..< buffer.height {
            for x in 0 ..< buffer.width {
                let onBorder = x < border || y < border
                    || x >= buffer.width - border || y >= buffer.height - border
                guard onBorder else { continue }
                let pixel = buffer[x, y]
                XCTAssertEqual(pixel.alpha, 255, "alpha at (\(x),\(y))", file: file, line: line)
                XCTAssertFalse(
                    pixel.red < 8 && pixel.green < 8 && pixel.blue < 8,
                    "black border pixel at (\(x),\(y))",
                    file: file,
                    line: line
                )
            }
        }
    }
}
