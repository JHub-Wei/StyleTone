import SwiftUI

/// Empty state shown before the first pair exists.
@MainActor
struct PairingEmptyStateView: View {
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            slotsPreview

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(verbatim: PairingCopy.emptyTitle.text)
                    .styleToneText(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: PairingCopy.emptyMessage.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: PairingCopy.emptyHint.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.spacing.lg)
        .background(
            theme.color(.surface),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(
                    theme.color(.border),
                    style: StrokeStyle(
                        lineWidth: theme.metrics.hairline,
                        dash: [6, 4]
                    )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.emptyState.rawValue)
    }

    private var slotsPreview: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            PhotoCanvas(
                image: nil,
                aspectRatio: 4.0 / 5.0,
                emptyTitle: PairingCopy.originalTitle.text,
                accessibilityID: PairingAccessibilityID.emptyPhoto(.original).rawValue
            )

            Image(systemName: "arrow.right")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            PhotoCanvas(
                image: nil,
                aspectRatio: 4.0 / 5.0,
                emptyTitle: PairingCopy.editedTitle.text,
                accessibilityID: PairingAccessibilityID.emptyPhoto(.edited).rawValue
            )
        }
    }
}
