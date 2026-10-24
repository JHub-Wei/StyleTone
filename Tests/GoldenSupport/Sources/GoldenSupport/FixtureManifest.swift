import Foundation
import StyleToneCore

/// The synthetic pattern families supported by the fixture renderer.
public enum SyntheticPattern: String, Codable, Sendable, CaseIterable {
    /// A single flat colour.
    case solidColor
    /// A linear ramp between two colours.
    case linearGradient
    /// A two-colour checkerboard.
    case checkerboard
    /// A grid of colour patches (ColourChecker or skin tone swatches).
    case colorChart
    /// Deterministic SplitMix64 noise around a base colour.
    case noise
    /// A straight vertical edge between two colours.
    case verticalEdge
    /// A background with straight horizontal and vertical lines.
    case grid
    /// A symmetric cartoon face outline (never a photograph).
    case faceSilhouette
}

/// Axis used by ``SyntheticPattern/linearGradient``.
public enum GradientAxis: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

/// One fixture description. This is the JSON shape committed in
/// `Fixtures/manifest.json` and the Swift data generated from it.
public struct FixtureManifestEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SyntheticPattern
    public var width: Int
    public var height: Int
    public var seed: UInt64
    /// Colours in `#RRGGBB` form; the order is kind-specific and documented in
    /// `Fixtures/README.md`.
    public var colors: [String]
    public var axis: GradientAxis?
    public var cellSize: Int?
    public var spacing: Int?
    public var lineWidth: Int?
    public var edgeX: Int?
    public var columns: Int?
    public var amplitude: Int?
    public var purpose: String
    /// Reference PNG file name, relative to `Fixtures/reference`.
    public var referenceFile: String?
    /// SHA-256 of the reference PNG bytes.
    public var referenceSHA256: String?

    public init(
        id: String,
        kind: SyntheticPattern,
        width: Int,
        height: Int,
        seed: UInt64 = 0,
        colors: [String],
        axis: GradientAxis? = nil,
        cellSize: Int? = nil,
        spacing: Int? = nil,
        lineWidth: Int? = nil,
        edgeX: Int? = nil,
        columns: Int? = nil,
        amplitude: Int? = nil,
        purpose: String,
        referenceFile: String? = nil,
        referenceSHA256: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.height = height
        self.seed = seed
        self.colors = colors
        self.axis = axis
        self.cellSize = cellSize
        self.spacing = spacing
        self.lineWidth = lineWidth
        self.edgeX = edgeX
        self.columns = columns
        self.amplitude = amplitude
        self.purpose = purpose
        self.referenceFile = referenceFile
        self.referenceSHA256 = referenceSHA256
    }

    public var pixelSize: PixelSize {
        PixelSize(width: width, height: height)
    }

    /// Parsed colours, dropping any invalid hex strings. Rendering validates
    /// strictly and reports the bad entry instead of dropping silently.
    public var rgbColors: [RGB8] {
        colors.compactMap(RGB8.init(hex:))
    }
}

/// The committed fixture catalog document (`Fixtures/manifest.json`).
public struct FixtureManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let currentGeneratorVersion = "1.0.0"

    public var schemaVersion: Int
    public var generatorVersion: String
    public var generatedBy: String
    /// Directory name, relative to `Fixtures`, holding the reference PNGs.
    public var referenceDirectory: String
    public var fixtures: [FixtureManifestEntry]

    public init(
        schemaVersion: Int = FixtureManifest.currentSchemaVersion,
        generatorVersion: String = FixtureManifest.currentGeneratorVersion,
        generatedBy: String = "Tests/GoldenSupport/Tools/generate_fixtures.py",
        referenceDirectory: String = "reference",
        fixtures: [FixtureManifestEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatorVersion = generatorVersion
        self.generatedBy = generatedBy
        self.referenceDirectory = referenceDirectory
        self.fixtures = fixtures
    }

    public func fixture(id: String) -> FixtureManifestEntry? {
        fixtures.first { $0.id == id }
    }

    /// Structural validation; rendering validates the kind-specific parameters.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GoldenSupportError.invalidManifest(
                reason: "unsupported schemaVersion \(schemaVersion)"
            )
        }
        guard !generatorVersion.isEmpty, !referenceDirectory.isEmpty else {
            throw GoldenSupportError.invalidManifest(reason: "generator metadata is empty")
        }
        let identifiers = Set(fixtures.map(\.id))
        guard identifiers.count == fixtures.count else {
            throw GoldenSupportError.invalidManifest(reason: "fixture ids are not unique")
        }
        for entry in fixtures {
            guard !entry.id.isEmpty else {
                throw GoldenSupportError.invalidManifest(reason: "fixture id is empty")
            }
            guard entry.width > 0, entry.height > 0 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "fixture '\(entry.id)' has invalid dimensions"
                )
            }
            guard !entry.colors.isEmpty else {
                throw GoldenSupportError.invalidManifest(
                    reason: "fixture '\(entry.id)' has no colours"
                )
            }
            guard entry.rgbColors.count == entry.colors.count else {
                throw GoldenSupportError.invalidManifest(
                    reason: "fixture '\(entry.id)' has an invalid #RRGGBB colour"
                )
            }
        }
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> FixtureManifest {
        try JSONDecoder().decode(FixtureManifest.self, from: data)
    }
}

/// A manifest entry bound to the renderer, ready to produce pixels.
public struct SyntheticFixture: Sendable, Equatable, Identifiable {
    public let entry: FixtureManifestEntry

    public init(entry: FixtureManifestEntry) {
        self.entry = entry
    }

    public var id: String { entry.id }
    public var kind: SyntheticPattern { entry.kind }
    public var pixelSize: PixelSize { entry.pixelSize }
    public var referenceFile: String? { entry.referenceFile }

    /// Renders deterministic straight-alpha sRGB pixels.
    public func render() throws -> PixelBuffer {
        try FixtureRenderer.render(entry)
    }

    /// Renders and wraps the pixels in the Core exchange type.
    public func imageAsset() throws -> ImageAsset {
        try render().makeImageAsset()
    }

    /// Renders and encodes the fixture as PNG.
    public func pngData() throws -> Data {
        try render().pngData()
    }
}

/// The ten built-in fixtures. Use `FixtureCatalog.fixture(id:)` or iterate
/// `FixtureCatalog.fixtures`; the catalog is compile-time data and needs no
/// bundle resource or filesystem access.
public enum FixtureCatalog {
    public static let schemaVersion = FixtureManifest.currentSchemaVersion
    public static let generatorVersion = FixtureManifest.currentGeneratorVersion
    public static let generatedBy = "Tests/GoldenSupport/Tools/generate_fixtures.py"
    public static let referenceDirectory = "reference"

    public static let fixtures: [SyntheticFixture] = FixtureCatalogData.entries.map {
        SyntheticFixture(entry: $0)
    }

    public static var manifest: FixtureManifest {
        FixtureManifest(
            schemaVersion: schemaVersion,
            generatorVersion: generatorVersion,
            generatedBy: generatedBy,
            referenceDirectory: referenceDirectory,
            fixtures: FixtureCatalogData.entries
        )
    }

    public static func fixture(id: String) throws -> SyntheticFixture {
        guard let fixture = fixtures.first(where: { $0.id == id }) else {
            throw GoldenSupportError.invalidFixture(id: id, reason: "no fixture with this id")
        }
        return fixture
    }

    public static func fixtures(for kind: SyntheticPattern) -> [SyntheticFixture] {
        fixtures.filter { $0.kind == kind }
    }
}
