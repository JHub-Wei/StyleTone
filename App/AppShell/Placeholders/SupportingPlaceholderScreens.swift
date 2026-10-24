import SwiftUI
import StyleToneUI

// Placeholder destinations that have no tab of their own. Each one demonstrates
// routing and the design system; none implements business behaviour.

struct OnboardingPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.onboardingTitle,
            subtitle: ShellCopy.onboardingSubtitle,
            screen: .onboarding
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                Text(verbatim: ShellCopy.onboardingNote)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    ShellCopy.onboardingStartButton,
                    systemImage: "slider.horizontal.3",
                    accessibilityID: AccessibilityID.onboardingStartButton.rawValue
                ) {
                    actions.navigate(.calibration)
                }

                PrimaryButton(
                    ShellCopy.onboardingNaturalDefaultButton,
                    systemImage: "leaf",
                    role: .secondary,
                    accessibilityID: AccessibilityID.onboardingNaturalDefaultButton.rawValue
                ) {
                    actions.navigate(.editor)
                }
            }
        }
    }
}

struct PairingPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.pairingTitle,
            subtitle: ShellCopy.pairingSubtitle,
            screen: .pairing
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                SectionHeader(
                    title: ShellCopy.pairingChecklistTitle,
                    subtitle: ShellCopy.pairingNote
                )

                VStack(spacing: theme.spacing.md) {
                    PrimaryButton(
                        ShellCopy.pairingAddPairButton,
                        systemImage: "rectangle.badge.plus",
                        accessibilityID: AccessibilityID.pairingAddPairButton.rawValue
                    ) {
                        actions.presentToast(
                            ToastMessage(text: ShellCopy.pairingToast, kind: .info)
                        )
                    }

                    PrimaryButton(
                        ShellCopy.pairingContinueButton,
                        systemImage: "arrow.right",
                        role: .secondary,
                        accessibilityID: AccessibilityID.pairingContinueButton.rawValue
                    ) {
                        actions.navigate(.calibration)
                    }
                }
            }
        }
    }
}

struct StyleProfilePlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.calibrationStyleCardTitle,
            subtitle: ShellCopy.calibrationStyleCardNote,
            screen: .styleProfile
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text(verbatim: ShellCopy.calibrationStyleCardTitle)
                        .styleToneText(.sectionTitle)

                    Text(verbatim: ShellCopy.calibrationStyleCardNote)
                        .styleToneText(.body, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(theme.spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.color(.surface),
                    in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                        .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
                }

                PrimaryButton(
                    ShellCopy.calibrationRecalibrateButton,
                    systemImage: "arrow.triangle.2.circlepath",
                    accessibilityID: AccessibilityID.styleProfileRecalibrateButton.rawValue
                ) {
                    actions.navigate(.calibration)
                }
            }
        }
    }
}

struct PaywallPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.paywallTitle,
            subtitle: ShellCopy.paywallSubtitle,
            screen: .paywall
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                Text(verbatim: ShellCopy.paywallNote)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: theme.spacing.md) {
                    PrimaryButton(
                        ShellCopy.paywallSubscribeButton,
                        systemImage: "creditcard",
                        accessibilityID: AccessibilityID.paywallSubscribeButton.rawValue
                    ) {
                        actions.presentToast(
                            ToastMessage(text: ShellCopy.paywallToast, kind: .info)
                        )
                    }

                    PrimaryButton(
                        ShellCopy.paywallRestoreButton,
                        systemImage: "arrow.clockwise",
                        role: .secondary,
                        accessibilityID: AccessibilityID.paywallRestoreButton.rawValue
                    ) {
                        actions.presentToast(
                            ToastMessage(text: ShellCopy.paywallToast, kind: .info)
                        )
                    }

                    PrimaryButton(
                        ShellCopy.paywallCloseButton,
                        role: .secondary,
                        accessibilityID: AccessibilityID.paywallCloseButton.rawValue
                    ) {
                        actions.dismissSheet()
                    }
                }
            }
        }
    }
}

struct ExportPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme
    @State private var showsLoading = false

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.exportTitle,
            subtitle: ShellCopy.exportSubtitle,
            screen: .export
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                SectionHeader(title: ShellCopy.exportPreviewTitle)

                Toggle(isOn: $showsLoading) {
                    Text(verbatim: ShellCopy.exportLoadingToggle)
                        .font(theme.typography.font(.body))
                        .foregroundStyle(theme.color(.textPrimary))
                }
                .tint(theme.color(.accent))
                .accessibilityIdentifier(AccessibilityID.exportLoadingToggle.rawValue)

                if showsLoading {
                    LoadingView(
                        message: ShellCopy.exportLoading,
                        style: .inline,
                        accessibilityID: AccessibilityID.exportLoading.rawValue
                    )
                }

                Text(verbatim: ShellCopy.exportNote)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: theme.spacing.md) {
                    PrimaryButton(
                        ShellCopy.exportButton,
                        systemImage: "square.and.arrow.up",
                        accessibilityID: AccessibilityID.exportExportButton.rawValue
                    ) {
                        actions.presentToast(
                            ToastMessage(text: ShellCopy.exportToast, kind: .info)
                        )
                    }

                    PrimaryButton(
                        ShellCopy.exportCloseButton,
                        role: .secondary,
                        accessibilityID: AccessibilityID.exportCloseButton.rawValue
                    ) {
                        actions.dismissSheet()
                    }
                }
            }
        }
    }
}
