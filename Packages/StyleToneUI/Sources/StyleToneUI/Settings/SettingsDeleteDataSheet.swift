import SwiftUI

/// Two-step deletion confirmation.
///
/// Step one explains exactly what is removed and what is kept. Step two is a
/// separate destructive confirmation; the sheet stays presented between steps,
/// so dismissing it can never be mistaken for confirming the deletion.
@MainActor
struct SettingsDeleteDataSheet: View {
    let viewModel: SettingsViewModel

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                    if viewModel.isFinalConfirmation {
                        finalStep
                    } else {
                        overviewStep
                    }
                }
                .padding(.horizontal, theme.spacing.screenHorizontal)
                .padding(.top, theme.spacing.screenVertical)
                .padding(.bottom, theme.spacing.xxxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(theme.color(.background).ignoresSafeArea())
            .navigationTitle(Text(verbatim: SettingsCopy.deleteSheetTitle.text))
            .modifier(SettingsInlineNavigationTitle())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cancelDelete()
                    } label: {
                        Text(verbatim: SettingsCopy.deleteCancelButton.text)
                    }
                    .accessibilityIdentifier(SettingsAccessibilityID.deleteCancelButton.rawValue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(SettingsAccessibilityID.deleteSheet.rawValue)
    }

    // MARK: Step one

    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Text(verbatim: SettingsCopy.deleteSheetTitle.text)
                    .styleToneText(.screenTitle)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: SettingsCopy.deleteSheetIntro.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            removalList
            keptList

            Text(verbatim: SettingsCopy.deleteKeepSubscription.text)
                .styleToneText(.caption, color: .warning)
                .fixedSize(horizontal: false, vertical: true)
                .settingsCard()

            PrimaryButton(
                SettingsCopy.deleteContinueButton.text,
                systemImage: "arrow.right",
                role: .primary,
                accessibilityID: SettingsAccessibilityID.deleteContinueButton.rawValue
            ) {
                viewModel.continueDelete()
            }
        }
    }

    private var removalList: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.deleteRemoveTitle.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                SettingsBulletRow(
                    text: SettingsCopy.deleteRemoveProfiles.text,
                    systemImage: "trash",
                    token: .error
                )
                SettingsBulletRow(
                    text: SettingsCopy.deleteRemovePairs.text,
                    systemImage: "trash",
                    token: .error
                )
                SettingsBulletRow(
                    text: SettingsCopy.deleteRemoveQuota.text,
                    systemImage: "trash",
                    token: .error
                )
                SettingsBulletRow(
                    text: SettingsCopy.deleteRemoveDiagnostics.text,
                    systemImage: "trash",
                    token: .error
                )
                SettingsBulletRow(
                    text: SettingsCopy.deleteRemoveTemporary.text,
                    systemImage: "trash",
                    token: .error
                )
            }
        }
    }

    private var keptList: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.deleteKeepTitle.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                SettingsBulletRow(
                    text: SettingsCopy.deleteKeepPhotos.text,
                    systemImage: "checkmark.circle",
                    token: .success
                )
                SettingsBulletRow(
                    text: SettingsCopy.deleteKeepPurchase.text,
                    systemImage: "checkmark.circle",
                    token: .success
                )
            }
        }
    }

    // MARK: Step two

    private var finalStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Text(verbatim: SettingsCopy.deleteFinalTitle.text)
                    .styleToneText(.screenTitle)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: SettingsCopy.deleteFinalMessage.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: SettingsCopy.deleteKeepSubscription.text)
                .styleToneText(.caption, color: .warning)
                .fixedSize(horizontal: false, vertical: true)
                .settingsCard()

            PrimaryButton(
                SettingsCopy.deleteFinalConfirm.text,
                systemImage: "trash.fill",
                role: .destructive,
                accessibilityID: SettingsAccessibilityID.deleteFinalButton.rawValue
            ) {
                Task { @MainActor in
                    await viewModel.confirmDeletion()
                }
            }

            PrimaryButton(
                SettingsCopy.deleteBackButton.text,
                systemImage: "chevron.left",
                role: .secondary,
                accessibilityID: SettingsAccessibilityID.deleteBackButton.rawValue
            ) {
                viewModel.backToDeleteOverview()
            }
        }
    }
}
