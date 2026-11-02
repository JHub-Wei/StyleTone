import StyleToneCore
import StyleToneLearning
import TestShared
import XCTest
@testable import StyleTonePairAnalysis

final class PairEditMetricsTests: XCTestCase {
    func testNarrowerEditedFaceProducesFaceSlimAndJawSignals() throws {
        let original = try face(width: 0.40)
        let edited = try face(width: 0.32)

        let result = try XCTUnwrap(
            FaceEditMetrics.compare(original: original, edited: edited)
        )
        XCTAssertGreaterThan(result.slim, 0.15)
        XCTAssertGreaterThan(result.jaw, 0.15)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testUnchangedFaceProducesNoFaceSignal() throws {
        let original = try face(width: 0.40)
        let edited = try face(width: 0.40)
        XCTAssertNil(FaceEditMetrics.compare(original: original, edited: edited))
    }

    func testNarrowerEditedWaistProducesBodySignal() throws {
        let original = try bodyAnalysis(waistWidth: 20)
        let edited = try bodyAnalysis(waistWidth: 15)

        let result = try XCTUnwrap(
            BodyEditMetrics.compare(original: original, edited: edited)
        )
        let waist = try XCTUnwrap(result.waist)
        XCTAssertGreaterThan(waist, 0.1)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testUnchangedBodyProducesNoBodySignal() throws {
        let original = try bodyAnalysis(waistWidth: 20)
        let edited = try bodyAnalysis(waistWidth: 20)

        XCTAssertNil(BodyEditMetrics.compare(original: original, edited: edited))
    }

    private func face(width: Double) throws -> FaceObservation {
        let minX = 0.5 - width / 2
        let maxX = 0.5 + width / 2
        let points = [
            NormalizedPoint(x: minX, y: 0.20),
            NormalizedPoint(x: minX, y: 0.70),
            NormalizedPoint(x: maxX, y: 0.70),
            NormalizedPoint(x: maxX, y: 0.20),
            NormalizedPoint(x: minX, y: 0.45),
            NormalizedPoint(x: maxX, y: 0.45),
        ]
        return FaceObservation(
            boundingBox: NormalizedRect(x: minX, y: 0.20, width: width, height: 0.50),
            landmarks: [.faceContour: points],
            confidence: 0.9
        )
    }

    private func bodyAnalysis(waistWidth: Int) throws -> PortraitAnalysis {
        let size = 64
        var bytes = [UInt8](repeating: 0, count: size * size)
        for y in 8..<56 {
            let width = y >= 24 && y <= 40 ? waistWidth : 24
            let start = 32 - width / 2
            for x in start..<(start + width) {
                bytes[y * size + x] = 255
            }
        }
        let mask = try MaskBuffer(width: size, height: size, bytes: Data(bytes))
        return PortraitAnalysis(
            imageSize: PixelSize(width: size, height: size),
            faces: [],
            body: nil,
            personMask: mask,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: []
        )
    }
}

final class AutoSignalStyleLearningTests: XCTestCase {
    private struct StubAnalyzer: PairEditAnalyzing {
        func analyze(
            original: ImageAsset,
            edited: ImageAsset
        ) async throws -> PairEditAnalysis {
            PairEditAnalysis(
                signals: PairStrengthSignals(
                    smoothing: 0.25,
                    faceSlim: 0.25,
                    waist: 0.25
                ),
                confidence: 0.9
            )
        }
    }

    func testAutomaticSignalsReachTheLearnedProfile() async throws {
        let pairs = try (0..<3).map { _ in
            PairSample(
                original: try MockImageAssetFactory.solid(),
                edited: try MockImageAssetFactory.solid(
                    color: RGB8(red: 150, green: 120, blue: 100)
                ),
                quality: PairQuality(grade: .good, confidence: 0.9)
            )
        }
        let learner = AutoSignalStyleLearning(
            engine: StyleLearningEngine(),
            analyzer: StubAnalyzer()
        )

        let profile = try await learner.learn(samples: pairs, answers: [])

        XCTAssertGreaterThan(profile.skin.smoothing, 0.10)
        XCTAssertGreaterThan(profile.face.slim, 0.10)
        XCTAssertGreaterThan(profile.body.waist, 0.10)
    }
}
