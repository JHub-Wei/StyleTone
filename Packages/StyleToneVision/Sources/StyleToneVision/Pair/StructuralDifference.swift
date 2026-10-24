import Foundation
import StyleToneImaging

/// Structural change after registration.
struct StructureComparisonResult: Sendable, Equatable {
    /// `0` = same structure, `1` = unrelated structure.
    let delta: Double
    let edgeCorrelation: Double
    let lumaCorrelation: Double
}

/// Compares edge orientation and luma correlation after applying the
/// registration shift.
///
/// Global tone/contrast edits are normalized out, so the delta reacts to
/// geometry and content changes rather than to color grading.
enum StructuralDifference {
    static func compare(
        original: LinearImage,
        edited: LinearImage,
        shiftX: Int,
        shiftY: Int,
        dimension: Int
    ) throws -> StructureComparisonResult? {
        guard let originalPlane = try GrayscalePlaneBuilder.build(
            linearImage: original,
            dimension: dimension
        ), let editedPlane = try GrayscalePlaneBuilder.build(
            linearImage: edited,
            dimension: dimension
        ) else {
            return nil
        }

        let dimensionValue = originalPlane.dimension
        if originalPlane.isFlat, editedPlane.isFlat {
            return StructureComparisonResult(delta: 0, edgeCorrelation: 0, lumaCorrelation: 1)
        }
        if originalPlane.isFlat || editedPlane.isFlat {
            return StructureComparisonResult(delta: 1, edgeCorrelation: 0, lumaCorrelation: 0)
        }

        let originalGradients = sobel(originalPlane.normalized, dimension: dimensionValue)
        let editedGradients = sobel(editedPlane.normalized, dimension: dimensionValue)
        try Task.checkCancellation()

        let startX = max(0, -shiftX)
        let endX = min(dimensionValue, dimensionValue - shiftX)
        let startY = max(0, -shiftY)
        let endY = min(dimensionValue, dimensionValue - shiftY)
        guard endX - startX >= dimensionValue / 2,
              endY - startY >= dimensionValue / 2
        else {
            return nil
        }

        let edgeThreshold: Float = 0.12
        var edgeDot = 0.0
        var edgeCount = 0
        var lumaDot = 0.0
        var originalEnergy = 0.0
        var editedEnergy = 0.0

        for y in startY ..< endY {
            let originalRow = y * dimensionValue
            let editedRow = (y + shiftY) * dimensionValue + shiftX
            for x in startX ..< endX {
                let originalIndex = originalRow + x
                let editedIndex = editedRow + x

                let originalValue = Double(originalPlane.normalized[originalIndex])
                let editedValue = Double(editedPlane.normalized[editedIndex])
                lumaDot += originalValue * editedValue
                originalEnergy += originalValue * originalValue
                editedEnergy += editedValue * editedValue

                let originalX = originalGradients.x[originalIndex]
                let originalY = originalGradients.y[originalIndex]
                let editedX = editedGradients.x[editedIndex]
                let editedY = editedGradients.y[editedIndex]
                let originalMagnitude = (originalX * originalX + originalY * originalY).squareRoot()
                let editedMagnitude = (editedX * editedX + editedY * editedY).squareRoot()
                guard originalMagnitude > edgeThreshold, editedMagnitude > edgeThreshold else {
                    continue
                }
                let dot = originalX * editedX + originalY * editedY
                edgeDot += Double(dot / (originalMagnitude * editedMagnitude))
                edgeCount += 1
            }
        }

        let edgeCorrelation = edgeCount > 0 ? edgeDot / Double(edgeCount) : 0
        let lumaCorrelation: Double
        if originalEnergy > 1e-9, editedEnergy > 1e-9 {
            lumaCorrelation = lumaDot / (originalEnergy * editedEnergy).squareRoot()
        } else {
            lumaCorrelation = 0
        }

        let combined = 0.65 * max(0, edgeCorrelation) + 0.35 * max(0, lumaCorrelation)
        return StructureComparisonResult(
            delta: min(max(1 - combined, 0), 1),
            edgeCorrelation: edgeCorrelation,
            lumaCorrelation: lumaCorrelation
        )
    }

    private static func sobel(
        _ plane: [Float],
        dimension: Int
    ) -> (x: [Float], y: [Float]) {
        var horizontal = [Float](repeating: 0, count: plane.count)
        var vertical = [Float](repeating: 0, count: plane.count)
        guard dimension >= 3 else {
            return (horizontal, vertical)
        }

        for y in 1 ..< dimension - 1 {
            let row = y * dimension
            for x in 1 ..< dimension - 1 {
                let index = row + x
                let topLeft = plane[index - dimension - 1]
                let top = plane[index - dimension]
                let topRight = plane[index - dimension + 1]
                let left = plane[index - 1]
                let right = plane[index + 1]
                let bottomLeft = plane[index + dimension - 1]
                let bottom = plane[index + dimension]
                let bottomRight = plane[index + dimension + 1]
                horizontal[index] = (topRight + 2 * right + bottomRight)
                    - (topLeft + 2 * left + bottomLeft)
                vertical[index] = (bottomLeft + 2 * bottom + bottomRight)
                    - (topLeft + 2 * top + topRight)
            }
        }
        return (horizontal, vertical)
    }
}
