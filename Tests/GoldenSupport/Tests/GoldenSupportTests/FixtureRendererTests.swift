import XCTest
@testable import GoldenSupport
import StyleToneCore

final class FixtureRendererTests: XCTestCase {
    func testCatalogContainsTenFixturesAndEveryPatternFamily() {
        XCTAssertEqual(FixtureCatalog.fixtures.count, 10)
        XCTAssertEqual(FixtureCatalog.manifest.fixtures.count, 10)
        let kinds = Set(FixtureCatalog.fixtures.map(\.kind))
        XCTAssertEqual(kinds, Set(SyntheticPattern.allCases))
    }

    func testEveryFixtureRendersExpectedSizeAndOpaquePixels() throws {
        for fixture in FixtureCatalog.fixtures {
            let buffer = try fixture.render()
            XCTAssertEqual(buffer.pixelSize, fixture.pixelSize, fixture.id)
            XCTAssertEqual(buffer.bytes.count, fixture.entry.width * fixture.entry.height * 4)
            for (x, y) in [(0, 0), (buffer.width - 1, buffer.height - 1), (buffer.width / 2, buffer.height / 2)] {
                XCTAssertEqual(buffer[x, y].alpha, 255, "\(fixture.id) alpha at \(x),\(y)")
            }
        }
    }

    func testProbesMatchGeneratedPixelsForEveryFixture() throws {
        for fixture in FixtureCatalog.fixtures {
            let buffer = try fixture.render()
            let probes = try FixtureProbes.colorProbes(for: fixture.entry)
            for probe in probes {
                XCTAssertEqual(
                    buffer[probe.x, probe.y].color,
                    probe.color,
                    "\(fixture.id) probe (\(probe.x), \(probe.y))"
                )
            }
        }
    }

    func testSolidColour() throws {
        let buffer = try FixtureCatalog.fixture(id: "solid.cream").render()
        let expected = try XCTUnwrap(RGB8(hex: "#E8D5C4"))
        XCTAssertEqual(buffer.uniqueColorCount, 1)
        XCTAssertEqual(buffer[0, 0].color, expected)
        XCTAssertEqual(buffer[buffer.width - 1, buffer.height - 1].color, expected)
    }

    func testHorizontalGradientIsMonotonicAndHitsEndpoints() throws {
        let buffer = try FixtureCatalog.fixture(id: "gradient.gray-horizontal").render()
        XCTAssertEqual(buffer[0, 0].color, .black)
        XCTAssertEqual(buffer[buffer.width - 1, 0].color, .white)

        var previous = -1
        for x in 0..<buffer.width {
            let value = Int(buffer[x, buffer.height / 2].red)
            XCTAssertGreaterThanOrEqual(value, previous, "ramp must not go backwards")
            previous = value
        }
    }

    func testVerticalGradientHitsEndpoints() throws {
        let buffer = try FixtureCatalog.fixture(id: "gradient.warm-vertical").render()
        let start = try XCTUnwrap(RGB8(hex: "#F6D7C3"))
        let end = try XCTUnwrap(RGB8(hex: "#402A2A"))
        XCTAssertEqual(buffer[0, 0].color, start)
        XCTAssertEqual(buffer[0, buffer.height - 1].color, end)
        XCTAssertNotEqual(buffer[0, 0].color, buffer[0, buffer.height - 1].color)
    }

    func testCheckerboardAlternatesCells() throws {
        let fixture = try FixtureCatalog.fixture(id: "checkerboard.8px")
        let buffer = try fixture.render()
        let entry = fixture.entry
        XCTAssertEqual(entry.cellSize ?? 0, 8)
        XCTAssertEqual(buffer[0, 0].color, .white)
        XCTAssertEqual(buffer[8, 0].color, RGB8(red: 0x20, green: 0x20, blue: 0x20))
        XCTAssertEqual(buffer[0, 8].color, RGB8(red: 0x20, green: 0x20, blue: 0x20))
        XCTAssertEqual(buffer[8, 8].color, .white)
        XCTAssertEqual(buffer.uniqueColorCount, 2)
    }

    func testColourChartPatchCentres() throws {
        let fixture = try FixtureCatalog.fixture(id: "colorchart.macbeth24")
        let buffer = try fixture.render()
        let entry = fixture.entry
        let columns = try XCTUnwrap(entry.columns)
        let colors = entry.rgbColors
        let rows = (colors.count + columns - 1) / columns
        let patchWidth = (entry.width - 2 * 10 - (columns - 1) * 6) / columns
        let patchHeight = (entry.height - 2 * 10 - (rows - 1) * 6) / rows

        for (index, color) in colors.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = 10 + column * (patchWidth + 6) + patchWidth / 2
            let y = 10 + row * (patchHeight + 6) + patchHeight / 2
            XCTAssertEqual(buffer[x, y].color, color, "patch \(index)")
        }
        XCTAssertEqual(buffer[0, 0].color, RGB8(gray: 128))
    }

    func testNoiseIsDeterministicAndBounded() throws {
        let fixture = try FixtureCatalog.fixture(id: "noise.midgray")
        let first = try fixture.render()
        let second = try fixture.render()
        XCTAssertEqual(first.bytes, second.bytes)
        XCTAssertGreaterThan(first.uniqueColorCount, 100)

        let amplitude = try XCTUnwrap(fixture.entry.amplitude)
        let base = try XCTUnwrap(RGB8(hex: "#808080"))
        var total = 0.0
        for y in 0..<first.height {
            for x in 0..<first.width {
                let pixel = first[x, y]
                for channel in [pixel.red, pixel.green, pixel.blue] {
                    XCTAssertLessThanOrEqual(
                        abs(Int(channel) - Int(base.red)),
                        amplitude,
                        "noise outside amplitude at \(x),\(y)"
                    )
                    total += Double(channel)
                }
            }
        }
        let mean = total / Double(first.pixelCount * 3)
        XCTAssertEqual(mean, Double(base.red), accuracy: 2.0)
    }

    func testDifferentNoiseSeedsDiffer() throws {
        let first = try FixtureCatalog.fixture(id: "noise.midgray").render()
        var entry = try FixtureCatalog.fixture(id: "noise.midgray").entry
        entry.seed = entry.seed &+ 1
        let second = try FixtureRenderer.render(entry)
        XCTAssertNotEqual(first.bytes, second.bytes)
    }

    func testVerticalEdgeSplitsExactly() throws {
        let fixture = try FixtureCatalog.fixture(id: "edge.vertical")
        let buffer = try fixture.render()
        let edgeX = try XCTUnwrap(fixture.entry.edgeX)
        for x in 0..<buffer.width {
            let expected = x < edgeX
                ? RGB8(red: 0x1E, green: 0x1E, blue: 0x1E)
                : RGB8(red: 0xF2, green: 0xF2, blue: 0xF2)
            XCTAssertEqual(buffer[x, buffer.height / 2].color, expected, "x=\(x)")
        }
    }

    func testGridLinesFollowSpacing() throws {
        let fixture = try FixtureCatalog.fixture(id: "grid.tiles")
        let buffer = try fixture.render()
        let entry = fixture.entry
        let spacing = try XCTUnwrap(entry.spacing)
        let lineWidth = try XCTUnwrap(entry.lineWidth)
        let background = entry.rgbColors[0]
        let line = entry.rgbColors[1]

        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let expected = (x % spacing < lineWidth || y % spacing < lineWidth)
                    ? line
                    : background
                XCTAssertEqual(buffer[x, y].color, expected, "grid at \(x),\(y)")
            }
        }
    }

    func testFaceSilhouetteIsSymmetricWithExpectedRegions() throws {
        let fixture = try FixtureCatalog.fixture(id: "face.silhouette")
        let buffer = try fixture.render()
        XCTAssertTrue(FixtureProbes.isMirrorSymmetric(buffer))
        XCTAssertEqual(buffer.uniqueColorCount, 6)
        XCTAssertFalse(FixtureProbes.isMirrorSymmetric(try FixtureCatalog.fixture(id: "grid.tiles").render()))
    }

    func testInvalidParameterCombinationsThrow() {
        let invalidEntries: [FixtureManifestEntry] = [
            FixtureManifestEntry(
                id: "bad.solid",
                kind: .solidColor,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                purpose: "two colours for a solid"
            ),
            FixtureManifestEntry(
                id: "bad.gradient",
                kind: .linearGradient,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                purpose: "missing axis"
            ),
            FixtureManifestEntry(
                id: "bad.checker",
                kind: .checkerboard,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                cellSize: 0,
                purpose: "zero cell"
            ),
            FixtureManifestEntry(
                id: "bad.chart",
                kind: .colorChart,
                width: 8,
                height: 8,
                colors: ["#000000"],
                columns: 0,
                purpose: "zero columns"
            ),
            FixtureManifestEntry(
                id: "bad.noise",
                kind: .noise,
                width: 8,
                height: 8,
                colors: ["#808080"],
                amplitude: 0,
                purpose: "zero amplitude"
            ),
            FixtureManifestEntry(
                id: "bad.edge",
                kind: .verticalEdge,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                edgeX: 8,
                purpose: "edge at width"
            ),
            FixtureManifestEntry(
                id: "bad.grid",
                kind: .grid,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                spacing: 4,
                lineWidth: 4,
                purpose: "line as wide as spacing"
            ),
            FixtureManifestEntry(
                id: "bad.face",
                kind: .faceSilhouette,
                width: 8,
                height: 8,
                colors: ["#000000", "#FFFFFF"],
                purpose: "too few colours"
            )
        ]

        for entry in invalidEntries {
            XCTAssertThrowsError(try FixtureRenderer.render(entry), entry.id) { error in
                guard let goldenError = error as? GoldenSupportError,
                      case .invalidFixture(_, _) = goldenError
                else {
                    XCTFail("expected invalidFixture for \(entry.id), got \(error)")
                    return
                }
            }
        }
    }

    func testFixtureLookup() throws {
        XCTAssertEqual(try FixtureCatalog.fixture(id: "solid.cream").kind, .solidColor)
        XCTAssertThrowsError(try FixtureCatalog.fixture(id: "nope"))
        XCTAssertEqual(FixtureCatalog.fixtures(for: .linearGradient).count, 2)
    }
}
