import CoreGraphics
import Foundation
import StyleToneCore

// MARK: - Preview context

/// A downscaled image paired with an analysis of exactly the same pixel size.
///
/// Sending a full-resolution mask set with a proxy image would make engines
/// read the wrong pixels, so the preview preparer resamples both.
public struct EditorPreviewContext: Sendable {
    public let image: ImageAsset
    public let analysis: PortraitAnalysis

    public init(image: ImageAsset, analysis: PortraitAnalysis) {
        self.image = image
        self.analysis = analysis
    }
}

// MARK: - Protocols

/// Stateless preview scaler. Implementations must preserve the colour space
/// and normalized landmark coordinates, and must resample masks to the new
/// pixel size.
public protocol EditorPreviewScaling: Sendable {
    func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) throws -> EditorPreviewContext
}

/// Async preview preparation used by the render pipeline.
///
/// Production uses `EditorPreviewPreparer`, which caches one proxy per source
/// image and quality tier. Tests can substitute a synchronous stub.
public protocol EditorPreviewPreparing: Sendable {
    func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) async throws -> EditorPreviewContext
}

// MARK: - Cached actor

/// Caches the most recent proxy so dragging a slider does not re-downscale the
/// same 12 MP source on every tick.
public actor EditorPreviewPreparer: EditorPreviewPreparing {
    private struct CachedPreview {
        let imageIdentifier: ObjectIdentifier
        let imageSize: PixelSize
        let analysisSize: PixelSize
        let maximumLongEdge: Int
        let context: EditorPreviewContext
    }

    private let scaler: any EditorPreviewScaling
    private var cached: CachedPreview?
    /// Number of real scaler invocations, exposed for performance tests.
    public private(set) var preparationCount = 0

    public init(scaler: any EditorPreviewScaling = CoreGraphicsPreviewScaler()) {
        self.scaler = scaler
    }

    public func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) async throws -> EditorPreviewContext {
        let identifier = ObjectIdentifier(image.cgImage)
        if let cached,
           cached.imageIdentifier == identifier,
           cached.imageSize == image.pixelSize,
           cached.analysisSize == analysis.imageSize,
           cached.maximumLongEdge == maximumLongEdge {
            return cached.context
        }

        try Task.checkCancellation()
        let context = try scaler.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: maximumLongEdge
        )
        try Task.checkCancellation()
        preparationCount += 1
        cached = CachedPreview(
            imageIdentifier: identifier,
            imageSize: image.pixelSize,
            analysisSize: analysis.imageSize,
            maximumLongEdge: maximumLongEdge,
            context: context
        )
        return context
    }

    public func clearCache() {
        cached = nil
    }
}

// MARK: - CoreGraphics implementation

/// Draws the source image into a smaller bitmap and nearest-neighbour samples
/// the masks. This is infrastructure, not a retouching algorithm: no pixels are
/// modified beyond resampling.
public struct CoreGraphicsPreviewScaler: EditorPreviewScaling {
    public init() {}

    public func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) throws -> EditorPreviewContext {
        guard image.pixelSize.isPositive else {
            throw StyleToneError.invalidImage
        }

        let target = Self.targetSize(for: image.pixelSize, maximumLongEdge: maximumLongEdge)
        let scaledImage = try Self.scale(image, to: target)
        let scaledAnalysis = try Self.scale(analysis, to: target)
        return EditorPreviewContext(image: scaledImage, analysis: scaledAnalysis)
    }

    public static func targetSize(for size: PixelSize, maximumLongEdge: Int) -> PixelSize {
        let longEdge = max(size.width, size.height)
        guard maximumLongEdge > 0, maximumLongEdge < longEdge, size.isPositive else {
            return size
        }

        let ratio = Double(maximumLongEdge) / Double(longEdge)
        let width = max(1, Int((Double(size.width) * ratio).rounded()))
        let height = max(1, Int((Double(size.height) * ratio).rounded()))
        return PixelSize(width: width, height: height)
    }

    private static func scale(_ image: ImageAsset, to size: PixelSize) throws -> ImageAsset {
        if image.pixelSize == size {
            return image
        }

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StyleToneError.invalidImage
        }

        context.interpolationQuality = .medium
        context.draw(
            image.cgImage,
            in: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height))
        )
        guard let cgImage = context.makeImage() else {
            throw StyleToneError.invalidImage
        }
        return ImageAsset(cgImage: cgImage, colorSpace: image.colorSpace)
    }

    private static func scale(_ analysis: PortraitAnalysis, to size: PixelSize) throws -> PortraitAnalysis {
        let needsResize = analysis.imageSize != size
            || analysis.personMask.map { $0.width != size.width || $0.height != size.height } ?? false
            || analysis.skinMask.map { $0.width != size.width || $0.height != size.height } ?? false
            || analysis.backgroundEdgeMask.map { $0.width != size.width || $0.height != size.height } ?? false

        guard needsResize else { return analysis }

        return PortraitAnalysis(
            imageSize: size,
            faces: analysis.faces,
            body: analysis.body,
            personMask: try scale(analysis.personMask, to: size),
            skinMask: try scale(analysis.skinMask, to: size),
            backgroundEdgeMask: try scale(analysis.backgroundEdgeMask, to: size),
            warnings: analysis.warnings
        )
    }

    private static func scale(_ mask: MaskBuffer?, to size: PixelSize) throws -> MaskBuffer? {
        guard let mask else { return nil }
        if mask.width == size.width && mask.height == size.height {
            return mask
        }
        guard mask.width > 0, mask.height > 0, size.isPositive else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            let sourceY = min(mask.height - 1, y * mask.height / size.height)
            for x in 0..<size.width {
                let sourceX = min(mask.width - 1, x * mask.width / size.width)
                bytes[y * size.width + x] = mask.bytes[sourceY * mask.width + sourceX]
            }
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }
}
