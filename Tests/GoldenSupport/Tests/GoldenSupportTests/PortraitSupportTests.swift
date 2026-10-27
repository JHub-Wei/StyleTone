import Foundation
import XCTest
@testable import GoldenSupport
import StyleToneCore
import TestShared

/// Unit-level checks for the WP-25 renderer, metrics and report types. They do
/// not run the production pipeline; the integration target covers that.
final class PortraitSupportTests: XCTestCase {
    private func repositoryCorpus() throws -> PortraitCorpus {
        let environment = TestEnvironment()
        let root = try environment.requireRepositoryRoot()
        let url = root.appendingPathComponent("Tests/Integration/Corpus/portrait-corpus.json")
        return try PortraitCorpus.decode(Data(contentsOf: url))
    }

    private func firstScene() throws -> PortraitScene {
        let corpus = try repositoryCorpus()
        let sample = try XCTUnwrap(corpus.samples.first { $0.id == "ps-006" })
        return try PortraitRenderer.render(sample)
    }

    func testCorpusDecodesAndSatisfiesCoverage() throws {
        let corpus = try repositoryCorpus()
        try corpus.validate()
        try corpus.validateCoverage()
        XCTAssertEqual(corpus.samples.count, 100)
        XCTAssertEqual(corpus.coverage.skinToneBandsCovered, 6)
        XCTAssertEqual(corpus.coverage.multiPersonSamples, 30)
        XCTAssertEqual(corpus.coverage.occlusionSamples, 45)
        XCTAssertEqual(corpus.coverage.doorFrameSamples, 40)
        XCTAssertEqual(corpus.coverage.floorTileSamples, 40)
        XCTAssertTrue(corpus.coverage.markdown().contains("door-frame+tiles"))
    }

    func testRendererIsDeterministicAndProducesUsableGroundTruth() throws {
        let scene = try firstScene()
        let regenerated = try PortraitRenderer.render(scene.spec)
        XCTAssertEqual(scene.pixels.bytes, regenerated.pixels.bytes)
        XCTAssertEqual(scene.analysis.faces.count, scene.spec.subjects.count)
        XCTAssertNotNil(scene.analysis.body)
        XCTAssertGreaterThan(MaskOperations.coverage(scene.groundTruth.personMask), 0.05)
        XCTAssertGreaterThan(MaskOperations.coverage(scene.groundTruth.skinMask), 0.01)
        XCTAssertGreaterThan(MaskOperations.coverage(scene.groundTruth.backgroundEdgeMask), 0.001)
        XCTAssertFalse(scene.groundTruth.lines.isEmpty)
        XCTAssertNotNil(scene.groundTruth.primaryFaceBox)
    }

    func testIdentityEvaluationPassesAndHasZeroDifference() throws {
        let scene = try firstScene()
        let evaluation = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: scene.pixels,
            retouched: scene.pixels,
            output: scene.pixels
        )
        XCTAssertTrue(evaluation.isPassing, evaluation.failures.joined(separator: "; "))
        XCTAssertEqual(evaluation.metrics.finalSSIM, 1, accuracy: 1e-9)
        XCTAssertEqual(evaluation.metrics.coverageMeanDeltaE00, 0, accuracy: 1e-9)
        XCTAssertEqual(evaluation.metrics.coverageP95DeltaE00, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(evaluation.background.measuredLineCount, 0)
        XCTAssertEqual(evaluation.background.distortedLineCount, 0)
        XCTAssertTrue(evaluation.skin.incidents.isEmpty)
        XCTAssertEqual(evaluation.metrics.skinSaturationRatio, 1, accuracy: 1e-9)
        XCTAssertEqual(evaluation.metrics.skinFinalMeanDeltaL, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(evaluation.metrics.edgeMedianContrastRetention, 0.9)
    }

    func testSignatureDetectsAChangedImage() throws {
        let scene = try firstScene()
        var changed = scene.pixels
        for y in 100 ..< 200 {
            for x in 100 ..< 200 {
                changed[x, y] = RGBA8(red: 255, green: 0, blue: 0)
            }
        }
        let original = try PortraitMetricEvaluator.signature(of: scene.pixels)
        let modified = try PortraitMetricEvaluator.signature(of: changed)
        let comparison = original.compare(to: modified)
        XCTAssertGreaterThan(comparison.meanLumaDelta, 0)
        XCTAssertGreaterThan(comparison.maxLumaDelta, 1)
        let identical = original.compare(to: original)
        XCTAssertEqual(identical.meanLumaDelta, 0, accuracy: 1e-9)
        XCTAssertEqual(identical.maxLumaDelta, 0)
    }

    func testBaselineComparatorFlagsRegressionsAndAcceptsIdentity() throws {
        let scene = try firstScene()
        let evaluation = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: scene.pixels,
            retouched: scene.pixels,
            output: scene.pixels
        )
        var current = evaluation.metrics
        current.backgroundMaxDeviationPx += 2
        current.backgroundMaxAngleDegrees += 1
        current.skinMeanDeltaE00 += 1
        current.skinP95DeltaE00 += 2
        current.skinSaturationRatio -= 0.05
        current.finalSSIM -= 0.05
        current.edgeMedianContrastRetention -= 0.1
        let messages = PortraitBaselineComparator.regressions(
            current: current,
            baseline: evaluation.metrics
        )
        XCTAssertTrue(messages.contains { $0.contains("backgroundMaxDeviationPx") })
        XCTAssertTrue(messages.contains { $0.contains("skinMeanDeltaE00") })
        XCTAssertTrue(messages.contains { $0.contains("finalSSIM") })
        XCTAssertTrue(messages.contains { $0.contains("edgeMedianContrastRetention") })
        XCTAssertTrue(
            PortraitBaselineComparator.regressions(
                current: evaluation.metrics,
                baseline: evaluation.metrics
            ).isEmpty
        )
    }

    func testReportAndArtifactsAreSelfConsistent() throws {
        let corpus = try repositoryCorpus()
        let scene = try firstScene()
        let evaluation = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: scene.pixels,
            retouched: scene.pixels,
            output: scene.pixels
        )
        let result = PortraitSampleResult(
            sampleID: scene.spec.id,
            skinTone: scene.spec.primarySubject.skinTone.roman,
            bodyType: scene.spec.primarySubject.bodyType.rawValue,
            background: scene.spec.background.displayName,
            framing: scene.spec.framing.displayName,
            occlusions: [],
            personCount: scene.spec.subjects.count,
            metrics: evaluation.metrics,
            failures: [],
            baselineRegressions: []
        )
        let gates = PortraitAggregateGate.evaluate(
            results: [result],
            thresholds: PortraitAggregateThresholds(
                backgroundDistortionRateMax: 0.05,
                minimumSamplesWithMeasuredLines: 0,
                skinIncidentSamplesMax: 0,
                edgeFailureSamplesMax: 0,
                fairnessSpreadMaxDeltaL: 1,
                darkSkinMeanDeltaLMax: 1,
                baselineRegressionsMax: 0
            ),
            baselineMode: .bootstrap
        )
        let report = PortraitRegressionReport(
            suite: "unit",
            corpusVersion: corpus.corpusVersion,
            corpusSHA256: "unit",
            baselineMode: .bootstrap,
            coverage: corpus.coverage,
            results: [result],
            gates: gates
        )
        XCTAssertTrue(report.markdown().contains(scene.spec.id))
        XCTAssertTrue(
            report.categoryTable().contains("tone \(scene.spec.primarySubject.skinTone.roman)")
        )

        let diff = try ImageComparator.differenceImage(
            expected: scene.pixels,
            actual: scene.pixels
        )
        let entry = PortraitContactSheetEntry(
            sampleID: scene.spec.id,
            skinTone: scene.spec.primarySubject.skinTone,
            source: PortraitArtifactBuilder.resized(scene.pixels, width: 72, height: 96),
            output: PortraitArtifactBuilder.resized(scene.pixels, width: 72, height: 96),
            difference: PortraitArtifactBuilder.resized(diff, width: 72, height: 96)
        )
        let sheet = try PortraitArtifactBuilder.contactSheet(entries: [entry])
        XCTAssertGreaterThan(sheet.width, 0)
        XCTAssertGreaterThan(sheet.height, 0)

        let diagnostics = try PortraitArtifactBuilder.diagnostics(
            scene: scene,
            source: scene.pixels,
            output: scene.pixels
        )
        XCTAssertEqual(diagnostics.width, scene.pixels.width)
        XCTAssertEqual(diagnostics.height, scene.pixels.height)
    }
}
