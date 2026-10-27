import Foundation
import GoldenSupport
import StyleToneCore
import XCTest

/// Proves that the WP-25 metrics fail on deliberately broken images and that a
/// failure names the sample, metric and artifact. A golden suite that cannot
/// fail is worse than no suite.
final class PortraitFailureLocalizationTests: XCTestCase {
    func testMetricsDetectInjectedBackgroundSkinAndEdgeDefects() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, _) = try environment.loadCorpus()
        let sample = try XCTUnwrap(
            corpus.samples.first { $0.id == "ps-001" },
            "the acceptance corpus lost its reference sample"
        )
        let scene = try PortraitRenderer.render(sample)
        let source = scene.pixels

        let identity = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: source,
            retouched: source,
            output: source
        )
        XCTAssertGreaterThan(identity.background.measuredLineCount, 0, "no background line was measured")
        XCTAssertEqual(identity.background.distortedLineCount, 0)
        XCTAssertTrue(identity.skin.incidents.isEmpty, identity.skin.incidents.joined(separator: "; "))
        XCTAssertEqual(identity.metrics.finalSSIM, 1, accuracy: 1e-9)
        XCTAssertEqual(identity.metrics.coverageMeanDeltaE00, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(identity.edge.boundarySamples, 20)

        let bentPixels = try PortraitDefectInjection.bendBackgroundLine(
            scene: scene,
            pixels: source
        )
        let bent = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: source,
            retouched: source,
            output: bentPixels
        )
        XCTAssertGreaterThan(
            bent.background.distortedLineCount,
            0,
            "a 4 px sine bend must trip the background line gate"
        )
        XCTAssertGreaterThan(bent.background.maxDeviationPx, 1.5)

        let tintedPixels = PortraitDefectInjection.tintSkin(scene: scene, pixels: source)
        let tinted = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: source,
            retouched: tintedPixels,
            output: source
        )
        XCTAssertGreaterThan(tinted.skin.meanDeltaE00, 3)
        XCTAssertFalse(tinted.skin.incidents.isEmpty, "a strong skin cast must be an incident")

        let blurredPixels = try PortraitDefectInjection.blurSilhouette(
            scene: scene,
            pixels: source
        )
        let blurred = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: source,
            retouched: source,
            output: blurredPixels
        )
        XCTAssertLessThan(
            blurred.edge.medianContrastRetention,
            0.99,
            "a blurred silhouette must lower edge contrast"
        )

        let diagnostics = try PortraitArtifactBuilder.diagnostics(
            scene: scene,
            source: source,
            output: bentPixels
        )
        XCTAssertEqual(diagnostics.width, source.width)
        XCTAssertEqual(diagnostics.height, source.height)
        let diagnosticsData = try diagnostics.pngData()
        let diagnosticsURL = try environment.write(
            diagnosticsData,
            name: "failure-localisation.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        environment.attach(
            diagnosticsData,
            name: "failure-localisation.png",
            uniformTypeIdentifier: "public.png",
            to: self
        )

        let sampleResult = PortraitSampleResult(
            sampleID: sample.id,
            skinTone: sample.primarySubject.skinTone.roman,
            bodyType: sample.primarySubject.bodyType.rawValue,
            background: sample.background.displayName,
            framing: sample.framing.displayName,
            occlusions: [],
            personCount: sample.subjects.count,
            metrics: bent.metrics,
            failures: bent.failures + ["skin.meanDeltaE00 9.000 > 3.000"],
            baselineRegressions: []
        )
        XCTAssertFalse(sampleResult.isPassing)
        XCTAssertTrue(sampleResult.categoryLabel.contains("I"))
        XCTAssertFalse(bent.failures.isEmpty)
    }

    func testBaselineComparatorNamesEveryRegression() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, _) = try environment.loadCorpus()
        let sample = try XCTUnwrap(corpus.samples.first)
        let scene = try PortraitRenderer.render(sample)
        let identity = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: scene.pixels,
            retouched: scene.pixels,
            output: scene.pixels
        )
        var current = identity.metrics
        current.backgroundMaxDeviationPx += 2.0
        current.backgroundMaxAngleDegrees += 1.0
        current.skinMeanDeltaE00 += 1.0
        current.skinP95DeltaE00 += 2.0
        current.skinSaturationRatio -= 0.05
        current.skinFinalMeanDeltaL += 1.0
        current.finalSSIM -= 0.06
        current.edgeMedianContrastRetention -= 0.10
        current.edgeDegradedFraction += 0.05
        current.coverageMeanDeltaE00 += 1.0

        let messages = PortraitBaselineComparator.regressions(
            current: current,
            baseline: identity.metrics
        )
        let joined = messages.joined(separator: "\n")
        XCTAssertTrue(joined.contains("backgroundMaxDeviationPx"), joined)
        XCTAssertTrue(joined.contains("backgroundMaxAngleDegrees"), joined)
        XCTAssertTrue(joined.contains("skinMeanDeltaE00"), joined)
        XCTAssertTrue(joined.contains("skinP95DeltaE00"), joined)
        XCTAssertTrue(joined.contains("skinSaturationRatio"), joined)
        XCTAssertTrue(joined.contains("skinFinalAbsDeltaL"), joined)
        XCTAssertTrue(joined.contains("finalSSIM"), joined)
        XCTAssertTrue(joined.contains("edgeMedianContrastRetention"), joined)
        XCTAssertTrue(joined.contains("edgeDegradedFraction"), joined)
        XCTAssertTrue(joined.contains("coverageMeanDeltaE00"), joined)

        let identical = PortraitBaselineComparator.regressions(
            current: identity.metrics,
            baseline: identity.metrics
        )
        XCTAssertTrue(identical.isEmpty, identical.joined(separator: "; "))
    }

    func testReportShowsSampleAndGateFailures() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, _) = try environment.loadCorpus()
        let sample = try XCTUnwrap(corpus.samples.first)
        let scene = try PortraitRenderer.render(sample)
        let identity = try PortraitMetricEvaluator.evaluate(
            scene: scene,
            source: scene.pixels,
            retouched: scene.pixels,
            output: scene.pixels
        )
        var result = PortraitSampleResult(
            sampleID: sample.id,
            skinTone: sample.primarySubject.skinTone.roman,
            bodyType: sample.primarySubject.bodyType.rawValue,
            background: sample.background.displayName,
            framing: sample.framing.displayName,
            occlusions: [],
            personCount: sample.subjects.count,
            metrics: identity.metrics,
            failures: ["skin.meanDeltaE00 4.000 > 3.000"],
            baselineRegressions: []
        )
        result.durationSeconds = 0.01
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
            baselineMode: .comparison
        )
        let report = PortraitRegressionReport(
            suite: "failure-localisation",
            corpusVersion: corpus.corpusVersion,
            corpusSHA256: "test",
            baselineMode: .comparison,
            coverage: corpus.coverage,
            results: [result],
            gates: gates
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains(sample.id), markdown)
        XCTAssertTrue(markdown.contains("skin.meanDeltaE00"), markdown)
        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(report.summary.failedSamples, 1)
        XCTAssertGreaterThan(report.summary.failedGates, 0)
    }
}
