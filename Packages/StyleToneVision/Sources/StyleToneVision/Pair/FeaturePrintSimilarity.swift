import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Semantic similarity from `VNGenerateImageFeaturePrintRequest`.
///
/// Feature-print distance is 0 for identical images and grows as content
/// diverges. The mapping below compresses the distance into `0...1`; it is a
/// ranking signal, not a probability.
enum FeaturePrintSimilarity {
    static func similarity(between lhs: CGImage, and rhs: CGImage) throws -> Float {
        let lhsPrint = try featurePrint(of: lhs)
        let rhsPrint = try featurePrint(of: rhs)
        var distance: Float = 0
        try lhsPrint.computeDistance(&distance, to: rhsPrint)
        guard distance.isFinite, distance >= 0 else {
            throw PairQualityAnalysisError.unavailable
        }
        let similarity = exp(-1.2 * Double(distance))
        return Float(min(max(similarity, 0), 1))
    }

    private static func featurePrint(of image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: CGImagePropertyOrientation.up,
            options: [:]
        )
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw PairQualityAnalysisError.unavailable
        }
        return observation
    }
}

/// Internal failures that only cause graceful degradation.
enum PairQualityAnalysisError: Error, Sendable {
    case unavailable
}
