import Foundation
import StyleToneCore
import StyleToneImaging

/// Applies one or more patch-based blemish repairs to a linear image.
struct BlemishRemovalPipeline: Sendable {
    func render(
        _ image: ImageAsset,
        points: [BlemishPoint],
        analysis: PortraitAnalysis
    ) throws -> ImageAsset {
        guard image.width > 0, image.height > 0 else {
            throw StyleToneError.invalidImage
        }
        let validPoints = points.filter(Self.isValid)
        guard !validPoints.isEmpty else { return image }

        let pipeline = ColorPipeline()
        var pixels = try pipeline.linearize(image).pixels
        let skinMask: [UInt8]?
        if let mask = analysis.skinMask,
           mask.width == image.width,
           mask.height == image.height,
           pixels.count == mask.width * mask.height
        {
            skinMask = [UInt8](mask.bytes)
        } else {
            skinMask = nil
        }

        var changed = false
        for point in validPoints {
            try Task.checkCancellation()
            if PatchBlemishInpainter.apply(
                point: point,
                width: image.width,
                height: image.height,
                pixels: &pixels,
                skinMask: skinMask
            ) {
                changed = true
            }
        }
        guard changed else { return image }

        let output = try LinearImage(
            width: image.width,
            height: image.height,
            pixels: pixels
        )
        do {
            return try pipeline.makeImage(
                from: output,
                colorSpace: ImageColorSpace.detect(image.colorSpace)
            )
        } catch let error as StyleToneError {
            throw error
        } catch {
            throw StyleToneError.retouchingFailed
        }
    }

    private static func isValid(_ point: BlemishPoint) -> Bool {
        point.point.x.isFinite
            && point.point.y.isFinite
            && point.radius.isFinite
            && point.point.x >= 0
            && point.point.x <= 1
            && point.point.y >= 0
            && point.point.y <= 1
            && point.radius > 0
    }
}

extension SkinRetoucher: BlemishRemoving {
    /// Removes one blemish. The original asset is returned when the point is
    /// outside the image or no repair could be computed.
    ///
    /// Undo is intentionally not implemented here: the engine is stateless and
    /// the UI keeps the previous ``ImageAsset`` for its undo stack.
    public func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        try await removeBlemishes(
            image,
            at: [point],
            analysis: analysis
        )
    }

    /// Removes several blemishes in one linearise/encode round trip.
    public func removeBlemishes(
        _ image: ImageAsset,
        at points: [BlemishPoint],
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        guard !points.isEmpty else { return image }
        let work = Task.detached(priority: .userInitiated) {
            try BlemishRemovalPipeline().render(
                image,
                points: points,
                analysis: analysis
            )
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }
}
