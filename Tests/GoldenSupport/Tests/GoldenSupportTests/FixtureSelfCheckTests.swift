import CryptoKit
import Foundation
import XCTest
@testable import GoldenSupport
import TestShared

/// Acceptance tests for WP-04: the ten committed fixtures must be reproducible,
/// match their manifest, match their reference PNGs and contain no photos.
final class FixtureSelfCheckTests: XCTestCase {
    private static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "tif", "tiff", "dng", "webp", "png"
    ]

    /// Loose enough to absorb an 8-bit decode/colour-management rounding step,
    /// tight enough to fail if the Swift renderer and the committed reference
    /// disagree about layout, colours or noise.
    private static let referenceConsistency = ImageThresholds(
        channelTolerance: 2,
        allowedDifferingPixelRatio: 1.0,
        maxMeanDeltaE00: 1.0,
        maxP95DeltaE00: 2.0,
        maxDeltaE00: 6.0,
        minSSIM: 0.995
    )

    func testTenFixturesAreDeclaredOnceInManifestAndCatalog() throws {
        let environment = TestEnvironment()
        guard let manifestURL = environment.fixtureManifestURL else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }

        let data = try Data(contentsOf: manifestURL)
        let committedManifest = try FixtureManifest.decode(data)
        try committedManifest.validate()

        XCTAssertEqual(committedManifest.fixtures.count, 10)
        XCTAssertEqual(Set(committedManifest.fixtures.map(\.id)).count, 10)
        XCTAssertEqual(committedManifest, FixtureCatalog.manifest)
        XCTAssertEqual(committedManifest.schemaVersion, 1)
        XCTAssertEqual(committedManifest.generatorVersion, FixtureCatalog.generatorVersion)
        XCTAssertEqual(committedManifest.referenceDirectory, FixtureCatalog.referenceDirectory)

        let kinds = Set(committedManifest.fixtures.map(\.kind))
        XCTAssertEqual(kinds, Set(SyntheticPattern.allCases), "every pattern family is covered")
    }

    func testTenFixturesSelfCheckAgainstReferences() throws {
        let environment = TestEnvironment()
        guard let manifestURL = environment.fixtureManifestURL,
              let referenceDirectory = environment.referenceDirectory
        else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }

        let manifest = try FixtureManifest.decode(Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest.fixtures.count, 10)

        for entry in manifest.fixtures {
            // 1. Deterministic regeneration.
            let generated = try FixtureRenderer.render(entry)
            let regenerated = try FixtureRenderer.render(entry)
            XCTAssertEqual(generated.bytes, regenerated.bytes, "\(entry.id) is not deterministic")
            XCTAssertEqual(generated.pixelSize, entry.pixelSize, entry.id)

            // 2. Structural probes hold for generated pixels.
            let probes = try FixtureProbes.colorProbes(for: entry)
            for probe in probes {
                XCTAssertEqual(
                    generated[probe.x, probe.y].color,
                    probe.color,
                    "\(entry.id) generated probe (\(probe.x), \(probe.y))"
                )
            }

            // 3. The committed reference exists, is untouched and matches the spec.
            let file = try XCTUnwrap(entry.referenceFile, "\(entry.id) has no reference file")
            let expectedHash = try XCTUnwrap(entry.referenceSHA256, "\(entry.id) has no SHA-256")
            let referenceURL = referenceDirectory.appendingPathComponent(file)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: referenceURL.path),
                "\(entry.id) reference PNG is missing"
            )
            let referenceData = try Data(contentsOf: referenceURL)
            XCTAssertEqual(
                Self.sha256Hex(referenceData),
                expectedHash,
                "\(entry.id) reference PNG hash changed"
            )

            let reference = try PixelBuffer(imageData: referenceData)
            XCTAssertEqual(reference.pixelSize, entry.pixelSize, "\(entry.id) reference size")
            for probe in probes {
                XCTAssertEqual(
                    reference[probe.x, probe.y].color,
                    probe.color,
                    "\(entry.id) reference probe (\(probe.x), \(probe.y))"
                )
            }

            // 4. The Swift renderer and the Python-generated reference agree.
            if entry.kind == .faceSilhouette {
                // The face uses floating-point ellipse coverage; assert structural
                // agreement instead of pixel equality.
                let report = try ImageComparator.compare(
                    expected: reference,
                    actual: generated,
                    thresholds: .structural
                )
                XCTAssertTrue(report.passes, "\(entry.id): \(report.summary)")
                XCTAssertTrue(FixtureProbes.isMirrorSymmetric(generated))
                XCTAssertTrue(FixtureProbes.isMirrorSymmetric(reference))
            } else {
                let consistency = try ImageComparator.compare(
                    expected: reference,
                    actual: generated,
                    thresholds: Self.referenceConsistency
                )
                XCTAssertTrue(
                    consistency.passes,
                    "\(entry.id) generated pixels differ from the committed reference: "
                        + consistency.summary
                )
            }
        }
    }

    func testReferenceDirectoryContainsOnlyDeclaredFixtures() throws {
        let environment = TestEnvironment()
        guard let referenceDirectory = environment.referenceDirectory,
              let manifestURL = environment.fixtureManifestURL
        else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }
        let manifest = try FixtureManifest.decode(Data(contentsOf: manifestURL))
        let declared = Set(manifest.fixtures.compactMap(\.referenceFile))

        let contents = try FileManager.default.contentsOfDirectory(
            at: referenceDirectory,
            includingPropertiesForKeys: nil
        )
        let pngNames = Set(
            contents
                .filter { $0.pathExtension.lowercased() == "png" }
                .map(\.lastPathComponent)
        )
        XCTAssertEqual(pngNames, declared)
    }

    func testAuthorizedSampleManifestIsValidAndPhotoFree() throws {
        let environment = TestEnvironment()
        guard let repositoryRoot = environment.repositoryRoot else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }
        let samplesDirectory = repositoryRoot
            .appendingPathComponent("Fixtures/samples", isDirectory: true)
        let manifestURL = samplesDirectory.appendingPathComponent("manifest.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "authorized sample manifest is missing"
        )

        let manifest = try AuthorizedSampleManifest.decode(Data(contentsOf: manifestURL))
        try manifest.validate()

        let contents = try FileManager.default.contentsOfDirectory(
            at: samplesDirectory,
            includingPropertiesForKeys: nil
        )
        let imageFiles = contents.filter {
            Self.photoExtensions.contains($0.pathExtension.lowercased())
        }
        XCTAssertTrue(
            imageFiles.isEmpty,
            "real photos must never be committed: \(imageFiles.map(\.lastPathComponent))"
        )
    }

    func testFixturesContainNoPhotographicFiles() throws {
        let environment = TestEnvironment()
        guard let fixturesDirectory = environment.fixturesDirectory else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }
        let photoExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "tif", "tiff", "dng", "webp"]
        var offenders: [String] = []
        if let enumerator = FileManager.default.enumerator(
            at: fixturesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for case let url as URL in enumerator {
                if photoExtensions.contains(url.pathExtension.lowercased()) {
                    offenders.append(url.lastPathComponent)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "photographic files found in Fixtures: \(offenders)")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
