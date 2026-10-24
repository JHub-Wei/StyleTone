import SwiftUI
import StyleToneUI

/// Calibration and style-card placeholder. WP-10 owns the 3/5/8 flow and A/B
/// comparisons; this screen only proves routing between pairing, calibration
/// and the style card.
struct CalibrationPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.calibrationTitle,
            subtitle: ShellCopy.calibrationSubtitle,
            screen: .calibration
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                SectionHeader(
                    title: ShellCopy.calibrationPathTitle,
                    subtitle: ShellCopy.calibrationNote
                )

                PrimaryButton(
                    ShellCopy.calibrationAddPairsButton,
                    systemImage: "rectangle.on.rectangle",
                    accessibilityID: AccessibilityID.calibrationAddPairsButton.rawValue
                ) {
                    actions.navigate(.pairing)
                }

                PrimaryButton(
                    ShellCopy.calibrationStartButton,
                    systemImage: "slider.horizontal.3",
                    role: .secondary,
                    accessibilityID: AccessibilityID.calibrationStartButton.rawValue
                ) {
                    actions.presentToast(
                        ToastMessage(text: ShellCopy.calibrationToast, kind: .info)
                    )
                }

                PrimaryButton(
                    ShellCopy.calibrationStyleCardButton,
                    systemImage: "person.crop.circle.badge.checkmark",
                    role: .secondary,
                    accessibilityID: AccessibilityID.calibrationStyleCardButton.rawValue
                ) {
                    actions.navigate(.styleProfile)
                }

                Text(verbatim: ShellCopy.calibrationNote)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
