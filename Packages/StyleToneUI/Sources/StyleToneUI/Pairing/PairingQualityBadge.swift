import SwiftUI

/// Compact green/yellow/red badge shown in a pair card header.
@MainActor
struct PairingQualityBadge: View {
    let presentation: PairingQualityPresentation
    let accessibilityID: String

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xxs) {
            Image(systemName: presentation.systemImage)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(verbatim: presentation.shortTitle)
                .font(theme.typography.font(.caption))
                .lineLimit(1)
        }
        .foregroundStyle(theme.color(presentation.colorToken))
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xxs)
        .background(
            theme.color(presentation.colorToken).opacity(0.16),
            in: Capsule()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        .accessibilityIdentifier(accessibilityID)
    }
}
