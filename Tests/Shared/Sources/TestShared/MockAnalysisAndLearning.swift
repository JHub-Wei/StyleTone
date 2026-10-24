import Foundation
import GoldenSupport
import StyleToneCore

/// A configurable `PortraitAnalyzing` test double.
public struct MockPortraitAnalyzer: PortraitAnalyzing {
    public enum Behavior: Sendable {
        /// Always returns a fixed analysis, ignoring the input image.
        case fixed(PortraitAnalysis)
        /// Builds a deterministic mock analysis matching the input pixel size.
        case generated(faceCount: Int, includesBody: Bool, includesMasks: Bool)
        /// Throws a fixed error.
        case failure(StyleToneError)
    }

    public let behavior: Behavior

    public init(behavior: Behavior) {
        self.behavior = behavior
    }

    public init(analysis: PortraitAnalysis) {
        self.behavior = .fixed(analysis)
    }

    public init(failure: StyleToneError) {
        self.behavior = .failure(failure)
    }

    /// Creates an analyzer that fabricates a portrait for any input size.
    public static func generated(
        faceCount: Int = 1,
        includesBody: Bool = true,
        includesMasks: Bool = true
    ) -> MockPortraitAnalyzer {
        MockPortraitAnalyzer(
            behavior: .generated(
                faceCount: faceCount,
                includesBody: includesBody,
                includesMasks: includesMasks
            )
        )
    }

    public func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        switch behavior {
        case let .fixed(analysis):
            return analysis
        case let .generated(faceCount, includesBody, includesMasks):
            return try MockPortraitAnalysisFactory.portrait(
                size: image.pixelSize,
                faceCount: faceCount,
                includesBody: includesBody,
                includesMasks: includesMasks
            )
        case let .failure(error):
            throw error
        }
    }
}

/// A `PairQualityAnalyzing` test double returning a fixed grade.
public struct MockPairQualityAnalyzer: PairQualityAnalyzing {
    public let quality: PairQuality
    public let error: StyleToneError?

    public init(
        quality: PairQuality = PairQuality(grade: .good, reasons: [], confidence: 0.9),
        error: StyleToneError? = nil
    ) {
        self.quality = quality
        self.error = error
    }

    public func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        if let error {
            throw error
        }
        return quality
    }

    public static func graded(
        _ grade: PairQualityGrade,
        reasons: [String] = [],
        confidence: Float = 0.9
    ) -> MockPairQualityAnalyzer {
        MockPairQualityAnalyzer(
            quality: PairQuality(grade: grade, reasons: reasons, confidence: confidence)
        )
    }
}

/// Ready-made `StyleProfile` values with the shapes WP-10/11/17 expect.
public enum MockStyleProfileFactory {
    /// Fixed timestamp so JSON and equality checks stay deterministic.
    public static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    public static func natural(updatedAt: Date = referenceDate) -> StyleProfile {
        StyleProfile(pairCount: 0, confidence: .trial, updatedAt: updatedAt)
    }

    public static func trial(updatedAt: Date = referenceDate) -> StyleProfile {
        standard(updatedAt: updatedAt).with(pairCount: 3, confidence: .trial)
    }

    public static func standard(updatedAt: Date = referenceDate) -> StyleProfile {
        StyleProfile(
            pairCount: 5,
            confidence: .standard,
            tone: ToneParameters(
                exposure: 0.12,
                contrast: 0.08,
                highlights: -0.10,
                shadows: 0.15,
                temperature: 0.06,
                tint: 0.02,
                saturation: 0.10
            ),
            skin: SkinParameters(smoothing: 0.35, evenness: 0.25, blemish: 0.20),
            face: FaceParameters(slim: 0.25, jaw: 0.15),
            body: BodyParameters(arm: 0.20, waist: 0.18, leg: 0.12, legLength: 1.03),
            finish: FinishParameters(grain: 0.08, vignette: -0.10),
            tags: ["style.tag.natural", "style.tag.warm"],
            updatedAt: updatedAt
        )
    }

    public static func stable(updatedAt: Date = referenceDate) -> StyleProfile {
        StyleProfile(
            pairCount: 8,
            confidence: .stable,
            tone: ToneParameters(
                exposure: 0.06,
                contrast: 0.04,
                highlights: -0.06,
                shadows: 0.08,
                temperature: 0.03,
                tint: 0.0,
                saturation: 0.06
            ),
            skin: SkinParameters(smoothing: 0.20, evenness: 0.15, blemish: 0.10),
            face: FaceParameters(slim: 0.15, jaw: 0.10),
            body: BodyParameters(arm: 0.10, waist: 0.10, leg: 0.06, legLength: 1.02),
            finish: FinishParameters(grain: 0.04, vignette: -0.05),
            tags: ["style.tag.natural"],
            updatedAt: updatedAt
        )
    }

    /// Maximum legal strengths, used to prove clamping and safety rails.
    public static func extreme(updatedAt: Date = referenceDate) -> StyleProfile {
        StyleProfile(
            pairCount: 8,
            confidence: .stable,
            tone: ToneParameters(
                exposure: 1,
                contrast: 1,
                highlights: -1,
                shadows: 1,
                temperature: 1,
                tint: 1,
                saturation: 1
            ),
            skin: SkinParameters(smoothing: 1, evenness: 1, blemish: 1),
            face: FaceParameters(slim: 1, jaw: 1),
            body: BodyParameters(arm: 1, waist: 1, leg: 1, legLength: 1.15),
            finish: FinishParameters(grain: 1, vignette: -1),
            tags: ["style.tag.strong"],
            updatedAt: updatedAt
        )
    }
}

/// A `StyleLearning` double returning a fixed profile.
public struct MockStyleLearner: StyleLearning {
    public let profile: StyleProfile
    public let error: StyleToneError?

    public init(
        profile: StyleProfile = MockStyleProfileFactory.standard(),
        error: StyleToneError? = nil
    ) {
        self.profile = profile
        self.error = error
    }

    public func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile {
        if let error {
            throw error
        }
        return profile
    }
}

/// A `StyleLearning` double that records how often, and with what batch sizes,
/// the learning engine was called. Useful for WP-11 flow tests.
public actor RecordingStyleLearner: StyleLearning {
    public private(set) var sampleCounts: [Int] = []
    public private(set) var answerCounts: [Int] = []

    private let profile: StyleProfile
    private let error: StyleToneError?

    public init(
        profile: StyleProfile = MockStyleProfileFactory.standard(),
        error: StyleToneError? = nil
    ) {
        self.profile = profile
        self.error = error
    }

    public func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile {
        sampleCounts.append(samples.count)
        answerCounts.append(answers.count)
        if let error {
            throw error
        }
        return profile
    }
}

private extension StyleProfile {
    func with(pairCount: Int, confidence: ConfidenceLevel) -> StyleProfile {
        var copy = self
        copy.pairCount = pairCount
        copy.confidence = confidence
        return copy
    }
}
