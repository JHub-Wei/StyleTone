import XCTest
import StyleToneUI

/// Baseline WCAG checks over the frozen palettes. These run on macOS as part of
/// `swift test` and do not require rendering or a simulator.
final class DesignSystemContrastTests: XCTestCase {
    private var allPalettes: [SemanticPalette] {
        [.dark, .light, .darkHighContrast, .lightHighContrast]
    }

    private func assertContrast(
        _ palette: SemanticPalette,
        _ foreground: ColorToken,
        on background: ColorToken,
        atLeast minimum: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = palette[foreground].contrastRatio(with: palette[background])
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(palette.mode.rawValue)/\(palette.contrast.rawValue): "
                + "\(foreground.rawValue) on \(background.rawValue) = \(ratio)",
            file: file,
            line: line
        )
    }

    func testStandardTextPairsMeetWCAGAA() {
        for palette in [SemanticPalette.dark, .light] {
            assertContrast(palette, .textPrimary, on: .background, atLeast: 7)
            assertContrast(palette, .textSecondary, on: .background, atLeast: 4.5)
            assertContrast(palette, .textTertiary, on: .background, atLeast: 4.5)
            assertContrast(palette, .textPrimary, on: .surfaceElevated, atLeast: 7)
            assertContrast(palette, .onAccent, on: .accent, atLeast: 4.5)
            assertContrast(palette, .onError, on: .error, atLeast: 4.5)
            assertContrast(palette, .error, on: .background, atLeast: 4.5)
            assertContrast(palette, .accent, on: .surface, atLeast: 3)
            assertContrast(palette, .focusRing, on: .background, atLeast: 3)
        }
    }

    func testStandardPressedStatesKeepReadableForeground() {
        for palette in [SemanticPalette.dark, .light] {
            assertContrast(palette, .onAccent, on: .accentPressed, atLeast: 4.5)
            assertContrast(palette, .onError, on: .errorPressed, atLeast: 4.5)
        }
    }

    func testIncreasedContrastPairsAreStronger() {
        for palette in [SemanticPalette.darkHighContrast, .lightHighContrast] {
            assertContrast(palette, .textPrimary, on: .background, atLeast: 7)
            assertContrast(palette, .textSecondary, on: .background, atLeast: 7)
            assertContrast(palette, .textTertiary, on: .background, atLeast: 4.5)
            assertContrast(palette, .onAccent, on: .accent, atLeast: 7)
            assertContrast(palette, .onError, on: .error, atLeast: 7)
            assertContrast(palette, .focusRing, on: .background, atLeast: 4.5)
        }
    }

    func testTextOnPhotoCanvasMeetsMinimum() {
        for palette in allPalettes {
            assertContrast(palette, .onPhoto, on: .photoBackground, atLeast: 7)
            assertContrast(palette, .onPhotoSecondary, on: .photoBackground, atLeast: 4.5)
        }
    }

    func testPhotoBackgroundIsDarkEnoughForLightPhotoOverlays() {
        for palette in allPalettes {
            XCTAssertLessThan(
                palette[.photoBackground].relativeLuminance,
                0.05,
                "Photo canvas should stay darker than mid grey"
            )
        }
    }
}
