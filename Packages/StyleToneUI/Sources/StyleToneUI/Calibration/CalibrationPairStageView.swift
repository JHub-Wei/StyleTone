import StyleToneCore
import SwiftUI

@MainActor
struct CalibrationPairStageView: View {
    let model: CalibrationViewModel
    let addPairs: (@MainActor () -> Void)?

    @Environment(\.styleToneTheme) private var theme
    @State private var selectedTier: CalibrationPairTier?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            header

            if model.flow.eligiblePairCount == 0 {
                emptyState
            } else {
                pairProgress
            }

            PrimaryButton(
                startTitle,
                systemImage: "wand.and.stars",
                isEnabled: model.flow.canStartComparisons,
                accessibilityID: AccessibilityID.calibrationStartButton.rawValue,
                action: start
            )

            if let addPairs {
                PrimaryButton(
                    CalibrationCopy.text(CalibrationCopy.pairsAdd),
                    systemImage: "plus",
                    role: .secondary,
                    accessibilityID: AccessibilityID.calibrationAddPairsButton.rawValue,
                    action: addPairs
                )
            }

            naturalDefault
        }
        .onAppear {
            if selectedTier == nil {
                selectedTier = model.flow.recommendedTier
            }
        }
        .onChange(of: model.flow.eligiblePairCount) { _, _ in
            selectedTier = model.flow.recommendedTier
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsTitle))
                .styleToneText(.screenTitle)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsSubtitle))
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsNote))
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Image(systemName: "photo.on.rectangle")
                .font(theme.typography.font(.display))
                .foregroundStyle(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsEmptyTitle))
                .styleToneText(.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsEmptyMessage))
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .calibrationCard()
        .accessibilityIdentifier(AccessibilityID.calibrationPairEmpty.rawValue)
    }

    private var pairProgress: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: CalibrationCopy.format(
                    CalibrationCopy.pairsCount,
                    model.flow.eligiblePairCount
                ))
                .styleToneText(.sectionTitle)
                .accessibilityIdentifier(AccessibilityID.calibrationPairCount.rawValue)

                Spacer()

                if let next = model.flow.nextTier {
                    Text(verbatim: CalibrationCopy.format(CalibrationCopy.pairsTarget, next.pairCount))
                        .styleToneText(.caption, color: .textSecondary)
                }
            }

            ProgressView(
                value: Double(min(
                    model.flow.eligiblePairCount,
                    CalibrationLimits.maximumPairCount
                )),
                total: Double(CalibrationLimits.maximumPairCount)
            )
            .progressViewStyle(.linear)
            .tint(theme.color(.accent))
            .accessibilityLabel(Text(verbatim: CalibrationCopy.text(CalibrationCopy.progressLabel)))
            .accessibilityValue(Text(verbatim: CalibrationCopy.format(
                CalibrationCopy.pairsCount,
                model.flow.eligiblePairCount
            )))

            Text(verbatim: CalibrationCopy.format(
                CalibrationCopy.pairsQuality,
                model.flow.goodPairCount,
                model.flow.warningPairCount,
                model.flow.rejectedPairCount
            ))
            .styleToneText(.caption, color: .textSecondary)
            .accessibilityIdentifier(AccessibilityID.calibrationQualitySummary.rawValue)

            if model.flow.recommendedTier == nil {
                Label {
                    Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsInsufficient))
                        .styleToneText(.caption, color: .warning)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(theme.color(.warning))
                }
            }

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsTierHint))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            CalibrationTierSelector(
                eligiblePairs: model.flow.eligiblePairCount,
                recommended: model.flow.recommendedTier,
                selection: $selectedTier
            )
        }
        .calibrationCard()
    }

    private var naturalDefault: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.naturalDefaultNote))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.skipToNaturalDefault()
            } label: {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: "leaf")
                        .accessibilityHidden(true)
                    Text(verbatim: CalibrationCopy.text(CalibrationCopy.naturalDefault))
                        .styleToneText(.label, color: .accent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.calibrationNaturalButton.rawValue)
        }
    }

    private var effectiveTier: CalibrationPairTier? {
        if let selectedTier, model.flow.hasEnoughPairs(for: selectedTier) {
            return selectedTier
        }
        return model.flow.recommendedTier
    }

    private var startTitle: String {
        let count = effectiveTier?.pairCount ?? CalibrationLimits.minimumPairCount
        return CalibrationCopy.format(CalibrationCopy.pairsStart, count)
    }

    private func start() {
        guard let tier = effectiveTier else { return }
        _ = model.beginComparisons(using: tier)
    }
}
