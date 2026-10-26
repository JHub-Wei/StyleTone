import Foundation
import StyleToneCore

/// Converts coarse edge-evidence coverage into straight lines and axis-aligned
/// rectangles.
///
/// The detector works on the structure grid produced by
/// ``BackgroundMaskSampler`` (twice the warp grid by default). It deliberately
/// uses only axis-aligned run lengths: door frames, floor tile seams, table
/// edges, window mouldings and text baselines are the dominant man-made
/// structures in a portrait, and the run representation is deterministic and
/// allocation-light. Curved and diagonal edges are still protected through the
/// generic edge term in ``BackgroundProtectionPlanner``.
struct BackgroundStructureDetector: Sendable {
    /// Detection tunables.
    let configuration: BackgroundProtectionConfiguration

    /// Detection result for one frame.
    struct Outcome: Sendable {
        /// Merged, capped lines.
        let lines: [BackgroundStructureLine]
        /// Closed rectangles, largest/strongest first.
        let rectangles: [BackgroundStructureRectangle]
        /// Number of lines before applying the cap.
        let detectedLineCount: Int
        /// Number of rectangles before applying the cap.
        let detectedRectangleCount: Int

        static let empty = Outcome(
            lines: [],
            rectangles: [],
            detectedLineCount: 0,
            detectedRectangleCount: 0
        )
    }

    private struct Segment: Sendable {
        let orientation: BackgroundStructureLine.Orientation
        /// Position axis: `y` for horizontal, `x` for vertical.
        let row: Int
        /// Start along the line.
        let start: Int
        /// End along the line (inclusive).
        let end: Int
        /// Mean edge evidence of the run.
        let strength: Float

        var length: Int {
            end - start + 1
        }
    }

    private struct Cluster {
        let orientation: BackgroundStructureLine.Orientation
        var minRow: Int
        var maxRow: Int
        var start: Int
        var end: Int
        var maxStrength: Float
        var weightedRowSum: Float
        var weightSum: Float

        var length: Int {
            end - start + 1
        }
    }

    /// Runs line and rectangle detection.
    ///
    /// - Parameters:
    ///   - maximums: Peak coverage per structure cell, row-major.
    ///   - means: Mean coverage per structure cell, row-major.
    ///   - dimension: Structure grid side length.
    /// - Returns: Detected structures and pre-cap counts.
    func detect(
        maximums: [Float],
        means: [Float],
        dimension: Int
    ) -> Outcome {
        let size = max(2, dimension)
        guard maximums.count == size * size, means.count == size * size else {
            return .empty
        }

        var evidence = [Float](repeating: 0, count: size * size)
        var hotCellCount = 0
        for index in 0 ..< evidence.count {
            let thin = min(1, max(0, maximums[index]) * configuration.edgeThinGain)
            let texture = min(1, max(0, means[index]) * configuration.edgeTextureGain)
            let value = max(thin, texture)
            evidence[index] = value
            if value >= configuration.structureThreshold {
                hotCellCount += 1
            }
        }
        guard hotCellCount > 0 else {
            return .empty
        }

        let minimumRun = max(
            3,
            Int(
                (Double(configuration.minimumLineSpanFraction) *
                    Double(size - 1)).rounded(.up)
            )
        )
        let horizontalSegments = rawSegments(
            evidence: evidence,
            size: size,
            orientation: .horizontal,
            minimumRun: minimumRun
        )
        let verticalSegments = rawSegments(
            evidence: evidence,
            size: size,
            orientation: .vertical,
            minimumRun: minimumRun
        )

        let horizontalLines = merge(horizontalSegments, size: size)
        let verticalLines = merge(verticalSegments, size: size)
        let allLines = horizontalLines + verticalLines
        let lineLimit = configuration.maximumLineCount
        var keptLines = allLines.sorted { lineScore($0) > lineScore($1) }
        if keptLines.count > lineLimit {
            keptLines = Array(keptLines.prefix(lineLimit))
        }
        keptLines.sort { lhs, rhs in
            if lhs.orientation != rhs.orientation {
                return lhs.orientation.rawValue < rhs.orientation.rawValue
            }
            if lhs.position != rhs.position {
                return lhs.position < rhs.position
            }
            return lhs.start < rhs.start
        }

        let rectangleResult = detectRectangles(lines: keptLines, size: size)
        return Outcome(
            lines: keptLines,
            rectangles: rectangleResult.rectangles,
            detectedLineCount: allLines.count,
            detectedRectangleCount: rectangleResult.detectedCount
        )
    }

    // MARK: - Runs

    private func rawSegments(
        evidence: [Float],
        size: Int,
        orientation: BackgroundStructureLine.Orientation,
        minimumRun: Int
    ) -> [Segment] {
        var segments: [Segment] = []
        let threshold = configuration.structureThreshold

        for outer in 0 ..< size {
            var runStart: Int?
            for inner in 0 ..< size {
                let index = orientation == .horizontal
                    ? outer * size + inner
                    : inner * size + outer
                if evidence[index] >= threshold {
                    if runStart == nil {
                        runStart = inner
                    }
                } else if let start = runStart {
                    append(
                        start: start,
                        end: inner - 1,
                        outer: outer,
                        orientation: orientation,
                        size: size,
                        minimumRun: minimumRun,
                        evidence: evidence,
                        to: &segments
                    )
                    runStart = nil
                }
            }
            if let start = runStart {
                append(
                    start: start,
                    end: size - 1,
                    outer: outer,
                    orientation: orientation,
                    size: size,
                    minimumRun: minimumRun,
                    evidence: evidence,
                    to: &segments
                )
            }
        }
        return segments
    }

    private func append(
        start: Int,
        end: Int,
        outer: Int,
        orientation: BackgroundStructureLine.Orientation,
        size: Int,
        minimumRun: Int,
        evidence: [Float],
        to segments: inout [Segment]
    ) {
        let length = end - start + 1
        guard length >= minimumRun else { return }

        var sum: Float = 0
        switch orientation {
        case .horizontal:
            let row = outer * size
            for x in start ... end {
                sum += evidence[row + x]
            }
        case .vertical:
            for y in start ... end {
                sum += evidence[y * size + outer]
            }
        }
        let meanEvidence = sum / Float(length)

        var neighbourSum: Float = 0
        var neighbourCount = 0
        switch orientation {
        case .horizontal:
            for neighbourRow in [outer - 1, outer + 1] where neighbourRow >= 0 && neighbourRow < size {
                let row = neighbourRow * size
                for x in start ... end {
                    neighbourSum += evidence[row + x]
                }
                neighbourCount += length
            }
        case .vertical:
            for neighbourColumn in [outer - 1, outer + 1] where neighbourColumn >= 0 && neighbourColumn < size {
                for y in start ... end {
                    neighbourSum += evidence[y * size + neighbourColumn]
                }
                neighbourCount += length
            }
        }
        let neighbourMean = neighbourCount > 0 ? neighbourSum / Float(neighbourCount) : 0
        let contrast = meanEvidence - neighbourMean

        // A thin ridge on a clean background is accepted even when the
        // absolute contrast is small; a dense texture is rejected because its
        // neighbours are equally hot.
        guard contrast >= configuration.ridgeContrast || neighbourMean <= 0.20 else {
            return
        }
        let contrastBoost = min(1, max(0, contrast) / 0.5)
        let strength = min(1, max(0, meanEvidence * (0.55 + 0.45 * contrastBoost)))
        guard strength >= configuration.minimumLineStrength else { return }

        segments.append(
            Segment(
                orientation: orientation,
                row: outer,
                start: start,
                end: end,
                strength: strength
            )
        )
    }

    // MARK: - Merging

    private func merge(_ segments: [Segment], size: Int) -> [BackgroundStructureLine] {
        guard !segments.isEmpty, size >= 2 else { return [] }
        let sorted = segments.sorted { lhs, rhs in
            if lhs.row != rhs.row {
                return lhs.row < rhs.row
            }
            return lhs.start < rhs.start
        }

        var clusters: [Cluster] = []
        for segment in sorted {
            var bestIndex: Int?
            var bestOverlap: Float = 0
            for (index, cluster) in clusters.enumerated() {
                guard cluster.orientation == segment.orientation else { continue }
                guard segment.row - cluster.maxRow <= 1 else { continue }
                let overlap = min(segment.end, cluster.end) -
                    max(segment.start, cluster.start) + 1
                guard overlap > 0 else { continue }
                let shorter = max(1, min(segment.length, cluster.length))
                let fraction = Float(overlap) / Float(shorter)
                guard fraction >= 0.60 else { continue }
                if fraction > bestOverlap {
                    bestOverlap = fraction
                    bestIndex = index
                }
            }

            if let bestIndex {
                var cluster = clusters[bestIndex]
                cluster.maxRow = max(cluster.maxRow, segment.row)
                cluster.minRow = min(cluster.minRow, segment.row)
                cluster.start = min(cluster.start, segment.start)
                cluster.end = max(cluster.end, segment.end)
                cluster.maxStrength = max(cluster.maxStrength, segment.strength)
                let weight = segment.strength * Float(segment.length)
                cluster.weightedRowSum += Float(segment.row) * weight
                cluster.weightSum += weight
                clusters[bestIndex] = cluster
            } else {
                let weight = segment.strength * Float(segment.length)
                clusters.append(
                    Cluster(
                        orientation: segment.orientation,
                        minRow: segment.row,
                        maxRow: segment.row,
                        start: segment.start,
                        end: segment.end,
                        maxStrength: segment.strength,
                        weightedRowSum: Float(segment.row) * weight,
                        weightSum: weight
                    )
                )
            }
        }

        let denominator = Float(size - 1)
        var lines: [BackgroundStructureLine] = []
        lines.reserveCapacity(clusters.count)
        for cluster in clusters {
            let spanFraction = Float(cluster.length) / Float(size)
            guard spanFraction >= configuration.minimumLineSpanFraction else { continue }
            guard cluster.maxStrength >= configuration.minimumLineStrength else { continue }
            let row = cluster.weightSum > 0
                ? cluster.weightedRowSum / cluster.weightSum
                : Float(cluster.minRow)
            lines.append(
                BackgroundStructureLine(
                    orientation: cluster.orientation,
                    position: min(max(row / denominator, 0), 1),
                    start: min(max(Float(cluster.start) / denominator, 0), 1),
                    end: min(max(Float(cluster.end) / denominator, 0), 1),
                    strength: cluster.maxStrength
                )
            )
        }
        return lines
    }

    private func lineScore(_ line: BackgroundStructureLine) -> Float {
        line.span * line.strength
    }

    // MARK: - Rectangles

    private func detectRectangles(
        lines: [BackgroundStructureLine],
        size: Int
    ) -> (rectangles: [BackgroundStructureRectangle], detectedCount: Int) {
        guard configuration.maximumRectangleCount > 0 else {
            return ([], 0)
        }
        let horizontals = lines
            .filter { $0.orientation == .horizontal }
            .sorted { $0.position < $1.position }
        let verticals = lines
            .filter { $0.orientation == .vertical }
            .sorted { $0.position < $1.position }
        guard horizontals.count >= 2, verticals.count >= 2 else {
            return ([], 0)
        }

        let tolerance = max(0.012, 2 / Float(size - 1))
        let minimumSpan = configuration.minimumRectangleSpanFraction
        let minimumArea = configuration.minimumRectangleAreaFraction
        var candidates: [(rect: NormalizedRect, strength: Float, score: Float)] = []

        for topIndex in 0 ..< (horizontals.count - 1) {
            let topLine = horizontals[topIndex]
            let bottomLine = horizontals[topIndex + 1]
            let height = bottomLine.position - topLine.position
            guard height >= minimumSpan else { continue }

            for leftIndex in 0 ..< (verticals.count - 1) {
                let leftLine = verticals[leftIndex]
                let rightLine = verticals[leftIndex + 1]
                let width = rightLine.position - leftLine.position
                guard width >= minimumSpan else { continue }
                let area = width * height
                guard area >= minimumArea else { continue }

                guard coversHorizontally(topLine, left: leftLine.position, right: rightLine.position, tolerance: tolerance),
                      coversHorizontally(bottomLine, left: leftLine.position, right: rightLine.position, tolerance: tolerance),
                      coversVertically(leftLine, top: topLine.position, bottom: bottomLine.position, tolerance: tolerance),
                      coversVertically(rightLine, top: topLine.position, bottom: bottomLine.position, tolerance: tolerance)
                else {
                    continue
                }

                let strength = min(
                    min(topLine.strength, bottomLine.strength),
                    min(leftLine.strength, rightLine.strength)
                )
                guard strength >= configuration.minimumLineStrength else { continue }
                let rect = NormalizedRect(
                    x: Double(leftLine.position),
                    y: Double(topLine.position),
                    width: Double(width),
                    height: Double(height)
                )
                candidates.append(
                    (rect: rect, strength: strength, score: area * strength)
                )
            }
        }

        guard !candidates.isEmpty else { return ([], 0) }
        let detectedCount = candidates.count
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.rect.y != rhs.rect.y {
                return lhs.rect.y < rhs.rect.y
            }
            return lhs.rect.x < rhs.rect.x
        }

        var accepted: [BackgroundStructureRectangle] = []
        var acceptedRects: [NormalizedRect] = []
        for candidate in candidates {
            if acceptedRects.contains(where: { intersectionOverUnion($0, candidate.rect) > 0.92 }) {
                continue
            }
            accepted.append(
                BackgroundStructureRectangle(
                    rect: candidate.rect,
                    strength: candidate.strength
                )
            )
            acceptedRects.append(candidate.rect)
            if accepted.count >= configuration.maximumRectangleCount {
                break
            }
        }
        return (accepted, detectedCount)
    }

    private func coversHorizontally(
        _ line: BackgroundStructureLine,
        left: Float,
        right: Float,
        tolerance: Float
    ) -> Bool {
        line.start <= left + tolerance && line.end >= right - tolerance
    }

    private func coversVertically(
        _ line: BackgroundStructureLine,
        top: Float,
        bottom: Float,
        tolerance: Float
    ) -> Bool {
        line.start <= top + tolerance && line.end >= bottom - tolerance
    }

    private func intersectionOverUnion(
        _ lhs: NormalizedRect,
        _ rhs: NormalizedRect
    ) -> Double {
        let minX = max(lhs.minX, rhs.minX)
        let minY = max(lhs.minY, rhs.minY)
        let maxX = min(lhs.maxX, rhs.maxX)
        let maxY = min(lhs.maxY, rhs.maxY)
        guard maxX > minX, maxY > minY else { return 0 }
        let intersection = (maxX - minX) * (maxY - minY)
        let union = lhs.width * lhs.height + rhs.width * rhs.height - intersection
        guard union > 0 else { return 0 }
        return intersection / union
    }
}
