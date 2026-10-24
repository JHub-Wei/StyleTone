import CoreGraphics
import Foundation
import StyleToneCore
import StyleToneImaging

/// The working image for analysis: a bounded-size CGImage for Vision plus a
/// linear sRGB buffer for mask models.
///
/// The proxy is never shared across actors. It is created and consumed inside
/// the analyzer's detached task, which keeps the non-`Sendable` `CGImage`
/// contained.
struct AnalysisImageProxy {
    let cgImage: CGImage
    let linearImage: LinearImage
    let proxySize: PixelSize
    let sourceSize: PixelSize
    let isDownsampled: Bool

    /// Horizontal source-to-proxy scale (source width / proxy width).
    var scaleX: Double {
        Double(sourceSize.width) / Double(max(proxySize.width, 1))
    }

    /// Vertical source-to-proxy scale (source height / proxy height).
    var scaleY: Double {
        Double(sourceSize.height) / Double(max(proxySize.height, 1))
    }

    static func make(image: ImageAsset, maximumLongEdge: Int) throws -> AnalysisImageProxy {
        let sourceSize = image.pixelSize
        guard sourceSize.isPositive else {
            throw StyleToneError.invalidImage
        }

        let limit = max(64, maximumLongEdge)
        let longEdge = max(sourceSize.width, sourceSize.height)
        if longEdge <= limit {
            let linear = try ColorPipeline().linearize(image)
            return AnalysisImageProxy(
                cgImage: image.cgImage,
                linearImage: linear,
                proxySize: sourceSize,
                sourceSize: sourceSize,
                isDownsampled: false
            )
        }

        let scale = Double(limit) / Double(longEdge)
        let targetWidth = max(1, Int((Double(sourceSize.width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceSize.height) * scale).rounded()))
        let colorSpace = ImageColorSpace.detect(image.colorSpace).cgColorSpace

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StyleToneError.imageAnalysisFailed
        }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(
            image.cgImage,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )
        guard let proxyImage = context.makeImage() else {
            throw StyleToneError.imageAnalysisFailed
        }

        let proxyAsset = ImageAsset(cgImage: proxyImage, colorSpace: colorSpace)
        let linear = try ColorPipeline().linearize(proxyAsset)
        return AnalysisImageProxy(
            cgImage: proxyImage,
            linearImage: linear,
            proxySize: PixelSize(width: targetWidth, height: targetHeight),
            sourceSize: sourceSize,
            isDownsampled: true
        )
    }
}
