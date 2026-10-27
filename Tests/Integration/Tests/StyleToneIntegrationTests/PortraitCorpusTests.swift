import Foundation
import GoldenSupport
import StyleToneCore
import XCTest

/// Corpus-level checks: coverage matrix, deterministic rendering, privacy and
/// baseline/golden integrity. These are cheap and run before the quality gate.
final class PortraitCorpusTests: XCTestCase {
    private static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "tif", "tiff", "dng", "webp", "bmp", "gif"
    ]

    func testCorpusIsValidAndCoversTheRequiredMatrix() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, _) = try environment.loadCorpus()
        XCTAssertEqual(corpus.samples.count, PortraitCorpus.acceptanceSampleCount)
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertFalse(corpus.corpusVersion.isEmpty)

        let coverage = corpus.coverage
        XCTAssertEqual(coverage.skinToneBandsCovered, 6)
        for tone in SkinToneBand.allCases {
            XCTAssertGreaterThanOrEqual(
                coverage.skinTones[tone.roman] ?? 0,
                10,
                "tone \(tone.roman) is under-represented"
            )
        }
        for body in PortraitBodyType.allCases {
            XCTAssertGreaterThanOrEqual(
                coverage.bodyTypes[body.rawValue] ?? 0,
                10,
                "body type \(body.rawValue) is under-represented"
            )
        }
        XCTAssertGreaterThanOrEqual(coverage.doorFrameSamples, 30)
        XCTAssertGreaterThanOrEqual(coverage.floorTileSamples, 30)
        XCTAssertGreaterThanOrEqual(coverage.multiPersonSamples, 25)
        XCTAssertGreaterThanOrEqual(coverage.occlusionSamples, 30)
        XCTAssertLessThanOrEqual(coverage.framings.count, 3)
        XCTAssertEqual(Set(coverage.framings.keys), Set(PortraitFraming.allCases.map(\.rawValue)))
        XCTAssertTrue(corpus.coverage.markdown().contains("samples"))
    }

    func testRendererIsDeterministicAndGroundTruthIsConsistent() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, _) = try environment.loadCorpus()
        let identifiers = [
            "ps-001", "ps-006", "ps-009", "ps-010",
            "ps-018", "ps-022", "ps-032", "ps-043"
        ]
        for identifier in identifiers {
            let sample = try XCTUnwrap(
                corpus.samples.first { $0.id == identifier },
                "missing sample \(identifier)"
            )
            let first = try PortraitRenderer.render(sample)
            let second = try PortraitRenderer.render(sample)
            XCTAssertEqual(first.pixels.bytes, second.pixels.bytes, "\(identifier) is not deterministic")
            XCTAssertEqual(first.pixels.pixelSize, sample.pixelSize)
            XCTAssertEqual(first.analysis.faces.count, sample.subjects.count, identifier)
            if sample.framing == .headshot {
                XCTAssertNil(first.analysis.body, "\(identifier): headshot must not claim a body")
            } else {
                XCTAssertNotNil(first.analysis.body, "\(identifier): body observation is missing")
            }

            XCTAssertGreaterThan(
                MaskOperations.coverage(first.groundTruth.personMask),
                0.05,
                "\(identifier): person mask is empty"
            )
            XCTAssertGreaterThan(
                MaskOperations.coverage(first.groundTruth.skinMask),
                0.01,
                "\(identifier): skin mask is empty"
            )
            XCTAssertEqual(
                first.analysis.personMask?.bytes,
                Optional(first.groundTruth.personMask.bytes),
                "\(identifier): analysis mask differs from ground truth"
            )

            if sample.background == .plain {
                XCTAssertTrue(first.groundTruth.lines.isEmpty, "\(identifier): plain background has lines")
                XCTAssertEqual(MaskOperations.coverage(first.groundTruth.backgroundEdgeMask), 0)
            } else {
                XCTAssertFalse(first.groundTruth.lines.isEmpty, "\(identifier): no structure lines")
                XCTAssertGreaterThan(
                    MaskOperations.coverage(first.groundTruth.backgroundEdgeMask),
                    0.001,
                    "\(identifier): structure mask is empty"
                )
            }

            for subject in first.groundTruth.subjects {
                for kind in [
                    FaceLandmarkKind.leftEye,
                    .rightEye,
                    .nose,
                    .outerLips,
                    .faceContour
                ] {
                    XCTAssertFalse(
                        subject.faceLandmarks[kind]?.isEmpty ?? true,
                        "\(identifier): missing \(kind.rawValue) landmark"
                    )
                }
                XCTAssertTrue(subject.faceBox.width > 0 && subject.faceBox.height > 0)
                XCTAssertTrue(subject.personBox.width > 0 && subject.personBox.height > 0)
            }
        }
    }

    func testNoPhotographsOrPhotoPathsAreCommitted() throws {
        let environment = try IntegrationEnvironment()
        let integration = environment.repositoryRoot
            .appendingPathComponent("Tests/Integration", isDirectory: true)
        var offenders: [String] = []
        if let enumerator = FileManager.default.enumerator(
            at: integration,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let components = url.pathComponents
                if components.contains("Artifacts") || components.contains("golden-candidates") {
                    continue
                }
                let fileExtension = url.pathExtension.lowercased()
                if Self.photoExtensions.contains(fileExtension) {
                    offenders.append(url.lastPathComponent)
                }
                if fileExtension == "png" {
                    let parent = url.deletingLastPathComponent().lastPathComponent
                    if parent != "Goldens" {
                        offenders.append(url.lastPathComponent)
                    }
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "only synthetic goldens may be committed under Tests/Integration: \(offenders)"
        )

        let (corpus, corpusData) = try environment.loadCorpus()
        let corpusText = String(decoding: corpusData, as: UTF8.self)
        for forbidden in ["\"fileName\"", "\"authorizedBy\"", "\"license\"", "\"photo\""] {
            XCTAssertFalse(
                corpusText.contains(forbidden),
                "corpus must contain metadata only, found \(forbidden)"
            )
        }
        XCTAssertEqual(Set(corpus.samples.map(\.id)).count, corpus.samples.count)

        let manifestURL = environment.repositoryRoot
            .appendingPathComponent("Fixtures/samples/manifest.json")
        let manifest = try AuthorizedSampleManifest.decode(Data(contentsOf: manifestURL))
        try manifest.validate()
    }

    func testCommittedBaselineAndGoldensWhenPresent() throws {
        let environment = try IntegrationEnvironment()
        let (corpus, corpusData) = try environment.loadCorpus()
        let corpusHash = environment.sha256Hex(corpusData)

        if environment.baselineExists {
            let data = try Data(contentsOf: environment.baselineURL)
            let baseline = try PortraitBaseline.decode(data)
            try baseline.validate(corpus: corpus)
            XCTAssertEqual(baseline.corpusSHA256, corpusHash)
            XCTAssertEqual(baseline.entries.count, corpus.samples.count)
            for entry in baseline.entries {
                XCTAssertGreaterThan(entry.metrics.skinPixelCount, 0, entry.sampleID)
                XCTAssertEqual(entry.metrics.signature.lumaHex.count, 16 * 16 * 2)
                XCTAssertEqual(entry.metrics.signature.chromaAHex.count, 8 * 8 * 2)
            }
        }

        let goldenFiles = (try? FileManager.default.contentsOfDirectory(
            at: environment.goldensDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let goldenPNGs = goldenFiles.filter { $0.pathExtension.lowercased() == "png" }
        if !goldenPNGs.isEmpty {
            let expected = Set(
                PortraitGoldenSelection.sampleIDs.map { "\($0).png" }
            )
            let actual = Set(goldenPNGs.map(\.lastPathComponent))
            XCTAssertEqual(actual, expected)
            for identifier in PortraitGoldenSelection.sampleIDs {
                let sample = try XCTUnwrap(corpus.samples.first { $0.id == identifier })
                let golden = try XCTUnwrap(
                    PortraitGoldenComparison.load(identifier, from: environment.goldensDirectory)
                )
                XCTAssertEqual(golden.pixelSize, sample.pixelSize, identifier)
            }
        } else if !environment.baselineExists {
            throw XCTSkip(
                "baseline and visual goldens are recorded by the first green CI run; "
                    + "download the golden-artifacts artifact and commit them"
            )
        }
    }

    func testAuthorizedSamplesAreOptionalAndNeverCommitted() throws {
        let environment = try IntegrationEnvironment()
        let samplesDirectory = environment.repositoryRoot
            .appendingPathComponent("Fixtures/samples", isDirectory: true)
        let manifestURL = samplesDirectory.appendingPathComponent("manifest.json")
        let manifest = try AuthorizedSampleManifest.decode(Data(contentsOf: manifestURL))
        try manifest.validate()
        guard !manifest.samples.isEmpty else {
            throw XCTSkip(
                "no authorized samples in this checkout; the synthetic corpus is the CI gate "
                    + "(see Tests/Integration/README.md)"
            )
        }
        for sample in manifest.samples {
            let url = samplesDirectory.appendingPathComponent(sample.fileName)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "authorized sample '\(sample.id)' is missing from the local directory"
            )
            let pixels = try PixelBuffer(imageData: Data(contentsOf: url))
            XCTAssertGreaterThanOrEqual(min(pixels.width, pixels.height), 64, sample.id)
            XCTAssertFalse(sample.license.isEmpty)
            XCTAssertFalse(sample.authorizedBy.isEmpty)
        }
    }
}
