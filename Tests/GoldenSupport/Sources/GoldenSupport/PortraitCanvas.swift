import Foundation
import StyleToneCore

/// A simple opaque RGBA raster with per-pixel person/skin/structure masks.
///
/// The renderer intentionally avoids anti-aliasing: hard silhouette and line
/// edges keep the comparison metrics and the human review images easy to
/// interpret. Drawing is deterministic and uses only integer bounding boxes,
/// ellipse equations and point-to-segment distances.
struct PortraitCanvas {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]
    private(set) var person: [UInt8]
    private(set) var skin: [UInt8]
    private(set) var structure: [UInt8]

    init(width: Int, height: Int, background: RGB8) {
        self.width = width
        self.height = height
        let count = width * height
        self.pixels = [UInt8](repeating: 255, count: count * 4)
        self.person = [UInt8](repeating: 0, count: count)
        self.skin = [UInt8](repeating: 0, count: count)
        self.structure = [UInt8](repeating: 0, count: count)
        fillRect(x: 0, y: 0, width: width, height: height, color: background)
    }

    // MARK: Pixel access

    mutating func set(
        x: Int,
        y: Int,
        color: RGB8,
        marksPerson: Bool,
        marksSkin: Bool,
        marksStructure: Bool = false
    ) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = y * width + x
        let pixelOffset = offset * 4
        pixels[pixelOffset] = color.red
        pixels[pixelOffset + 1] = color.green
        pixels[pixelOffset + 2] = color.blue
        pixels[pixelOffset + 3] = 255
        if marksPerson {
            person[offset] = 255
        }
        if marksSkin {
            skin[offset] = 255
        } else if marksPerson {
            skin[offset] = 0
        }
        if marksStructure {
            structure[offset] = 255
        }
    }

    mutating func markStructure(x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        structure[y * width + x] = 255
    }

    mutating func clearSkin(x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        skin[y * width + x] = 0
    }

    func color(x: Int, y: Int) -> RGB8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (y * width + x) * 4
        return RGB8(
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2]
        )
    }

    func isPerson(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return person[y * width + x] > 0
    }

    func isSkin(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return skin[y * width + x] > 0
    }

    mutating func updateColor(x: Int, y: Int, _ color: RGB8) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = (y * width + x) * 4
        pixels[offset] = color.red
        pixels[offset + 1] = color.green
        pixels[offset + 2] = color.blue
    }

    mutating func updateColor(x: Int, y: Int, mutate: (RGB8) -> RGB8) {
        guard let current = color(x: x, y: y) else { return }
        updateColor(x: x, y: y, mutate(current))
    }

    // MARK: Shapes

    mutating func fillRect(
        x: Int,
        y: Int,
        width rectWidth: Int,
        height rectHeight: Int,
        color: RGB8,
        marksPerson: Bool = false,
        marksSkin: Bool = false
    ) {
        let startX = max(0, x)
        let startY = max(0, y)
        let endX = min(width, x + rectWidth)
        let endY = min(height, y + rectHeight)
        guard startX < endX, startY < endY else { return }
        for row in startY ..< endY {
            for column in startX ..< endX {
                set(
                    x: column,
                    y: row,
                    color: color,
                    marksPerson: marksPerson,
                    marksSkin: marksSkin
                )
            }
        }
    }

    mutating func fillEllipse(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double,
        color: RGB8,
        marksPerson: Bool = false,
        marksSkin: Bool = false
    ) {
        guard radiusX > 0, radiusY > 0 else { return }
        let minX = max(0, Int((centerX - radiusX).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + radiusX).rounded(.up)))
        let minY = max(0, Int((centerY - radiusY).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + radiusY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY ... maxY {
            let normalizedY = ((Double(y) + 0.5) - centerY) / radiusY
            let remaining = 1 - normalizedY * normalizedY
            if remaining < 0 { continue }
            let span = (remaining.squareRoot()) * radiusX
            let lower = max(minX, Int((centerX - span).rounded(.up)))
            let upper = min(maxX, Int((centerX + span).rounded(.down)))
            guard lower <= upper else { continue }
            for x in lower ... upper {
                set(
                    x: x,
                    y: y,
                    color: color,
                    marksPerson: marksPerson,
                    marksSkin: marksSkin
                )
            }
        }
    }

    mutating func fillCapsule(
        fromX startX: Double,
        fromY startY: Double,
        toX endX: Double,
        toY endY: Double,
        radius: Double,
        color: RGB8,
        marksPerson: Bool = false,
        marksSkin: Bool = false,
        marksStructure: Bool = false,
        recordStructureBand: Bool = false
    ) {
        guard radius > 0 else { return }
        let minX = max(0, Int((min(startX, endX) - radius).rounded(.down)))
        let maxX = min(width - 1, Int((max(startX, endX) + radius).rounded(.up)))
        let minY = max(0, Int((min(startY, endY) - radius).rounded(.down)))
        let maxY = min(height - 1, Int((max(startY, endY) + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        let segmentX = endX - startX
        let segmentY = endY - startY
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        for y in minY ... maxY {
            let pointY = Double(y) + 0.5
            for x in minX ... maxX {
                let pointX = Double(x) + 0.5
                let t: Double
                if lengthSquared <= 1e-12 {
                    t = 0
                } else {
                    t = min(
                        max(
                            ((pointX - startX) * segmentX + (pointY - startY) * segmentY)
                                / lengthSquared,
                            0
                        ),
                        1
                    )
                }
                let closestX = startX + segmentX * t
                let closestY = startY + segmentY * t
                let dx = pointX - closestX
                let dy = pointY - closestY
                if dx * dx + dy * dy <= radius * radius {
                    set(
                        x: x,
                        y: y,
                        color: color,
                        marksPerson: marksPerson,
                        marksSkin: marksSkin,
                        marksStructure: marksStructure
                    )
                    if recordStructureBand {
                        markStructure(x: x, y: y)
                    }
                }
            }
        }
    }

    /// Fills a simple polygon using the even-odd rule.
    mutating func fillPolygon(
        points: [SIMD2<Double>],
        color: RGB8,
        marksPerson: Bool = false,
        marksSkin: Bool = false
    ) {
        guard points.count >= 3 else { return }
        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let startY = max(0, Int(minY.rounded(.down)))
        let endY = min(height - 1, Int(maxY.rounded(.up)))
        guard startY <= endY else { return }

        for y in startY ... endY {
            let scanY = Double(y) + 0.5
            var crossings: [Double] = []
            for index in 0 ..< points.count {
                let first = points[index]
                let second = points[(index + 1) % points.count]
                guard (first.y <= scanY && second.y > scanY)
                    || (second.y <= scanY && first.y > scanY)
                else {
                    continue
                }
                let t = (scanY - first.y) / (second.y - first.y)
                crossings.append(first.x + (second.x - first.x) * t)
            }
            crossings.sort()
            var index = 0
            while index + 1 < crossings.count {
                let lower = max(0, Int(crossings[index].rounded(.up)))
                let upper = min(width - 1, Int(crossings[index + 1].rounded(.down)))
                if lower <= upper {
                    for x in lower ... upper {
                        set(
                            x: x,
                            y: y,
                            color: color,
                            marksPerson: marksPerson,
                            marksSkin: marksSkin
                        )
                    }
                }
                index += 2
            }
        }
    }

    mutating func strokeVerticalLine(
        x: Double,
        startY: Double,
        endY: Double,
        thickness: Double,
        color: RGB8,
        marksStructure: Bool
    ) {
        fillCapsule(
            fromX: x,
            fromY: startY,
            toX: x,
            toY: endY,
            radius: max(0.5, thickness * 0.5),
            color: color,
            marksStructure: marksStructure,
            recordStructureBand: marksStructure
        )
    }

    mutating func strokeHorizontalLine(
        y: Double,
        startX: Double,
        endX: Double,
        thickness: Double,
        color: RGB8,
        marksStructure: Bool
    ) {
        fillCapsule(
            fromX: startX,
            fromY: y,
            toX: endX,
            toY: y,
            radius: max(0.5, thickness * 0.5),
            color: color,
            marksStructure: marksStructure,
            recordStructureBand: marksStructure
        )
    }

    // MARK: Masks

    func personMask() throws -> MaskBuffer {
        try MaskOperations.make(width: width, height: height, values: person)
    }

    func skinMask() throws -> MaskBuffer {
        try MaskOperations.make(width: width, height: height, values: skin)
    }

    func structureMask() throws -> MaskBuffer {
        try MaskOperations.make(width: width, height: height, values: structure)
    }

    /// Final straight-alpha pixels, after lighting and texture.
    func pixelBuffer() throws -> PixelBuffer {
        try PixelBuffer(width: width, height: height, rgbaBytes: pixels)
    }

    var isStructureMaskEmpty: Bool {
        !structure.contains { $0 > 0 }
    }
}
