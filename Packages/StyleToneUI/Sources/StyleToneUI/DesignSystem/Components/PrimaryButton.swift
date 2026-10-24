import SwiftUI

/// Primary action button with secondary and destructive variants.
///
/// The title is already-localized text (resolve it with `L10n.resolve` or
/// `String(localized:)`); the design system does not own feature copy.
/// Dynamic Type is supported through semantic fonts and a scaled minimum
/// height, and every button requires an `accessibilityID`.
public struct PrimaryButton: View {
    public enum Role: String, CaseIterable, Sendable {
        case primary
        case secondary
        case destructive
    }

    private let title: String
    private let systemImage: String?
    private let role: Role
    private let isLoading: Bool
    private let isEnabled: Bool
    private let accessibilityID: String
    private let accessibilityHint: String?
    private let action: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .headline) private var scaledMinHeight: CGFloat =
        LayoutMetrics.standard.controlHeight

    public init(
        _ title: String,
        systemImage: String? = nil,
        role: Role = .primary,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        accessibilityID: String,
        accessibilityHint: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accessibilityID = accessibilityID
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, minHeight: scaledMinHeight)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, theme.spacing.sm)
                .overlay {
                    if let borderColor {
                        shape.strokeBorder(borderColor, lineWidth: theme.metrics.hairline)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(
            FilledButtonStyle(
                normalBackground: backgroundColor,
                pressedBackground: pressedBackgroundColor,
                shape: shape
            )
        )
        .disabled(!isEnabled || isLoading)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(Text(verbatim: title))
        .modifier(AccessibilityHintModifier(hint: accessibilityHint))
    }

    private var label: some View {
        ZStack {
            HStack(spacing: theme.spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(theme.typography.font(.button))
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(theme.typography.font(.button))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(foregroundColor)
                    .accessibilityHidden(true)
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
    }

    private var isInteractive: Bool {
        isEnabled && !isLoading
    }

    private var foregroundColor: Color {
        guard isInteractive else { return theme.color(.onDisabled) }
        switch role {
        case .primary: return theme.color(.onAccent)
        case .secondary: return theme.color(.textPrimary)
        case .destructive: return theme.color(.onError)
        }
    }

    private var backgroundColor: Color {
        guard isInteractive else { return theme.color(.disabledBackground) }
        switch role {
        case .primary: return theme.color(.accent)
        case .secondary: return theme.color(.surfaceElevated)
        case .destructive: return theme.color(.error)
        }
    }

    private var pressedBackgroundColor: Color {
        switch role {
        case .primary: return theme.color(.accentPressed)
        case .secondary: return theme.color(.surfacePressed)
        case .destructive: return theme.color(.errorPressed)
        }
    }

    private var borderColor: Color? {
        guard isInteractive, role == .secondary else { return nil }
        return theme.color(.border)
    }
}

private struct FilledButtonStyle: ButtonStyle {
    let normalBackground: Color
    let pressedBackground: Color
    let shape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? pressedBackground : normalBackground,
                in: shape
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AccessibilityHintModifier: ViewModifier {
    let hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(Text(verbatim: hint))
        } else {
            content
        }
    }
}
