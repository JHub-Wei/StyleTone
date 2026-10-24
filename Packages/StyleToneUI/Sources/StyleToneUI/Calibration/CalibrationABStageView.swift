import StyleToneCore
import SwiftUI

@MainActor
struct CalibrationABStageView: View {
    let model: CalibrationViewModel

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            header
            progress

            if let comparison = model.flow.currentComparison {
                CalibrationABCard(
                    comparison: comparison,
                    chooseA: { model.answerCurrent(choseA: true) },
                    chooseB: { model.answerCurrent(choseA: false) }
                )

                skipCardButton
            }

            if model.flow.canFinishComparisons {
                finishArea
            } else {
                Text(verbatim: CalibrationCopy.format(
                    CalibrationCopy.abFinishHint,
                    model.flow.remainingToFinish
                ))
                .styleToneText(.caption, color: .textSecondary)
            }

            naturalDefault
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.abTitle))
                .styleToneText(.screenTitle)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.abSubtitle))
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: CalibrationCopy.text(CalibrationCopy.abProgressLabel))
                    .styleToneText(.label, color: .textSecondary)

                Spacer()

                Text(verbatim: CalibrationCopy.format(
                    CalibrationCopy.abProgress,
                    model.flow.interactionCount,
                    CalibrationLimits.plannedComparisonCount
                ))
                .styleToneText(.value)
                .accessibilityIdentifier(AccessibilityID.calibrationABProgress.rawValue)
            }

            ProgressView(
                value: Double(model.flow.interactionCount),
                total: Double(CalibrationLimits.plannedComparisonCount)
            )
            .progressViewStyle(.linear)
            .tint(theme.color(.accent))
            .accessibilityLabel(Text(verbatim: CalibrationCopy.text(CalibrationCopy.abProgressLabel)))
            .accessibilityValue(Text(verbatim: CalibrationCopy.format(
                CalibrationCopy.abProgress,
                model.flow.interactionCount,
                CalibrationLimits.plannedComparisonCount
            )))
        }
        .calibrationCard()
    }

    private var skipCardButton: some View {
        Button {
            model.skipCurrentComparison()
        } label: {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "arrow.right.circle")
                    .accessibilityHidden(true)
                Text(verbatim: CalibrationCopy.text(CalibrationCopy.abSkip))
                    .styleToneText(.label, color: .textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.calibrationABSkipButton.rawValue)
        .accessibilityHint(Text(verbatim: CalibrationCopy.text(CalibrationCopy.abSkipHint)))
    }

    private var finishArea: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.abReady))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                CalibrationCopy.text(CalibrationCopy.abFinish),
                systemImage: "sparkles",
                accessibilityID: AccessibilityID.calibrationABFinishButton.rawValue,
                action: model.finishComparisons
            )
        }
    }

    private var naturalDefault: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.abSkipAllHint))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.skipToNaturalDefault()
            } label: {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: "leaf")
                        .accessibilityHidden(true)
                    Text(verbatim: CalibrationCopy.text(CalibrationCopy.abSkipAll))
                        .styleToneText(.label, color: .accent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.calibrationABNaturalButton.rawValue)
        }
    }
}
