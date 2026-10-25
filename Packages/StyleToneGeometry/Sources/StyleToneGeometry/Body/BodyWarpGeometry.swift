import Foundation
import StyleToneCore

/// Small numeric helpers shared by the body pass. Kept internal so the module's
/// public surface stays limited to the pass, configuration and plan.
enum BodyWarpMath {
    @inline(__always)
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    @inline(__always)
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else {
            return value < edge0 ? 0 : 1
        }
        let t = clamp((value - edge0) / (edge1 - edge0), to: 0 ... 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always)
    static func dot(_ lhs: SIMD2<Double>, _ rhs: SIMD2<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y
    }

    @inline(__always)
    static func length(_ vector: SIMD2<Double>) -> Double {
        (vector.x * vector.x + vector.y * vector.y).squareRoot()
    }

    @inline(__always)
    static func normalized(_ vector: SIMD2<Double>) -> SIMD2<Double> {
        let magnitude = length(vector)
        guard magnitude > 1e-12 else {
            return .zero
        }
        return vector / magnitude
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

/// Converts between normalized image coordinates and an isotropic metric
/// space whose unit is the image's shorter edge.
struct BodyWarpMetricSpace {
    let width: Double
    let height: Double
    let shortSide: Double
    let xScale: Double
    let yScale: Double

    init?(imageSize: PixelSize) {
        guard imageSize.isPositive else {
            return nil
        }
        let short = Double(min(imageSize.width, imageSize.height))
        guard short > 0 else {
            return nil
        }
        width = Double(imageSize.width)
        height = Double(imageSize.height)
        shortSide = short
        xScale = width / short
        yScale = height / short
    }

    func point(_ normalized: NormalizedPoint) -> SIMD2<Double> {
        SIMD2<Double>(normalized.x * xScale, normalized.y * yScale)
    }

    func normalized(_ point: SIMD2<Double>) -> NormalizedPoint {
        NormalizedPoint(
            x: point.x / xScale,
            y: point.y / yScale
        ).clamped()
    }

    func offset(from displacement: SIMD2<Double>) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(displacement.x / xScale),
            Float(displacement.y / yScale)
        )
    }

    /// Magnitude of a normalized offset in short-side image units. Useful for
    /// diagnostics/tests that need to compare against configuration caps.
    func metricMagnitude(of offset: SIMD2<Float>) -> Double {
        BodyWarpMath.length(
            SIMD2<Double>(Double(offset.x) * xScale, Double(offset.y) * yScale)
        )
    }
}

/// Thin, allocation-free sampling facade over a ``MaskBuffer``.
///
/// Masks are sampled at full analysis resolution with nearest-neighbour lookups
/// at only the handful of points the planner needs. The full mask is never
/// copied, which keeps the pass cheap at 12 MP.
struct BodyWarpMask {
    let width: Int
    let height: Int
    private let bytes: Data
    private let baseIndex: Data.Index

    init(_ mask: MaskBuffer) {
        width = mask.width
        height = mask.height
        bytes = mask.bytes
        baseIndex = mask.bytes.startIndex
    }

    func alpha(at point: NormalizedPoint) -> Double {
        let x = min(max(Int(point.x * Double(width)), 0), width - 1)
        let y = min(max(Int(point.y * Double(height)), 0), height - 1)
        let index = baseIndex + y * width + x
        return Double(bytes[index]) / 255.0
    }

    func gate(
        at point: NormalizedPoint,
        lower: Double,
        upper: Double
    ) -> Double {
        BodyWarpMath.smoothstep(lower, upper, alpha(at: point))
    }

    func coverage(at points: [NormalizedPoint]) -> Double {
        guard !points.isEmpty else {
            return 0
        }
        var total = 0.0
        for point in points {
            total += alpha(at: point)
        }
        return total / Double(points.count)
    }

    /// Coarse connected-component probe used to detect a second silhouette.
    ///
    /// This is deliberately only a safety signal. It cannot attribute a
    /// component to a pose, so the planner defaults to skipping multi-person
    /// frames rather than guessing.
    func hasMultiplePeople(probeSize: Int, minimumAreaFraction: Double) -> Bool {
        let size = min(max(probeSize, 8), 96)
        guard width > 0, height > 0 else {
            return false
        }
        let cellCount = size * size
        var visited = [Bool](repeating: false, count: cellCount)
        let minimumArea = max(4, Int((Double(cellCount) * minimumAreaFraction).rounded(.up)))
        var largeComponents = 0

        for startY in 0 ..< size {
            for startX in 0 ..< size where !visited[startY * size + startX] {
                let startAlpha = probeAlpha(x: startX, y: startY, probeSize: size)
                guard startAlpha >= 0.5 else {
                    visited[startY * size + startX] = true
                    continue
                }

                var stack: [(x: Int, y: Int)] = [(startX, startY)]
                visited[startY * size + startX] = true
                var area = 0

                while let current = stack.popLast() {
                    area += 1
                    let neighbors = [
                        (current.x - 1, current.y),
                        (current.x + 1, current.y),
                        (current.x, current.y - 1),
                        (current.x, current.y + 1)
                    ]
                    for neighbor in neighbors {
                        guard neighbor.0 >= 0, neighbor.0 < size,
                              neighbor.1 >= 0, neighbor.1 < size
                        else {
                            continue
                        }
                        let neighborIndex = neighbor.1 * size + neighbor.0
                        guard !visited[neighborIndex] else {
                            continue
                        }
                        visited[neighborIndex] = true
                        if probeAlpha(x: neighbor.0, y: neighbor.1, probeSize: size) >= 0.5 {
                            stack.append((neighbor.0, neighbor.1))
                        }
                    }
                }

                if area >= minimumArea {
                    largeComponents += 1
                    if largeComponents >= 2 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func probeAlpha(x: Int, y: Int, probeSize: Int) -> Double {
        let normalized = NormalizedPoint(
            x: (Double(x) + 0.5) / Double(probeSize),
            y: (Double(y) + 0.5) / Double(probeSize)
        )
        return alpha(at: normalized)
    }
}
