import SwiftUI
import XCTest
import StyleToneUI

final class DesignTokensTests: XCTestCase {
    private var allPalettes: [SemanticPalette] {
        [.dark, .light, .darkHighContrast, .lightHighContrast]
    }

    func testEveryPaletteDefinesEveryToken() {
        let expected = Set(ColorToken.allCases)
        for palette in allPalettes {
            XCTAssertEqual(
                palette.definedTokens,
                expected,
                "Missing tokens in \(palette.mode.rawValue)/\(palette.contrast.rawValue)"
            )
        }
    }

    func testPhotoBackgroundIsEighteenPercentNeutralGrey() {
        for palette in allPalettes {
            let photoBackground = palette[.photoBackground]
            XCTAssertEqual(photoBackground.red, 0.18, accuracy: 0.001)
            XCTAssertEqual(photoBackground.green, 0.18, accuracy: 0.001)
            XCTAssertEqual(photoBackground.blue, 0.18, accuracy: 0.001)
            XCTAssertEqual(photoBackground.hexString, "#2E2E2E")
        }
    }

    func testConveniencePalettesMatchFactory() {
        XCTAssertEqual(SemanticPalette.dark.mode, .dark)
        XCTAssertEqual(SemanticPalette.dark.contrast, .standard)
        XCTAssertEqual(SemanticPalette.light.mode, .light)
        XCTAssertEqual(SemanticPalette.darkHighContrast.contrast, .increased)
        XCTAssertEqual(SemanticPalette.lightHighContrast.mode, .light)
        XCTAssertEqual(SemanticPalette.lightHighContrast.contrast, .increased)
    }

    func testRGBColorClampsOutOfRangeComponents() {
        let color = RGBColor(red: -1, green: 0.5, blue: 2)
        XCTAssertEqual(color.red, 0)
        XCTAssertEqual(color.green, 0.5)
        XCTAssertEqual(color.blue, 1)
    }

    func testRGBColorHexRoundTrip() {
        XCTAssertEqual(RGBColor(hex: 0xDFA76C).hexString, "#DFA76C")
        XCTAssertEqual(RGBColor(white: 0.5).hexString, "#808080")
        XCTAssertEqual(RGBColor(white: 0).hexString, "#000000")
        XCTAssertEqual(RGBColor(white: 1).hexString, "#FFFFFF")
    }

    func testRelativeLuminanceBounds() {
        XCTAssertEqual(RGBColor(white: 0).relativeLuminance, 0, accuracy: 0.0001)
        XCTAssertEqual(RGBColor(white: 1).relativeLuminance, 1, accuracy: 0.0001)
        let mid = RGBColor(white: 0.5).relativeLuminance
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testContrastRatioIsSymmetricAndBounded() {
        let black = RGBColor(white: 0)
        let white = RGBColor(white: 1)
        XCTAssertEqual(black.contrastRatio(with: white), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrastRatio(with: black), 21, accuracy: 0.01)
        XCTAssertEqual(black.contrastRatio(with: black), 1, accuracy: 0.0001)
    }

    func testBlendCompositesOverBackground() {
        let foreground = RGBColor(white: 1)
        let background = RGBColor(white: 0)
        let half = foreground.blended(over: background, opacity: 0.5)
        XCTAssertEqual(half.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(foreground.blended(over: background, opacity: 0), background)
    }

    func testSpacingScaleIsStrictlyIncreasing() {
        let spacing = SpacingTokens.standard
        let values = [
            spacing.xxs,
            spacing.xs,
            spacing.sm,
            spacing.md,
            spacing.lg,
            spacing.xl,
            spacing.xxl,
            spacing.xxxl,
        ]
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertGreaterThan(spacing.screenHorizontal, spacing.md)
        XCTAssertGreaterThan(spacing.sectionGap, spacing.lg)
    }

    func testRadiusScaleIsStrictlyIncreasing() {
        let radii = RadiusTokens.standard
        let values = [radii.small, radii.medium, radii.large, radii.extraLarge]
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertGreaterThanOrEqual(radii.control, radii.small)
        XCTAssertGreaterThanOrEqual(radii.card, radii.control)
    }

    func testLayoutMetricsMeetAccessibilityBaseline() {
        let metrics = LayoutMetrics.standard
        XCTAssertGreaterThanOrEqual(metrics.minTouchTarget, 44)
        XCTAssertGreaterThanOrEqual(metrics.controlHeight, metrics.minTouchTarget)
        XCTAssertGreaterThan(metrics.scrimOpacity, 0)
        XCTAssertLessThan(metrics.scrimOpacity, 1)
        XCTAssertGreaterThan(metrics.toastMaxWidth, 0)
    }

    func testTypographyCoversEverySemanticStyle() {
        let typography = TypographyTokens.standard
        for style in TextStyle.allCases {
            _ = typography.font(style)
            _ = typography.lineSpacing(style)
            _ = typography.baseTextStyle(style)
        }
    }

    func testThemeResolvesRequestedMode() {
        XCTAssertEqual(StyleToneTheme.dark.mode, .dark)
        XCTAssertEqual(StyleToneTheme.light.mode, .light)
        XCTAssertEqual(StyleToneTheme.darkHighContrast.contrast, .increased)
        XCTAssertEqual(StyleToneTheme.dark.colorScheme, .dark)
        XCTAssertEqual(StyleToneTheme.light.colorScheme, .light)
    }

    func testThemeColorsComeFromPalette() {
        let theme = StyleToneTheme.dark
        XCTAssertGreaterThan(
            theme.palette[.accent].contrastRatio(with: theme.palette[.background]),
            3
        )
        XCTAssertEqual(theme.spacing.xxs, SpacingTokens.standard.xxs)
        XCTAssertEqual(theme.metrics.minTouchTarget, 44)
    }
}
