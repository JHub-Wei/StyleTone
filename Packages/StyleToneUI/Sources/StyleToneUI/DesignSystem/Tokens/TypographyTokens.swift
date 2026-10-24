import SwiftUI

/// Semantic text styles. Components must use these instead of fixed-size fonts
/// so Dynamic Type works without per-screen changes.
public enum TextStyle: String, CaseIterable, Sendable {
    case display
    case screenTitle
    case sectionTitle
    case body
    case label
    case value
    case caption
    case button
}

/// Typography scale built exclusively on system text styles.
public struct TypographyTokens: Sendable, Hashable {
    public init() {}

    public static let standard = TypographyTokens()

    /// Font for a semantic text style. Every font derives from a system text
    /// style, so it scales with the user's Dynamic Type setting.
    public func font(_ style: TextStyle) -> Font {
        switch style {
        case .display:
            return .system(.largeTitle, design: .default, weight: .semibold)
        case .screenTitle:
            return .system(.title2, design: .default, weight: .semibold)
        case .sectionTitle:
            return .system(.headline, design: .default, weight: .semibold)
        case .body:
            return .system(.body)
        case .label:
            return .system(.subheadline, design: .default, weight: .medium)
        case .value:
            return .system(.subheadline, design: .default, weight: .medium).monospacedDigit()
        case .caption:
            return .system(.footnote)
        case .button:
            return .system(.headline, design: .default, weight: .semibold)
        }
    }

    /// Extra line spacing for a style, in points.
    public func lineSpacing(_ style: TextStyle) -> CGFloat {
        switch style {
        case .body: return 3
        case .caption: return 1
        case .display, .screenTitle, .sectionTitle, .label, .value, .button: return 0
        }
    }

    /// The system text style a scaled metric should track for a semantic style.
    public func baseTextStyle(_ style: TextStyle) -> Font.TextStyle {
        switch style {
        case .display: return .largeTitle
        case .screenTitle: return .title2
        case .sectionTitle: return .headline
        case .body: return .body
        case .label: return .subheadline
        case .value: return .subheadline
        case .caption: return .footnote
        case .button: return .headline
        }
    }
}

private struct StyleToneTextModifier: ViewModifier {
    let style: TextStyle
    let colorToken: ColorToken

    @Environment(\.styleToneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.typography.font(style))
            .lineSpacing(theme.typography.lineSpacing(style))
            .foregroundStyle(theme.color(colorToken))
    }
}

public extension View {
    /// Applies a semantic font, line spacing and token colour in one step.
    func styleToneText(_ style: TextStyle, color: ColorToken = .textPrimary) -> some View {
        modifier(StyleToneTextModifier(style: style, colorToken: color))
    }
}
