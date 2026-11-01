import GoldenSupport
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

final class CoreImageToneRendererTests: XCTestCase {
    func testNeutralSettingsReturnTheOriginalImage() async throws {
        let image = try MockImageAssetFactory.solid(
            color: RGB8(red: 120, green: 90, blue: 70),
            size: PixelSize(width: 16, height: 16)
        )
        let output = try await CoreImageToneRenderer().applyTone(
            image,
            settings: EditorToneSettings(),
            analysis: .empty(imageSize: image.pixelSize)
        )
        XCTAssertEqual(output.pixelSize, image.pixelSize)
        let before = try PixelBuffer(image: image)
        let after = try PixelBuffer(image: output)
        XCTAssertEqual(before, after)
    }

    func testWarmTemperatureRaisesRedRelativeToBlue() async throws {
        let image = try MockImageAssetFactory.solid(
            color: RGB8(red: 128, green: 128, blue: 128),
            size: PixelSize(width: 16, height: 16)
        )
        let output = try await CoreImageToneRenderer().applyTone(
            image,
            settings: EditorToneSettings(
                tone: ToneParameters(temperature: 0.8),
                finish: .neutral
            ),
            analysis: .empty(imageSize: image.pixelSize)
        )
        let pixels = try PixelBuffer(image: output)
        let center = pixels[8, 8]
        XCTAssertGreaterThan(Int(center.red), Int(center.blue) + 5)
    }

    func testVignetteDarkensCornersMoreThanCenter() async throws {
        let image = try MockImageAssetFactory.solid(
            color: RGB8(red: 160, green: 160, blue: 160),
            size: PixelSize(width: 64, height: 64)
        )
        let output = try await CoreImageToneRenderer().applyTone(
            image,
            settings: EditorToneSettings(
                tone: .neutral,
                finish: FinishParameters(vignette: -0.8)
            ),
            analysis: .empty(imageSize: image.pixelSize)
        )
        let pixels = try PixelBuffer(image: output)
        let center = pixels[32, 32]
        let corner = pixels[1, 1]
        XCTAssertLessThan(
            Int(corner.red) + Int(corner.green) + Int(corner.blue),
            Int(center.red) + Int(center.green) + Int(center.blue) - 15
        )
    }
}
