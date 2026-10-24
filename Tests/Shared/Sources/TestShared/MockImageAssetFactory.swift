import Foundation
import GoldenSupport
import StyleToneCore

/// Image factory for tests that need an `ImageAsset` without touching disk.
///
/// Pure colour, gradient and checkerboard images are the three patterns named
/// in contracts §7.2; `fixture(named:)` exposes the ten committed synthetic
/// fixtures as well.
public enum MockImageAssetFactory {
    public static func solid(
        color: RGB8 = .midGray,
        size: PixelSize = PixelSize(width: 64, height: 64)
    ) throws -> ImageAsset {
        try PixelBuffer(width: size.width, height: size.height, fill: color).makeImageAsset()
    }

    public static func gradient(
        from start: RGB8 = .black,
        to end: RGB8 = .white,
        size: PixelSize = PixelSize(width: 64, height: 32),
        axis: GradientAxis = .horizontal
    ) throws -> ImageAsset {
        let entry = FixtureManifestEntry(
            id: "mock.gradient",
            kind: .linearGradient,
            width: size.width,
            height: size.height,
            colors: [start.hex, end.hex],
            axis: axis,
            purpose: "In-memory gradient mock"
        )
        return try FixtureRenderer.render(entry).makeImageAsset()
    }

    public static func checkerboard(
        light: RGB8 = .white,
        dark: RGB8 = .black,
        cellSize: Int = 8,
        size: PixelSize = PixelSize(width: 64, height: 64)
    ) throws -> ImageAsset {
        let entry = FixtureManifestEntry(
            id: "mock.checkerboard",
            kind: .checkerboard,
            width: size.width,
            height: size.height,
            colors: [light.hex, dark.hex],
            cellSize: cellSize,
            purpose: "In-memory checkerboard mock"
        )
        return try FixtureRenderer.render(entry).makeImageAsset()
    }

    /// One of the ten built-in fixtures, rendered to an `ImageAsset`.
    public static func fixture(named id: String) throws -> ImageAsset {
        try FixtureCatalog.fixture(id: id).imageAsset()
    }

    /// Pixels for one of the ten built-in fixtures.
    public static func fixturePixels(named id: String) throws -> PixelBuffer {
        try FixtureCatalog.fixture(id: id).render()
    }

    /// A tiny image with an intentionally corrupted PNG payload, for decode
    /// failure tests. It is not a valid image.
    public static func corruptedPNGData() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02, 0x03])
    }
}
