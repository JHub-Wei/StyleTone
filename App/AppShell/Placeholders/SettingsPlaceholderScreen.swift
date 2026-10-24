import SwiftUI
import StyleToneUI

/// Settings placeholder. Privacy copy, data deletion and diagnostics belong to
/// WP-21; the buttons here only exercise navigation and the design system.
struct SettingsPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.settingsTitle,
            subtitle: ShellCopy.settingsSubtitle,
            screen: .settings
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                SectionHeader(
                    title: ShellCopy.settingsLocalDataTitle,
                    subtitle: ShellCopy.settingsPrivacyNote
                )

                VStack(spacing: theme.spacing.md) {
                    PrimaryButton(
                        ShellCopy.settingsStyleCardButton,
                        systemImage: "person.crop.circle.badge.checkmark",
                        role: .secondary,
                        accessibilityID: AccessibilityID.settingsStyleCardButton.rawValue
                    ) {
                        actions.navigate(.styleProfile)
                    }

                    PrimaryButton(
                        ShellCopy.settingsPaywallButton,
                        systemImage: "creditcard",
                        role: .secondary,
                        accessibilityID: AccessibilityID.settingsPaywallButton.rawValue
                    ) {
                        actions.navigate(.paywall)
                    }

                    PrimaryButton(
                        ShellCopy.settingsOnboardingButton,
                        systemImage: "hand.wave",
                        role: .secondary,
                        accessibilityID: AccessibilityID.settingsOnboardingButton.rawValue
                    ) {
                        actions.navigate(.onboarding)
                    }

                    PrimaryButton(
                        ShellCopy.settingsDeleteDataButton,
                        systemImage: "trash",
                        role: .destructive,
                        accessibilityID: AccessibilityID.settingsDeleteDataButton.rawValue
                    ) {
                        actions.presentToast(
                            ToastMessage(text: ShellCopy.settingsDeleteDataToast, kind: .warning)
                        )
                    }
                }

                Text(verbatim: ShellCopy.settingsNote)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
