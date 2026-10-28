import Foundation
import GoldenSupport
import StyleToneCore
import XCTest

/// WP-25 acceptance test: 100 synthetic portraits through the real Retouch and
/// Geometry pipeline, measured against the absolute quality gates and (once
/// recorded) the committed metric/visual baseline.
final class PortraitQualityGateTests: XCTestCase {
    func testHundredSyntheticPortraitsMeetQualityGates() async throws {
        let environment = try IntegrationEnvironment()
        let (corpus, corpusData) = try environment.loadCorpus()
        let corpusHash = environment.sha256Hex(corpusData)
        let baseline = try environment.loadBaseline(corpus: corpus)
        let baselineMode: PortraitBaselineMode = baseline == nil ? .bootstrap : .comparison

        if let baseline, baseline.corpusSHA256 != corpusHash {
            XCTFail(
                "baseline was recorded for corpus \(baseline.corpusSHA256), "
                    + "current corpus is \(corpusHash); re-record the baseline"
            )
            return
        }

        let runner = PortraitPipelineRunner()
        var results: [PortraitSampleResult] = []
        results.reserveCapacity(corpus.samples.count)
        var contactEntries: [PortraitContactSheetEntry] = []
        contactEntries.reserveCapacity(corpus.samples.count)
        let goldenIDs = Set(PortraitGoldenSelection.sampleIDs)
        var goldenCompared = 0
        var goldenMissing = 0
        var goldenFailed = 0
        var totalDuration = 0.0

        for (index, sample) in corpus.samples.enumerated() {
            let scene = try PortraitRenderer.render(sample)
            let pipeline = try await runner.run(scene: scene)
            totalDuration += pipeline.durationSeconds
            let evaluation = try PortraitMetricEvaluator.evaluate(
                scene: scene,
                source: pipeline.source,
                retouched: pipeline.retouched,
                output: pipeline.output,
                renderedPersonMask: pipeline.renderedPersonMask,
                thresholds: .standard
            )

            var failures = evaluation.failures.filter { !$0.hasPrefix("background.") }
            let warnings = evaluation.failures.filter { $0.hasPrefix("background.") }
            var baselineRegressions: [String] = []
            if let baseline {
                if let entry = baseline.entry(for: sample.id) {
                    baselineRegressions = PortraitBaselineComparator.regressions(
                        current: evaluation.metrics,
                        baseline: entry.metrics
                    )
                } else {
                    baselineRegressions = ["baseline sample entry is missing"]
                }
            }

            if goldenIDs.contains(sample.id) {
                if let golden = try PortraitGoldenComparison.load(
                    sample.id,
                    from: environment.goldensDirectory
                ) {
                    goldenCompared += 1
                    let report = try ImageComparator.compare(
                        expected: golden,
                        actual: pipeline.output,
                        thresholds: PortraitGoldenComparison.thresholds
                    )
                    if !report.passes {
                        goldenFailed += 1
                        failures.append("golden.\(sample.id) \(report.summary)")
                    }
                } else {
                    goldenMissing += 1
                    try environment.write(
                        pipeline.output.pngData(),
                        name: "golden-candidates/\(sample.id).png"
                    )
                }
            }

            let result = PortraitSampleResult(
                sampleID: sample.id,
                skinTone: sample.primarySubject.skinTone.roman,
                bodyType: sample.primarySubject.bodyType.rawValue,
                background: sample.background.displayName,
                framing: sample.framing.displayName,
                occlusions: sample.subjects
                    .map(\.occlusion)
                    .filter { $0 != .none }
                    .map(\.displayName),
                personCount: sample.subjects.count,
                metrics: evaluation.metrics,
                failures: failures,
                warnings: warnings,
                baselineRegressions: baselineRegressions,
                durationSeconds: pipeline.durationSeconds
            )
            results.append(result)

            if !result.isPassing {
                let diagnostics = try PortraitArtifactBuilder.diagnostics(
                    scene: scene,
                    source: pipeline.source,
                    output: pipeline.output
                )
                let diagnosticData = try diagnostics.pngData()
                let diagnosticName = "\(sample.id)-diagnostics.png"
                try environment.write(diagnosticData, name: diagnosticName)
                environment.attach(
                    diagnosticData,
                    name: diagnosticName,
                    uniformTypeIdentifier: "public.png",
                    to: self
                )
            }

            let thumbnailSize = (width: 72, height: 96)
            let sourceThumb = PortraitArtifactBuilder.resized(
                pipeline.source,
                width: thumbnailSize.width,
                height: thumbnailSize.height
            )
            let outputThumb = PortraitArtifactBuilder.resized(
                pipeline.output,
                width: thumbnailSize.width,
                height: thumbnailSize.height
            )
            let differenceThumb = try ImageComparator.differenceImage(
                expected: sourceThumb,
                actual: outputThumb,
                amplification: 6
            )
            contactEntries.append(
                PortraitContactSheetEntry(
                    sampleID: sample.id,
                    skinTone: sample.primarySubject.skinTone,
                    source: sourceThumb,
                    output: outputThumb,
                    difference: differenceThumb
                )
            )

            if (index + 1) % 10 == 0 {
                print("PORTRAIT_GATE progress \(index + 1)/\(corpus.samples.count)")
            }
        }

        var gates = PortraitAggregateGate.evaluate(
            results: results,
            thresholds: .standard,
            baselineMode: baselineMode
        )

        if goldenMissing > 0 {
            gates.append(
                PortraitGateResult(
                    name: "quality.goldens",
                    passed: true,
                    skipped: true,
                    value: Double(goldenMissing),
                    threshold: 0,
                    message: "\(goldenMissing) golden image(s) pending; candidates written to artifacts"
                )
            )
        } else {
            gates.append(
                PortraitGateResult(
                    name: "quality.goldens",
                    passed: goldenFailed == 0,
                    value: Double(goldenFailed),
                    threshold: 0,
                    message: "\(goldenCompared) golden images compared, \(goldenFailed) failed"
                )
            )
        }

        let report = PortraitRegressionReport(
            suite: "StyleToneIntegrationTests.PortraitQualityGate",
            corpusVersion: corpus.corpusVersion,
            corpusSHA256: corpusHash,
            baselineMode: baselineMode,
            coverage: corpus.coverage,
            results: results,
            gates: gates
        )

        let reportJSON = try report.jsonData()
        try environment.write(reportJSON, name: "portrait-report.json")
        try environment.write(report.markdown(), name: "portrait-report.md")
        environment.attach(
            reportJSON,
            name: "portrait-report.json",
            uniformTypeIdentifier: "public.json",
            to: self
        )
        environment.attach(
            Data(report.markdown().utf8),
            name: "portrait-report.md",
            uniformTypeIdentifier: "public.plain-text",
            to: self
        )

        let contactSheet = try PortraitArtifactBuilder.contactSheet(entries: contactEntries)
        let contactData = try contactSheet.pngData()
        try environment.write(contactData, name: "contact-sheet.png")
        environment.attach(
            contactData,
            name: "contact-sheet.png",
            uniformTypeIdentifier: "public.png",
            to: self
        )

        let absoluteGatesPassed = gates.allSatisfy { $0.skipped || $0.passed }
        if baselineMode == .bootstrap && absoluteGatesPassed {
            let entries = results.map {
                PortraitBaselineEntry(sampleID: $0.sampleID, metrics: $0.metrics)
            }
            let candidate = PortraitBaseline(
                corpusVersion: corpus.corpusVersion,
                corpusSHA256: corpusHash,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                entries: entries
            )
            let candidateData = try candidate.encodedJSON()
            try environment.write(candidateData, name: "portrait-baseline-candidate.json")
            environment.attach(
                candidateData,
                name: "portrait-baseline-candidate.json",
                uniformTypeIdentifier: "public.json",
                to: self
            )
            print(
                "PORTRAIT_BASELINE_BOOTSTRAP samples=\(entries.count) "
                    + "corpusSHA256=\(corpusHash)"
            )
        }

        print(
            "PORTRAIT_GATE samples=\(results.count) "
                + "baselineMode=\(baselineMode.rawValue) "
                + "goldensCompared=\(goldenCompared) goldensMissing=\(goldenMissing) "
                + "goldenFailed=\(goldenFailed) "
                + "totalPipelineSeconds=\(String(format: "%.2f", totalDuration))"
        )
        for gate in gates where !gate.passed && !gate.skipped {
            print("PORTRAIT_GATE_FAIL \(gate.name) value=\(gate.value) \(gate.message)")
        }
        for result in results where !result.isPassing {
            print(
                "PORTRAIT_SAMPLE_FAIL \(result.sampleID) [\(result.categoryLabel)] "
                    + "\(result.failures.joined(separator: " | ")) "
                    + "\(result.baselineRegressions.joined(separator: " | "))"
            )
        }

        let failedGates = gates.filter { !$0.passed && !$0.skipped }
        let failedSamples = results.filter { !$0.isPassing }
        if !failedGates.isEmpty || !failedSamples.isEmpty {
            let sampleDetails = failedSamples.prefix(12).map { result in
                let details = (result.failures + result.baselineRegressions)
                    .prefix(3)
                    .joined(separator: "; ")
                return "\(result.sampleID) [\(result.categoryLabel)]: \(details)"
            }
            XCTFail(
                "Portrait quality gate failed: \(failedGates.count) gate(s), "
                    + "\(failedSamples.count) sample(s).\n"
                    + "Gates: "
                    + failedGates.map { "\($0.name) (\($0.message))" }.joined(separator: "; ")
                    + "\nSamples:\n"
                    + sampleDetails.joined(separator: "\n")
                    + "\nArtifacts: \(environment.artifactsDirectory.path)"
            )
        }
    }
}
