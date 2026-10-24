import StyleToneCore
import SwiftUI

/// Progress counter, grade mix and the 3/5/8 target selector.
@MainActor
struct PairingProgressHeader: View {
    let progress: PairingProgress
    let target: PairingTarget
    let isEnabled: Bool
    let onSelectTarget: @MainActor (PairingTarget) -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            counterRow
            progressBar
            countsRow
            targetRow
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
    }

    // MARK: - Counter

    private var counterRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.md) {
            Text(verbatim: progress.label)
                .styleToneText(.screenTitle, color: .textPrimary)
                .accessibilityIdentifier(
                    PairingAccessibilityID.progressValue.rawValue
                )

            Text(verbatim: PairingCopy.progressCaption.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bar

    private var progressBar: some View {
        ProgressView(value: progress.fraction)
            .progressViewStyle(.linear)
            .tint(theme.color(.accent))
            .accessibilityLabel(
                Text(verbatim: PairingCopy.progressAccessibilityLabel.text)
            )
            .accessibilityValue(Text(verbatim: progress.label))
            .accessibilityIdentifier(PairingAccessibilityID.progress.rawValue)
    }

    // MARK: - Counts

    private var countsRow: some View {
        HStack(spacing: theme.spacing.md) {
            countChip(
                count: progress.good,
                label: PairingCopy.countGood.text,
                accessibilityLabel: PairingCopy.countGoodAccessibility.text,
                token: .success,
                identifier: PairingAccessibilityID.countsGood
            )

            countChip(
                count: progress.warning,
                label: PairingCopy.countWarning.text,
                accessibilityLabel: PairingCopy.countWarningAccessibility.text,
                token: .warning,
                identifier: PairingAccessibilityID.countsWarning
            )

            countChip(
                count: progress.rejected,
                label: PairingCopy.countRejected.text,
                accessibilityLabel: PairingCopy.countRejectedAccessibility.text,
                token: .error,
                identifier: PairingAccessibilityID.countsRejected
            )

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.counts.rawValue)
    }

    private func countChip(
        count: Int,
        label: String,
        accessibilityLabel: String,
        token: ColorToken,
        identifier: AccessibilityID
    ) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Circle()
                .fill(theme.color(token))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(verbatim: "\(count)")
                .font(theme.typography.font(.value))
                .foregroundStyle(theme.color(.textPrimary))

            Text(verbatim: label)
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textSecondary))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(accessibilityLabel): \(count)"))
        .accessibilityIdentifier(identifier.rawValue)
    }

    // MARK: - Target selector

    private var targetRow: some View {
        HStack(spacing: theme.spacing.sm) {
            Text(verbatim: PairingCopy.targetLabel.text)
                .styleToneText(.caption, color: .textSecondary)

            ForEach(PairingTarget.allCases) { option in
                targetButton(option)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.targetPicker.rawValue)
    }

    private func targetButton(_ option: PairingTarget) -> some View {
        let isSelected = option == target
        return Button {
            onSelectTarget(option)
        } label: {
            Text(verbatim: option.label)
                .font(theme.typography.font(.label))
                .foregroundStyle(
                    isSelected ? theme.color(.onAccent) : theme.color(.textPrimary)
                )
                .frame(minWidth: 44, minHeight: 36)
                .background(
                    isSelected
                        ? theme.color(.accent)
                        : theme.color(.surfacePressed),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text(verbatim: PairingCopy.targetTitle(option).text))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(PairingAccessibilityID.target(option).rawValue)
    }
}
