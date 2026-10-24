import SwiftUI

/// Single-level undo bar pinned above the home indicator after a deletion.
@MainActor
struct PairingUndoBar: View {
    let backup: PairingDeletionBackup
    let onUndo: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.textSecondary))
                .accessibilityHidden(true)

            Text(verbatim: label)
                .styleToneText(.body, color: .textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onUndo) {
                Text(verbatim: PairingCopy.undoAction.text)
                    .font(theme.typography.font(.button))
                    .foregroundStyle(theme.color(.accent))
                    .padding(.horizontal, theme.spacing.md)
                    .frame(minHeight: theme.metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: PairingCopy.undoAction.text))
            .accessibilityIdentifier(PairingAccessibilityID.undoButton.rawValue)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.sm)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.borderStrong), lineWidth: theme.metrics.hairline)
        }
        .shadow(
            color: theme.color(.scrim).opacity(0.35),
            radius: 12,
            x: 0,
            y: 6
        )
        .padding(.horizontal, theme.spacing.screenHorizontal)
        .padding(.bottom, theme.spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.undoBar.rawValue)
    }

    private var label: String {
        backup.isPairDeletion
            ? PairingCopy.undoPair.text
            : PairingCopy.undoPhoto.text
    }
}
