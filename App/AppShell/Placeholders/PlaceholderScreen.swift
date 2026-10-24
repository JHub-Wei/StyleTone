import SwiftUI
import StyleToneUI

/// Shared scaffold for placeholder destinations.
///
/// It demonstrates the design system (display type, secondary copy, section
/// spacing, accessibility identifiers) without implementing business logic.
struct PlaceholderScreen<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let screen: AccessibilityScreen
    private let content: Content

    @Environment(\.styleToneTheme) private var theme

    init(
        title: String,
        subtitle: String,
        screen: AccessibilityScreen,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.screen = screen
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text(verbatim: title)
                        .styleToneText(.display)

                    Text(verbatim: subtitle)
                        .styleToneText(.body, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content

                PlaceholderBadge()
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.screenVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            theme.color(.background)
                .ignoresSafeArea()
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID(screen, "root").rawValue)
    }
}

private struct PlaceholderBadge: View {
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: "hammer")
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(verbatim: ShellCopy.placeholderBadge)
                .font(theme.typography.font(.caption))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.color(.textTertiary))
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xs)
        .overlay {
            Capsule()
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}
