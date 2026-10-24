import StyleToneCore
import SwiftUI

@MainActor
struct CalibrationResultView: View {
    let model: CalibrationViewModel
    let profile: StyleProfile
    let openStyleCard: (@MainActor () -> Void)?
    let useStyle: (@MainActor () -> Void)?

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            header

            CalibrationStyleCardPreview(
                profile: profile,
                isNaturalDefault: model.flow.isNaturalDefaultResult,
                open: { openStyleCard?() }
            )

            summary

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultPreviewNote))
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let useStyle {
                PrimaryButton(
                    CalibrationCopy.text(CalibrationCopy.resultUse),
                    systemImage: "checkmark",
                    accessibilityID: AccessibilityID.calibrationUseStyleButton.rawValue,
                    action: useStyle
                )
            }

            PrimaryButton(
                CalibrationCopy.text(CalibrationCopy.resultRecalibrate),
                systemImage: "arrow.clockwise",
                role: .secondary,
                accessibilityID: AccessibilityID.calibrationRecalibrateButton.rawValue,
                action: model.recalibrate
            )

            Label {
                Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultSaved))
                    .styleToneText(.caption, color: .success)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.color(.success))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: model.flow.isNaturalDefaultResult
                ? CalibrationCopy.text(CalibrationCopy.resultNaturalTitle)
                : CalibrationCopy.text(CalibrationCopy.resultTitle))
                .styleToneText(.screenTitle)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: subtitle)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultConfidence))
                    .styleToneText(.caption, color: .textSecondary)
                Text(verbatim: CalibrationCopy.text(
                    CalibrationCopy.confidenceKey(for: profile.confidence)
                ))
                .styleToneText(.label)
                .accessibilityIdentifier(AccessibilityID.calibrationResultConfidence.rawValue)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
                Text(verbatim: CalibrationCopy.format(CalibrationCopy.resultPairs, profile.pairCount))
                    .styleToneText(.label)
                Text(verbatim: CalibrationCopy.format(
                    CalibrationCopy.resultChoices,
                    model.flow.answeredComparisonCount
                ))
                .styleToneText(.caption, color: .textSecondary)
            }
        }
        .calibrationCard()
        .accessibilityIdentifier(AccessibilityID.calibrationResultSummary.rawValue)
    }

    private var subtitle: String {
        if model.flow.isNaturalDefaultResult {
            return CalibrationCopy.text(CalibrationCopy.resultNaturalNote)
        }
        return CalibrationCopy.format(
            CalibrationCopy.resultSubtitle,
            profile.pairCount,
            model.flow.answeredComparisonCount
        )
    }
}
