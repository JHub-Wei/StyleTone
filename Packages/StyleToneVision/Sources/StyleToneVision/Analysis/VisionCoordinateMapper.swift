import CoreGraphics
import StyleToneCore

/// Converts Vision coordinates into the convention used by `StyleToneCore`.
///
/// Vision normalizes points and rectangles to `0...1` with a **bottom-left**
/// origin. `PortraitAnalysis` — and the rest of StyleTone, including the shared
/// test mocks — uses a **top-left** origin with `y` growing downwards. Every
/// coordinate that leaves this module must pass through this mapper.
public enum VisionCoordinateMapper {
    /// Converts one normalized Vision point to top-left normalized coordinates.
    public static func topLeftPoint(fromVisionNormalized point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: clamp01(Double(point.x)),
            y: clamp01(1 - Double(point.y))
        )
    }

    /// Converts a normalized Vision rectangle to a top-left normalized rect.
    public static func topLeftRect(fromVisionNormalized rect: CGRect) -> NormalizedRect {
        let originX = clamp01(Double(rect.origin.x))
        let width = clamp01(Double(rect.width))
        let height = clamp01(Double(rect.height))
        let topY = 1 - Double(rect.origin.y) - Double(rect.height)
        return NormalizedRect(
            x: originX,
            y: clamp01(topY),
            width: width,
            height: height
        )
    }

    /// Converts a landmark point that Vision normalized to a face bounding box.
    ///
    /// Vision's `VNFaceLandmarkRegion2D.normalizedPoints` are relative to the
    /// face bounding box's lower-left corner. This expands them into image
    /// space and flips the vertical axis.
    public static func topLeftPoint(
        landmark: CGPoint,
        inVisionFaceBoundingBox box: CGRect
    ) -> NormalizedPoint {
        let imageX = Double(box.origin.x) + Double(landmark.x) * Double(box.width)
        let imageBottomY = Double(box.origin.y) + Double(landmark.y) * Double(box.height)
        return NormalizedPoint(x: clamp01(imageX), y: clamp01(1 - imageBottomY))
    }

    /// Converts a top-left normalized point to pixel coordinates.
    public static func pixelPoint(
        _ point: NormalizedPoint,
        width: Int,
        height: Int
    ) -> CGPoint {
        CGPoint(
            x: point.x * Double(max(width, 1)),
            y: point.y * Double(max(height, 1))
        )
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
