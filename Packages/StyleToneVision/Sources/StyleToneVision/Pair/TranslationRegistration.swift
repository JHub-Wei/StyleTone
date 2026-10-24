import Foundation
import StyleToneImaging

/// Translation-only registration result, normalized to the search plane.
struct TranslationRegistrationResult: Sendable, Equatable {
    /// Shift applied to the edited plane's x axis, as a fraction of the plane.
    let offsetX: Double
    /// Shift applied to the edited plane's y axis, as a fraction of the plane.
    let offsetY: Double
    /// Pearson correlation at the selected shift, in `-1...1`.
    let peak: Float

    var magnitude: Double {
        (offsetX * offsetX + offsetY * offsetY).squareRoot()
    }
}

/// Normalized cross-correlation translation registration.
///
/// A full affine solve is unnecessary for the pair-quality gate: editors
/// preserve orientation and scale. Translation catches the common failure
/// modes (cropped/reframed exports, re-shot pairs) cheaply and deterministically.
enum TranslationRegistration {
    static func estimate(
        original: LinearImage,
        edited: LinearImage,
        dimension: Int
    ) throws -> TranslationRegistrationResult? {
        guard let originalPlane = try GrayscalePlaneBuilder.build(
            linearImage: original,
            dimension: dimension
        ), let editedPlane = try GrayscalePlaneBuilder.build(
            linearImage: edited,
            dimension: dimension
        ) else {
            return nil
        }
        guard !originalPlane.isFlat, !editedPlane.isFlat else {
            return nil
        }

        let maximumShift = max(4, Int(Double(dimension) * 0.10))
        var bestX = 0
        var bestY = 0
        var bestScore: Float = -1
        let coarseStep = 2

        for shiftY in stride(from: -maximumShift, through: maximumShift, by: coarseStep) {
            for shiftX in stride(from: -maximumShift, through: maximumShift, by: coarseStep) {
                let score = correlation(
                    originalPlane.normalized,
                    editedPlane.normalized,
                    dimension: dimension,
                    shiftX: shiftX,
                    shiftY: shiftY
                )
                if score > bestScore {
                    bestScore = score
                    bestX = shiftX
                    bestY = shiftY
                }
            }
        }

        let refineRangeX = max(-maximumShift, bestX - coarseStep) ... min(maximumShift, bestX + coarseStep)
        let refineRangeY = max(-maximumShift, bestY - coarseStep) ... min(maximumShift, bestY + coarseStep)
        for shiftY in refineRangeY {
            for shiftX in refineRangeX {
                let score = correlation(
                    originalPlane.normalized,
                    editedPlane.normalized,
                    dimension: dimension,
                    shiftX: shiftX,
                    shiftY: shiftY
                )
                if score > bestScore {
                    bestScore = score
                    bestX = shiftX
                    bestY = shiftY
                }
            }
        }

        guard bestScore >= 0.20 else { return nil }

        // A pure gradient (or another translation-ambiguous texture) can score
        // equally well at many shifts. Prefer the zero shift unless a candidate
        // is meaningfully better: a false 10% offset is worse than "no shift".
        let zeroScore = correlation(
            originalPlane.normalized,
            editedPlane.normalized,
            dimension: dimension,
            shiftX: 0,
            shiftY: 0
        )
        if zeroScore >= 0.20, bestScore - zeroScore < 0.03 {
            bestX = 0
            bestY = 0
            bestScore = zeroScore
        }

        return TranslationRegistrationResult(
            offsetX: Double(bestX) / Double(dimension),
            offsetY: Double(bestY) / Double(dimension),
            peak: bestScore
        )
    }

    /// Computes the correlation of `original[x, y]` with `edited[x + shiftX, y + shiftY]`.
    private static func correlation(
        _ original: [Float],
        _ edited: [Float],
        dimension: Int,
        shiftX: Int,
        shiftY: Int
    ) -> Float {
        let startX = max(0, -shiftX)
        let endX = min(dimension, dimension - shiftX)
        let startY = max(0, -shiftY)
        let endY = min(dimension, dimension - shiftY)
        guard endX - startX >= dimension / 2,
              endY - startY >= dimension / 2
        else {
            return -1
        }

        var dot: Float = 0
        var originalEnergy: Float = 0
        var editedEnergy: Float = 0
        for y in startY ..< endY {
            let originalRow = y * dimension
            let editedRow = (y + shiftY) * dimension + shiftX
            for x in startX ..< endX {
                let originalValue = original[originalRow + x]
                let editedValue = edited[editedRow + x]
                dot += originalValue * editedValue
                originalEnergy += originalValue * originalValue
                editedEnergy += editedValue * editedValue
            }
        }
        guard originalEnergy > 1e-9, editedEnergy > 1e-9 else {
            return -1
        }
        return dot / (originalEnergy * editedEnergy).squareRoot()
    }
}
