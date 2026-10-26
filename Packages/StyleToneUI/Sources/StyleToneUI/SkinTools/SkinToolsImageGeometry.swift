import CoreGraphics
import Foundation
import StyleToneCore

/// Pure geometry for the blemish canvas.
///
/// The canvas shows the whole photo with aspect-fit, then multiplies by the
/// zoom and applies a pan offset. Keeping the mapping here makes tap-to-point
/// conversion testable without a simulator: the view only supplies its size and
/// the gesture location.
public struct SkinToolsImageGeometry: Equatable {
    public let containerSize: CGSize
    public let imageSize: CGSize
    public let zoomScale: Double
    public let panOffset: CGSize

    public init(
        containerSize: CGSize,
        imageSize: CGSize,
        zoomScale: Double = SkinToolsLimits.minimumZoom,
        panOffset: CGSize = .zero
    ) {
        self.containerSize = containerSize
        self.imageSize = imageSize
        self.zoomScale = zoomScale
        self.panOffset = panOffset
    }

    /// The resolved zoom, never below 1. The product only zooms in.
    public var resolvedZoom: CGFloat {
        max(CGFloat(zoomScale.isFinite ? zoomScale : SkinToolsLimits.minimumZoom), 1)
    }

    /// Scale that fits the image inside the container at 1×.
    public var fitScale: CGFloat {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0
        else {
            return 0
        }
        return min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    }

    /// Image size at 1× before zoom.
    public var fittedSize: CGSize {
        CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
    }

    /// Image size at the current zoom.
    public var displayedSize: CGSize {
        CGSize(
            width: fittedSize.width * resolvedZoom,
            height: fittedSize.height * resolvedZoom
        )
    }

    /// Top-left corner of the displayed image in container coordinates.
    public var imageOrigin: CGPoint {
        CGPoint(
            x: (containerSize.width - displayedSize.width) / 2 + panOffset.width,
            y: (containerSize.height - displayedSize.height) / 2 + panOffset.height
        )
    }

    /// Converts a tap in container coordinates to a normalized image point.
    ///
    /// Returns `nil` for taps on the letterbox or outside the photo; the UI
    /// must not repair a point the user did not actually touch.
    public func normalizedPoint(at location: CGPoint) -> NormalizedPoint? {
        let size = displayedSize
        guard size.width > 0, size.height > 0 else { return nil }

        let origin = imageOrigin
        let x = (location.x - origin.x) / size.width
        let y = (location.y - origin.y) / size.height
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }

        return NormalizedPoint(x: Double(x), y: Double(y))
    }

    /// Center of a normalized point in container coordinates.
    public func viewPoint(for point: NormalizedPoint) -> CGPoint {
        let size = displayedSize
        let origin = imageOrigin
        return CGPoint(
            x: origin.x + CGFloat(point.x) * size.width,
            y: origin.y + CGFloat(point.y) * size.height
        )
    }

    /// Diameter of the brush circle for a contract radius.
    ///
    /// `BlemishPoint.radius` is normalized to the short edge, so the on-screen
    /// circle scales with the short edge of the displayed image.
    public func markerDiameter(forRadius radius: Double) -> CGFloat {
        let size = displayedSize
        let shortEdge = min(size.width, size.height)
        guard shortEdge > 0, radius.isFinite else { return 0 }
        return max(0, CGFloat(radius) * shortEdge * 2)
    }

    /// Clamps a proposed pan so the photo cannot be dragged fully off-screen.
    public func clampedPanOffset(_ proposed: CGSize) -> CGSize {
        let limitX = max(0, (displayedSize.width - containerSize.width) / 2)
        let limitY = max(0, (displayedSize.height - containerSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }
}
