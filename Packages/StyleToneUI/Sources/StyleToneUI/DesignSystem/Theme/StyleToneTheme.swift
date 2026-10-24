import SwiftUI

/// The complete visual environment for a screen.
///
/// Read it from the environment with `@Environment(\.styleToneTheme)`; do not
/// instantiate one per view. The default is dark, matching the product's
/// darkroom direction. `styleToneThemeProvider()` adapts to the system's
/// colour scheme and contrast settings.
public struct StyleToneTheme: Sendable {
    public let mode: ThemeMode
    public let contrast: ContrastLevel
    public let palette: SemanticPalette
    public let spacing: SpacingTokens
    public let radii: RadiusTokens
    public let metrics: LayoutMetrics
    public let typography: TypographyTokens

    public init(
        mode: ThemeMode = .dark,
        contrast: ContrastLevel = .standard,
        spacing: SpacingTokens = .standard,
        radii: RadiusTokens = .standard,
        metrics: LayoutMetrics = .standard,
        typography: TypographyTokens = .standard
    ) {
        self.mode = mode
        self.contrast = contrast
        self.palette = .palette(mode: mode, contrast: contrast)
        self.spacing = spacing
        self.radii = radii
        self.metrics = metrics
        self.typography = typography
    }

    public static let dark = StyleToneTheme(mode: .dark)
    public static let light = StyleToneTheme(mode: .light)
    public static let darkHighContrast = StyleToneTheme(mode: .dark, contrast: .increased)
    public static let lightHighContrast = StyleToneTheme(mode: .light, contrast: .increased)

    /// SwiftUI colour for a semantic token.
    public func color(_ token: ColorToken) -> Color {
        palette.color(token)
    }

    /// Colour scheme this theme is designed for.
    public var colorScheme: ColorScheme {
        mode == .dark ? .dark : .light
    }
}

private struct StyleToneThemeKey: EnvironmentKey {
    static let defaultValue: StyleToneTheme = .dark
}

public extension EnvironmentValues {
    /// The active design system theme.
    var styleToneTheme: StyleToneTheme {
        get { self[StyleToneThemeKey.self] }
        set { self[StyleToneThemeKey.self] = newValue }
    }
}

private struct StyleToneThemeAdaptationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content.environment(
            \.styleToneTheme,
            StyleToneTheme(
                mode: colorScheme == .light ? .light : .dark,
                contrast: colorSchemeContrast == .increased ? .increased : .standard
            )
        )
    }
}

public extension View {
    /// Injects an explicit theme, useful for previews and tests.
    func styleToneTheme(_ theme: StyleToneTheme) -> some View {
        environment(\.styleToneTheme, theme)
    }

    /// Resolves the theme from the system colour scheme and contrast setting.
    func styleToneThemeProvider() -> some View {
        modifier(StyleToneThemeAdaptationModifier())
    }
}
