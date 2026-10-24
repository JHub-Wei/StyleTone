import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore
import StyleToneImaging

enum ImagingTestError: Error {
    case imageCreation
    case encoding
}

/// The eight saturated colors used to verify EXIF orientation.
enum TestColor: String, CaseIterable {
    case red
    case green
    case blue
    case white
    case yellow
    case cyan
    case magenta
    case black

    var rgba: (UInt8, UInt8, UInt8, UInt8) {
        switch self {
        case .red: return (255, 0, 0, 255)
        case .green: return (0, 255, 0, 255)
        case .blue: return (0, 0, 255, 255)
        case .white: return (255, 255, 255, 255)
        case .yellow: return (255, 255, 0, 255)
        case .cyan: return (0, 255, 255, 255)
        case .magenta: return (255, 0, 255, 255)
        case .black: return (0, 0, 0, 255)
        }
    }

    /// Nearest reference color, tolerating lossy JPEG/HEIC shifts.
    static func nearest(red: UInt8, green: UInt8, blue: UInt8) -> TestColor {
        var best = TestColor.black
        var bestDistance = Double.greatestFiniteMagnitude
        for color in TestColor.allCases {
            let reference = color.rgba
            let dr = Double(red) - Double(reference.0)
            let dg = Double(green) - Double(reference.1)
            let db = Double(blue) - Double(reference.2)
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = color
            }
        }
        return best
    }
}

enum TestImage {
    static var sRGB: CGColorSpace { ImageColorSpace.sRGB.cgColorSpace }
    static var displayP3: CGColorSpace { ImageColorSpace.displayP3.cgColorSpace }

    static var isHEICEncodingSupported: Bool {
        let identifiers = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return identifiers.contains("public.heic")
    }

    static func image(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        fill: (Int, Int) -> SIMD4<UInt8>
    ) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let value = fill(x, y)
                let base = (y * width + x) * 4
                bytes[base] = value.x
                bytes[base + 1] = value.y
                bytes[base + 2] = value.z
                bytes[base + 3] = value.w
            }
        }
        return try image(width: width, height: height, colorSpace: colorSpace, bytes: bytes)
    }

    static func image(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        bytes: [UInt8]
    ) throws -> CGImage {
        guard width > 0,
              height > 0,
              bytes.count == width * height * 4
        else {
            throw ImagingTestError.imageCreation
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw ImagingTestError.imageCreation
        }
        guard let cgImage = CGImage(
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
        ) else {
            throw ImagingTestError.imageCreation
        }
        return cgImage
    }

    static func solid(
        width: Int,
        height: Int,
        color: TestColor,
        colorSpace: CGColorSpace? = nil
    ) throws -> CGImage {
        let rgba = color.rgba
        return try image(
            width: width,
            height: height,
            colorSpace: colorSpace ?? sRGB
        ) { _, _ in
            SIMD4<UInt8>(rgba.0, rgba.1, rgba.2, rgba.3)
        }
    }

    static func asset(
        _ image: CGImage,
        colorSpace: ImageColorSpace = .sRGB
    ) -> ImageAsset {
        ImageAsset(cgImage: image, colorSpace: colorSpace.cgColorSpace)
    }

    static func encode(
        _ image: CGImage,
        format: String,
        orientation: CGImagePropertyOrientation = .up,
        quality: Double = 1.0,
        metadata: [CFString: Any] = [:]
    ) throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  mutableData,
                  format as CFString,
                  1,
                  nil
              )
        else {
            throw ImagingTestError.encoding
        }
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        if orientation != .up {
            properties[kCGImagePropertyOrientation] = orientation.rawValue
        }
        for (key, value) in metadata {
            properties[key] = value
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagingTestError.encoding
        }
        return mutableData as Data
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImagingTestError.encoding
        }
        return image
    }

    static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// Renders an image into a known sRGB RGBA8 buffer for pixel assertions.
    static func pixels(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            throw ImagingTestError.imageCreation
        }
        return bytes
    }

    static func rgba(
        _ pixels: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        let base = (y * width + x) * 4
        return (pixels[base], pixels[base + 1], pixels[base + 2], pixels[base + 3])
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleToneImagingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
