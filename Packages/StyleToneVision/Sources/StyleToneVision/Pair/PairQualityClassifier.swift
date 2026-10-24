import Foundation
import StyleToneCore

/// Deterministic decision rule that turns pair metrics into ``PairQuality``.
///
/// Keeping this separate from Vision makes the grading table unit-testable and
/// keeps thresholds in one place.
enum PairQualityClassifier {
    static func classify(
        metrics: VisionPairQualityMetrics,
        configuration: VisionPairQualityConfiguration
    ) -> PairQuality {
        var reasons: [PairQualityReason] = []

        if metrics.resolutionRatio < configuration.rejectedResolutionRatio {
            reasons.append(.resolutionTooLow)
        } else if metrics.resolutionRatio < configuration.warningResolutionRatio {
            reasons.append(.resolutionReduced)
        }

        if metrics.aspectRatioDelta > configuration.rejectedAspectRatioDelta {
            reasons.append(.aspectRatioMismatch)
        } else if metrics.aspectRatioDelta > configuration.warningAspectRatioDelta {
            reasons.append(.aspectRatioChanged)
        }

        if let offset = metrics.registrationOffset {
            if offset > configuration.rejectedMisalignment {
                reasons.append(.notRegistered)
            } else if offset > configuration.warningMisalignment {
                reasons.append(.misaligned)
            }
        }

        if let similarity = metrics.semanticSimilarity {
            if similarity < configuration.rejectedSimilarity {
                reasons.append(.semanticMismatch)
            } else if similarity < configuration.warningSimilarity {
                reasons.append(.semanticDrift)
            }
        }

        if let structure = metrics.structureDelta {
            if structure > configuration.rejectedStructureDelta {
                reasons.append(.structureMismatch)
            } else if structure > configuration.warningStructureDelta {
                reasons.append(.structureChanged)
            }
        }

        if metrics.semanticSimilarity == nil, metrics.structureDelta == nil {
            reasons.append(.analysisUnavailable)
        }

        var uniqueReasons: [PairQualityReason] = []
        for reason in reasons where !uniqueReasons.contains(reason) {
            uniqueReasons.append(reason)
        }

        let rejected: Set<PairQualityReason> = [
            .resolutionTooLow,
            .aspectRatioMismatch,
            .notRegistered,
            .semanticMismatch,
            .structureMismatch
        ]
        let grade: PairQualityGrade
        if uniqueReasons.contains(where: { rejected.contains($0) }) {
            grade = .rejected
        } else if !uniqueReasons.isEmpty {
            grade = .warning
        } else {
            grade = .good
        }

        var confidence: Float = 0.90
        if metrics.semanticSimilarity == nil {
            confidence -= 0.15
        }
        if metrics.structureDelta == nil {
            confidence -= 0.20
        }
        if metrics.registrationOffset == nil {
            confidence -= 0.10
        }
        if metrics.originalSize.shortEdge < 64 || metrics.editedSize.shortEdge < 64 {
            confidence -= 0.20
        }
        if let registrationConfidence = metrics.registrationConfidence,
           registrationConfidence < 0.30 {
            confidence -= 0.10
        }
        confidence = min(max(confidence, 0.05), 1)

        return PairQuality(
            grade: grade,
            reasons: uniqueReasons.map(\.rawValue),
            confidence: confidence
        )
    }
}
