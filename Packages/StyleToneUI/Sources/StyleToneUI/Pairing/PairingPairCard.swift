import StyleToneCore
import SwiftUI

/// One pair card: the two photos, the quality badge and the recovery actions.
@MainActor
struct PairingPairCard: View {
    let row: PairingPairRow
    let isImporting: Bool
    let isEditable: Bool
    let onPick: @MainActor (PairingSlot) -> Void
    let onRemovePhoto: @MainActor (PairingSlot) -> Void
    let onDelete: @MainActor () -> Void
    let onRetry: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    private var pair: PairingPairState { row.pair }

    private var presentation: PairingQualityPresentation {
        PairingQualityPresentation.make(
            for: pair.assessment,
            isComplete: pair.isComplete
        )
    }

    private var isInteractive: Bool {
        isEditable && !isImporting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            header

            HStack(alignment: .top, spacing: theme.spacing.md) {
                slotView(.original)
                slotView(.edited)
            }

            if isImporting {
                importingRow
            }

            qualitySection
        }
        .padding(theme.spacing.lg)
        .background(
            theme.color(.surface),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.pair(row.number).rawValue)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Text(verbatim: "\(PairingCopy.pairLabel.text) \(row.number)")
                .styleToneText(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(
                    PairingAccessibilityID.pairTitle(row.number).rawValue
                )

            Spacer(minLength: 0)

            PairingQualityBadge(
                presentation: presentation,
                accessibilityID: PairingAccessibilityID.quality(pair: row.number).rawValue
            )

            deleteButton
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textSecondary))
                .frame(
                    width: theme.metrics.minTouchTarget,
                    height: theme.metrics.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .opacity(isInteractive ? 1 : 0.5)
        .accessibilityLabel(
            Text(verbatim: "\(PairingCopy.deletePair.text) \(row.number)")
        )
        .accessibilityIdentifier(
            PairingAccessibilityID.deleteButton(pair: row.number).rawValue
        )
    }

    // MARK: - Slots

    private func slotView(_ slot: PairingSlot) -> some View {
        PairingPhotoSlotView(
            slot: slot,
            pairNumber: row.number,
            photo: pair.photo(for: slot),
            needsReselect: pair.needsReselect(for: slot),
            isEnabled: isInteractive,
            onPick: { onPick(slot) },
            onRemove: { onRemovePhoto(slot) }
        )
    }

    private var importingRow: some View {
        HStack(spacing: theme.spacing.sm) {
            ProgressView()
                .tint(theme.color(.accent))

            Text(verbatim: PairingCopy.slotImporting.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            PairingAccessibilityID.importingIndicator(pair: row.number).rawValue
        )
    }

    // MARK: - Quality

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if presentation.kind != .waiting {
                Text(verbatim: presentation.title)
                    .styleToneText(.label, color: presentation.colorToken)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(presentation.messages.indices, id: \.self) { index in
                bullet(presentation.messages[index])
            }

            if presentation.canRetry {
                retryButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(
            PairingAccessibilityID.quality(pair: row.number).rawValue
        )
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            Text(verbatim: "•")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            Text(verbatim: text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .imageScale(.small)
                    .accessibilityHidden(true)

                Text(verbatim: PairingCopy.qualityRetry.text)
                    .font(theme.typography.font(.label))
            }
            .foregroundStyle(theme.color(.accent))
            .padding(.horizontal, theme.spacing.md)
            .frame(minHeight: theme.metrics.minTouchTarget)
            .overlay {
                Capsule()
                    .strokeBorder(
                        theme.color(.borderStrong),
                        lineWidth: theme.metrics.hairline
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel(Text(verbatim: PairingCopy.qualityRetry.text))
        .accessibilityIdentifier(
            PairingAccessibilityID.retryButton(pair: row.number).rawValue
        )
    }
}
