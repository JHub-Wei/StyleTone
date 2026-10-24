import SwiftUI

/// Loading indicator for inline waits and blocking overlays.
///
/// The message is already-localized text and doubles as the accessibility
/// label. Long-running work owns its own cancellation semantics (WP-17/WP-19);
/// this component is presentation only.
public struct LoadingView: View {
    public enum Style: String, CaseIterable, Sendable {
        /// A card with spinner and message, for empty content areas.
        case inline
        /// A bare spinner, for tight spaces. The message is still read aloud.
        case compact
        /// A scrimmed overlay that covers the presenting screen.
        case overlay
    }

    private let message: String
    private let style: Style
    private let accessibilityID: String

    @Environment(\.styleToneTheme) private var theme

    public init(
        message: String,
        style: Style = .inline,
        accessibilityID: String = AccessibilityID.designSystemLoading.rawValue
    ) {
        self.message = message
        self.style = style
        self.accessibilityID = accessibilityID
    }

    public var body: some View {
        Group {
            switch style {
            case .compact:
                spinner
                    .padding(theme.spacing.sm)
            case .inline:
                card
            case .overlay:
                ZStack {
                    theme.color(.scrim)
                        .opacity(theme.metrics.scrimOpacity)
                        .ignoresSafeArea()
                    card
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: message))
        .accessibilityIdentifier(accessibilityID)
    }

    private var spinner: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(theme.color(.accent))
    }

    private var card: some View {
        HStack(spacing: theme.spacing.md) {
            spinner
            Text(verbatim: message)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(theme.spacing.lg)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
    }
}
