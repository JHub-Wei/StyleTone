import CoreGraphics
import Foundation
import GoldenSupport
import StyleToneCore
import TestShared

enum VisionTestError: Error {
    case imageCreationFailed
}

/// Deterministic images for Vision tests. No real photos are used.
enum VisionTestImage {
    static func solid(size: PixelSize, color: RGB8) throws -> ImageAsset {
        try MockImageAssetFactory.solid(color: color, size: size)
    }

    static func gradient(
        size: PixelSize,
        from start: RGB8 = RGB8(hex: "#101010") ?? .black,
        to end: RGB8 = RGB8(hex: "#F0E8DC") ?? .white
    ) throws -> ImageAsset {
        try MockImageAssetFactory.gradient(from: start, to: end, size: size)
    }

    static func fixture(named id: String) throws -> ImageAsset {
        try MockImageAssetFactory.fixture(named: id)
    }

    static func resized(_ image: ImageAsset, to size: PixelSize) throws -> ImageAsset {
        let colorSpace = image.colorSpace
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisionTestError.imageCreationFailed
        }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(
            image.cgImage,
            in: CGRect(x: 0, y: 0, width: size.width, height: size.height)
        )
        guard let cgImage = context.makeImage() else {
            throw VisionTestError.imageCreationFailed
        }
        return ImageAsset(cgImage: cgImage, colorSpace: colorSpace)
    }

    static func shifted(_ image: ImageAsset, dx: Int, dy: Int) throws -> ImageAsset {
        let pixels = try PixelBuffer(image: image)
        var bytes = [UInt8](repeating: 0, count: pixels.width * pixels.height * 4)
        for y in 0 ..< pixels.height {
            let targetY = y + dy
            guard targetY >= 0, targetY < pixels.height else { continue }
            for x in 0 ..< pixels.width {
                let targetX = x + dx
                guard targetX >= 0, targetX < pixels.width else { continue }
                let pixel = pixels[x, y]
                let offset = (targetY * pixels.width + targetX) * 4
                bytes[offset] = pixel.red
                bytes[offset + 1] = pixel.green
                bytes[offset + 2] = pixel.blue
                bytes[offset + 3] = pixel.alpha
            }
        }
        return try PixelBuffer(
            width: pixels.width,
            height: pixels.height,
            rgbaBytes: bytes
        ).makeImageAsset()
    }
}
