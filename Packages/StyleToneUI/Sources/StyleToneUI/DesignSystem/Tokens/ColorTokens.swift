import SwiftUI

/// The visual appearance a palette is designed for.
public enum ThemeMode: String, CaseIterable, Sendable {
    case dark
    case light
}

/// The accessibility contrast level a palette is designed for.
public enum ContrastLevel: String, CaseIterable, Sendable {
    case standard
    case increased
}

/// Semantic colour tokens.
///
/// Feature code uses these tokens instead of constructing colours, so dark
/// mode and increased contrast keep working without per-screen changes.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case surface
    case surfaceElevated
    case surfacePressed
    case photoBackground
    case textPrimary
    case textSecondary
    case textTertiary
    case accent
    case accentPressed
    case onAccent
    case border
    case borderStrong
    case success
    case warning
    case error
    case errorPressed
    case onError
    case scrim
    case disabledBackground
    case onDisabled
    case focusRing
    case sliderTrack
    case onPhoto
    case onPhotoSecondary
}

/// A complete semantic palette for one theme mode and contrast level.
///
/// The default product appearance is dark. Light and increased-contrast
/// palettes exist so the same components remain usable when the system asks
/// for them.
public struct SemanticPalette: Sendable {
    public let mode: ThemeMode
    public let contrast: ContrastLevel
    private let values: [ColorToken: RGBColor]

    init(mode: ThemeMode, contrast: ContrastLevel, values: [ColorToken: RGBColor]) {
        self.mode = mode
        self.contrast = contrast
        self.values = values
    }

    /// The resolved value for `token`.
    ///
    /// Every palette defines every token; the magenta fallback is a visible
    /// development signal and is covered by `DesignTokensTests`.
    public subscript(token: ColorToken) -> RGBColor {
        values[token] ?? RGBColor(red: 1, green: 0, blue: 1)
    }

    /// SwiftUI colour for `token`.
    public func color(_ token: ColorToken) -> Color {
        Color(self[token])
    }

    /// Tokens this palette explicitly defines.
    public var definedTokens: Set<ColorToken> {
        Set(values.keys)
    }

    public static func palette(mode: ThemeMode, contrast: ContrastLevel) -> SemanticPalette {
        switch (mode, contrast) {
        case (.dark, .standard): return darkStandard
        case (.dark, .increased): return darkIncreased
        case (.light, .standard): return lightStandard
        case (.light, .increased): return lightIncreased
        }
    }

    /// Dark appearance with the standard contrast baseline.
    public static var dark: SemanticPalette {
        palette(mode: .dark, contrast: .standard)
    }

    /// Light appearance. The app ships dark-first; this keeps components
    /// adaptable when the host asks for light mode.
    public static var light: SemanticPalette {
        palette(mode: .light, contrast: .standard)
    }

    /// Dark appearance for the system's increased-contrast setting.
    public static var darkHighContrast: SemanticPalette {
        palette(mode: .dark, contrast: .increased)
    }

    /// Light appearance for the system's increased-contrast setting.
    public static var lightHighContrast: SemanticPalette {
        palette(mode: .light, contrast: .increased)
    }
}

// MARK: - Palettes

private extension SemanticPalette {
    /// Darkroom baseline: near-black chrome, warm bronze accent, neutral text.
    static let darkStandard = SemanticPalette(
        mode: .dark,
        contrast: .standard,
        values: [
            .background: RGBColor(hex: 0x0C0D10),
            .surface: RGBColor(hex: 0x14161A),
            .surfaceElevated: RGBColor(hex: 0x1C1F25),
            .surfacePressed: RGBColor(hex: 0x272B33),
            // Frozen UI contract: photo canvases sit on 18% neutral grey.
            .photoBackground: RGBColor(white: 0.18),
            .onPhoto: RGBColor(hex: 0xF2F3F5),
            .onPhotoSecondary: RGBColor(hex: 0xC9CED6),
            .textPrimary: RGBColor(hex: 0xF4F5F7),
            .textSecondary: RGBColor(hex: 0xB6BBC5),
            .textTertiary: RGBColor(hex: 0x8A919D),
            .accent: RGBColor(hex: 0xDFA76C),
            .accentPressed: RGBColor(hex: 0xC58C50),
            .onAccent: RGBColor(hex: 0x14161A),
            .border: RGBColor(hex: 0x2A2F37),
            .borderStrong: RGBColor(hex: 0x3E4550),
            .success: RGBColor(hex: 0x5BD6A2),
            .warning: RGBColor(hex: 0xF2C66D),
            .error: RGBColor(hex: 0xFF8A8A),
            .errorPressed: RGBColor(hex: 0xE06B6B),
            .onError: RGBColor(hex: 0x1B0D0D),
            .scrim: RGBColor(hex: 0x000000),
            .disabledBackground: RGBColor(hex: 0x22262D),
            .onDisabled: RGBColor(hex: 0x9AA1AC),
            .focusRing: RGBColor(hex: 0x8FB4FF),
            .sliderTrack: RGBColor(hex: 0x3A414C),
        ]
    )

    static let darkIncreased = SemanticPalette(
        mode: .dark,
        contrast: .increased,
        values: [
            .background: RGBColor(hex: 0x000000),
            .surface: RGBColor(hex: 0x0E1014),
            .surfaceElevated: RGBColor(hex: 0x181B21),
            .surfacePressed: RGBColor(hex: 0x242830),
            .photoBackground: RGBColor(white: 0.18),
            .onPhoto: RGBColor(hex: 0xFFFFFF),
            .onPhotoSecondary: RGBColor(hex: 0xE2E6EC),
            .textPrimary: RGBColor(hex: 0xFFFFFF),
            .textSecondary: RGBColor(hex: 0xE4E7EC),
            .textTertiary: RGBColor(hex: 0xCBD1D9),
            .accent: RGBColor(hex: 0xFFC98A),
            .accentPressed: RGBColor(hex: 0xE8AF6B),
            .onAccent: RGBColor(hex: 0x000000),
            .border: RGBColor(hex: 0x5A6270),
            .borderStrong: RGBColor(hex: 0x8B93A1),
            .success: RGBColor(hex: 0x8DF0C2),
            .warning: RGBColor(hex: 0xFFD88A),
            .error: RGBColor(hex: 0xFFB3B3),
            .errorPressed: RGBColor(hex: 0xFF9A9A),
            .onError: RGBColor(hex: 0x000000),
            .scrim: RGBColor(hex: 0x000000),
            .disabledBackground: RGBColor(hex: 0x262A31),
            .onDisabled: RGBColor(hex: 0xB6BCC6),
            .focusRing: RGBColor(hex: 0xBDD3FF),
            .sliderTrack: RGBColor(hex: 0x59616E),
        ]
    )

    static let lightStandard = SemanticPalette(
        mode: .light,
        contrast: .standard,
        values: [
            .background: RGBColor(hex: 0xF5F6F8),
            .surface: RGBColor(hex: 0xFFFFFF),
            .surfaceElevated: RGBColor(hex: 0xFFFFFF),
            .surfacePressed: RGBColor(hex: 0xE9EBEF),
            .photoBackground: RGBColor(white: 0.18),
            .onPhoto: RGBColor(hex: 0xF2F3F5),
            .onPhotoSecondary: RGBColor(hex: 0xC9CED6),
            .textPrimary: RGBColor(hex: 0x15171B),
            .textSecondary: RGBColor(hex: 0x4E5560),
            .textTertiary: RGBColor(hex: 0x626A76),
            .accent: RGBColor(hex: 0x9A5B1C),
            .accentPressed: RGBColor(hex: 0x7C4813),
            .onAccent: RGBColor(hex: 0xFFFFFF),
            .border: RGBColor(hex: 0xD9DCE2),
            .borderStrong: RGBColor(hex: 0xAEB4BE),
            .success: RGBColor(hex: 0x1F7A52),
            .warning: RGBColor(hex: 0x8A5A00),
            .error: RGBColor(hex: 0xB3261E),
            .errorPressed: RGBColor(hex: 0x8C1D18),
            .onError: RGBColor(hex: 0xFFFFFF),
            .scrim: RGBColor(hex: 0x000000),
            .disabledBackground: RGBColor(hex: 0xE4E6EA),
            .onDisabled: RGBColor(hex: 0x6E7580),
            .focusRing: RGBColor(hex: 0x1A5CC8),
            .sliderTrack: RGBColor(hex: 0xC7CBD3),
        ]
    )

    static let lightIncreased = SemanticPalette(
        mode: .light,
        contrast: .increased,
        values: [
            .background: RGBColor(hex: 0xFFFFFF),
            .surface: RGBColor(hex: 0xFFFFFF),
            .surfaceElevated: RGBColor(hex: 0xFFFFFF),
            .surfacePressed: RGBColor(hex: 0xEDEEF1),
            .photoBackground: RGBColor(white: 0.18),
            .onPhoto: RGBColor(hex: 0xFFFFFF),
            .onPhotoSecondary: RGBColor(hex: 0xE2E6EC),
            .textPrimary: RGBColor(hex: 0x000000),
            .textSecondary: RGBColor(hex: 0x2B3038),
            .textTertiary: RGBColor(hex: 0x444A53),
            .accent: RGBColor(hex: 0x6E3C00),
            .accentPressed: RGBColor(hex: 0x552E00),
            .onAccent: RGBColor(hex: 0xFFFFFF),
            .border: RGBColor(hex: 0x7A808A),
            .borderStrong: RGBColor(hex: 0x4F555E),
            .success: RGBColor(hex: 0x0C5236),
            .warning: RGBColor(hex: 0x5E3C00),
            .error: RGBColor(hex: 0x8C1D18),
            .errorPressed: RGBColor(hex: 0x6E1512),
            .onError: RGBColor(hex: 0xFFFFFF),
            .scrim: RGBColor(hex: 0x000000),
            .disabledBackground: RGBColor(hex: 0xD9DCE1),
            .onDisabled: RGBColor(hex: 0x5A616B),
            .focusRing: RGBColor(hex: 0x003C9E),
            .sliderTrack: RGBColor(hex: 0x737A85),
        ]
    )
}
