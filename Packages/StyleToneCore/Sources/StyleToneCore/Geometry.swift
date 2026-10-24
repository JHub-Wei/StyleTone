import Foundation

/// Pixel dimensions of an image.
public struct PixelSize: Sendable, Hashable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var longEdge: Int { max(width, height) }
    public var shortEdge: Int { min(width, height) }
    public var isPositive: Bool { width > 0 && height > 0 }
    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }
}

/// A point normalized to the image bounds: x and y are expected to be in 0...1.
public struct NormalizedPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var isNormalized: Bool {
        (0...1).contains(x) && (0...1).contains(y)
    }

    public func clamped() -> NormalizedPoint {
        NormalizedPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    public func distance(to other: NormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A rectangle normalized to the image bounds.
public struct NormalizedRect: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func clamped() -> NormalizedRect {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let clampedMaxX = min(max(maxX, clampedX), 1)
        let clampedMaxY = min(max(maxY, clampedY), 1)
        return NormalizedRect(
            x: clampedX,
            y: clampedY,
            width: clampedMaxX - clampedX,
            height: clampedMaxY - clampedY
        )
    }
}
