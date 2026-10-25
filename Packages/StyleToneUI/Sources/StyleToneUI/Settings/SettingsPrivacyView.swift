import SwiftUI

/// The in-app privacy explanation.
///
/// This page is readable without a network connection and without an account.
/// The store-facing privacy policy URL is injected by WP-28 when it exists; no
/// web address is hardcoded here.
@MainActor
public struct SettingsPrivacyView: View {
    private let support: SettingsSupportInfo

    @Environment(\.styleToneTheme) private var theme

    public init(support: SettingsSupportInfo = .placeholder) {
        self.support = support
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header
                introCard
                localDataSection
                leavesSection
                diagnosticsSection
                choicesSection
                policySection
                noAccountNote
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.top, theme.spacing.screenVertical)
            .padding(.bottom, theme.spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .navigationTitle(Text(verbatim: SettingsCopy.privacyDetailTitle.text))
        .modifier(SettingsInlineNavigationTitle())
        .accessibilityIdentifier(SettingsAccessibilityID.privacyScreen.rawValue)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: SettingsCopy.privacyDetailTitle.text)
                .styleToneText(.display)

            Text(verbatim: SettingsCopy.privacySummary.text)
                .styleToneText(.screenTitle, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text(verbatim: SettingsCopy.privacyIntro.text)
                .styleToneText(.body)
                .fixedSize(horizontal: false, vertical: true)

            SettingsBulletRow(
                text: SettingsCopy.privacyNoAccount.text,
                systemImage: "person.crop.circle.badge.xmark",
                token: .accent
            )
        }
        .settingsCard()
        .accessibilityIdentifier(SettingsAccessibilityID.privacyNote.rawValue)
    }

    // MARK: Sections

    private var localDataSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.privacyLocalTitle.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                SettingsBulletRow(
                    text: SettingsCopy.privacyLocalPhotos.text,
                    systemImage: "photo",
                    token: .success
                )
                SettingsBulletRow(
                    text: SettingsCopy.privacyLocalStyle.text,
                    systemImage: "person.crop.circle.badge.checkmark",
                    token: .success
                )
                SettingsBulletRow(
                    text: SettingsCopy.privacyLocalHistory.text,
                    systemImage: "clock.arrow.circlepath",
                    token: .success
                )
                SettingsBulletRow(
                    text: SettingsCopy.privacyLocalDiagnostics.text,
                    systemImage: "waveform.path.ecg",
                    token: .success
                )
            }
            .settingsCard()
        }
    }

    private var leavesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.privacyLeavesTitle.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                SettingsBulletRow(
                    text: SettingsCopy.privacyLeavesNothing.text,
                    systemImage: "lock.shield",
                    token: .success
                )
                SettingsBulletRow(
                    text: SettingsCopy.privacyLeavesApple.text,
                    systemImage: "creditcard",
                    token: .textSecondary
                )
            }
            .settingsCard()
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.privacyCollectTitle.text)

            Text(verbatim: SettingsCopy.privacyCollectBody.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .settingsCard()
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsData.rawValue)
        }
    }

    private var choicesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.privacyControlsTitle.text)

            Text(verbatim: SettingsCopy.privacyControlsBody.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .settingsCard()
        }
    }

    @ViewBuilder
    private var policySection: some View {
        if let url = support.privacyPolicyURL {
            Link(destination: url) {
                SettingsLinkLabel(
                    title: SettingsCopy.privacyPolicy.text,
                    subtitle: nil,
                    systemImage: "doc.text"
                )
            }
            .buttonStyle(.plain)
            .settingsCard()
            .accessibilityIdentifier(SettingsAccessibilityID.privacyPolicyLink.rawValue)
        } else {
            Text(verbatim: SettingsCopy.privacyPolicyUnavailable.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noAccountNote: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Image(systemName: "lock")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            Text(verbatim: SettingsCopy.privacyNoAccountNote.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SettingsAccessibilityID.noAccountNote.rawValue)
    }
}
