import Foundation

public enum PairQualityGrade: String, Sendable, Codable, CaseIterable {
    case good
    case warning
    case rejected
}

public struct PairQuality: Sendable, Codable, Equatable {
    public let grade: PairQualityGrade
    /// Localization keys describing why the pair received this grade.
    public let reasons: [String]
    public let confidence: Float

    public init(grade: PairQualityGrade, reasons: [String] = [], confidence: Float) {
        self.grade = grade
        self.reasons = reasons
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct PairSample: Sendable {
    public let id: UUID
    public let original: ImageAsset
    public let edited: ImageAsset
    public let quality: PairQuality

    public init(
        id: UUID = UUID(),
        original: ImageAsset,
        edited: ImageAsset,
        quality: PairQuality
    ) {
        self.id = id
        self.original = original
        self.edited = edited
        self.quality = quality
    }
}

public enum CalibrationDimension: String, Codable, Sendable, CaseIterable {
    case skinTone
    case smoothing
    case faceSlim
    case bodySlim
    case legLength
    case tone
    case naturalness
}

public struct CalibrationAnswer: Codable, Sendable, Equatable {
    public let dimension: CalibrationDimension
    public let choseA: Bool
    public let strengthDelta: Double

    public init(dimension: CalibrationDimension, choseA: Bool, strengthDelta: Double = 0) {
        self.dimension = dimension
        self.choseA = choseA
        self.strengthDelta = min(max(strengthDelta, -1), 1)
    }
}
