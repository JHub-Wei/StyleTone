import SwiftUI

@MainActor
struct CalibrationLearningView: View {
    let model: CalibrationViewModel

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            Text(verbatim: CalibrationCopy.text(CalibrationCopy.learningTitle))
                .styleToneText(.screenTitle)
                .accessibilityAddTraits(.isHeader)

            LoadingView(
                message: CalibrationCopy.text(CalibrationCopy.learningMessage),
                style: .inline,
                accessibilityID: AccessibilityID.calibrationLoading.rawValue
            )

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.errorPairsPreserved))
                .styleToneText(.caption, color: .textSecondary)

            PrimaryButton(
                CalibrationCopy.text(CalibrationCopy.learningCancel),
                role: .secondary,
                accessibilityID: AccessibilityID.calibrationCancelWorkButton.rawValue,
                action: model.cancelWork
            )
        }
        .calibrationCard()
    }
}
