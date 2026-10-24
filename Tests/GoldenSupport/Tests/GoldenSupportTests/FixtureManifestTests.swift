import XCTest
@testable import GoldenSupport
import StyleToneCore

final class FixtureManifestTests: XCTestCase {
    func testBuiltInManifestRoundTrips() throws {
        let manifest = FixtureCatalog.manifest
        let data = try manifest.encodedJSON()
        let decoded = try FixtureManifest.decode(data)
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.schemaVersion, FixtureManifest.currentSchemaVersion)
        XCTAssertEqual(decoded.fixtures.count, 10)
    }

    func testManifestValidationAcceptsBuiltInCatalog() throws {
        try FixtureCatalog.manifest.validate()
    }

    func testManifestValidationRejectsDuplicateIdentifiers() {
        let entry = FixtureManifestEntry(
            id: "dup",
            kind: .solidColor,
            width: 4,
            height: 4,
            colors: ["#000000"],
            purpose: "duplicate"
        )
        let manifest = FixtureManifest(fixtures: [entry, entry])
        XCTAssertThrowsError(try manifest.validate())
    }

    func testManifestValidationRejectsInvalidColoursAndDimensions() {
        let invalidColour = FixtureManifestEntry(
            id: "bad-colour",
            kind: .solidColor,
            width: 4,
            height: 4,
            colors: ["nope"],
            purpose: "bad colour"
        )
        XCTAssertThrowsError(try FixtureManifest(fixtures: [invalidColour]).validate())

        let invalidSize = FixtureManifestEntry(
            id: "bad-size",
            kind: .solidColor,
            width: 0,
            height: 4,
            colors: ["#000000"],
            purpose: "bad size"
        )
        XCTAssertThrowsError(try FixtureManifest(fixtures: [invalidSize]).validate())
    }

    func testDecodingRejectsUnknownPattern() {
        let json = """
        {
          "schemaVersion": 1,
          "generatorVersion": "1.0.0",
          "generatedBy": "test",
          "referenceDirectory": "reference",
          "fixtures": [
            {
              "id": "unknown",
              "kind": "notAPattern",
              "width": 4,
              "height": 4,
              "seed": 0,
              "colors": ["#000000"],
              "purpose": "unknown"
            }
          ]
        }
        """
        XCTAssertThrowsError(try FixtureManifest.decode(Data(json.utf8)))
    }

    func testColoursEncodeAsHexStrings() throws {
        let data = try FixtureCatalog.manifest.encodedJSON()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"#E8D5C4\""))
        XCTAssertFalse(json.contains("red"))
    }

    func testReferenceFilesAreDeclaredAndUnique() {
        let files = FixtureCatalog.fixtures.compactMap(\.entry.referenceFile)
        XCTAssertEqual(files.count, FixtureCatalog.fixtures.count)
        XCTAssertEqual(Set(files).count, files.count)
        for entry in FixtureCatalog.manifest.fixtures {
            XCTAssertEqual(entry.referenceSHA256?.count ?? 0, 64, entry.id)
        }
    }

    func testAuthorizedSampleManifestValidation() throws {
        let sample = AuthorizedSample(
            id: "sample-1",
            fileName: "portrait-01.jpg",
            category: .portrait,
            skinTone: .iv,
            license: "written-consent-2026-01",
            authorizedBy: "project-owner",
            addedAt: "2026-01-01T00:00:00Z"
        )
        var manifest = AuthorizedSampleManifest(
            description: "authorized samples (not committed)",
            samples: [sample]
        )
        try manifest.validate()

        manifest.samples = [
            AuthorizedSample(
                id: "sample-2",
                fileName: "../escape.jpg",
                category: .portrait,
                license: "x",
                authorizedBy: "y",
                addedAt: "2026-01-01T00:00:00Z"
            )
        ]
        XCTAssertThrowsError(try manifest.validate())
    }

    func testSkinToneBands() {
        XCTAssertEqual(SkinToneBand.allCases.map(\.roman), ["I", "II", "III", "IV", "V", "VI"])
    }
}
