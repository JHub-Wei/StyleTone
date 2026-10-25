import SwiftUI

/// Licenses page: the application notice, Apple system frameworks and any
/// third-party components.
///
/// The MVP has no third-party runtime dependencies, so the third-party section
/// is an explicit "none" statement rather than an empty list. If a dependency
/// is ever added, the injected catalog lists it and the page needs no change.
@MainActor
public struct SettingsLicensesView: View {
    private let catalog: SettingsLicenseCatalog

    @Environment(\.styleToneTheme) private var theme

    public init(catalog: SettingsLicenseCatalog = .standard) {
        self.catalog = catalog
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header
                licenseSection(
                    title: SettingsCopy.licensesApplicationTitle.text,
                    licenses: catalog.application,
                    accessibilityID: nil
                )
                licenseSection(
                    title: SettingsCopy.licensesSystemTitle.text,
                    licenses: catalog.systemFrameworks,
                    accessibilityID: nil
                )
                thirdPartySection
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.top, theme.spacing.screenVertical)
            .padding(.bottom, theme.spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .navigationTitle(Text(verbatim: SettingsCopy.licensesDetailTitle.text))
        .modifier(SettingsInlineNavigationTitle())
        .accessibilityIdentifier(SettingsAccessibilityID.licensesScreen.rawValue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: SettingsCopy.licensesDetailTitle.text)
                .styleToneText(.display)

            Text(verbatim: SettingsCopy.licensesIntro.text)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func licenseSection(
        title: String,
        licenses: [SettingsLicense],
        accessibilityID: String?
    ) -> some View {
        if !licenses.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                SectionHeader(title: title)

                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    ForEach(licenses) { license in
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                                Text(verbatim: license.name)
                                    .styleToneText(.label)
                                Spacer(minLength: 0)
                                if let version = license.version {
                                    Text(verbatim: version)
                                        .styleToneText(.caption, color: .textTertiary)
                                }
                            }

                            Text(verbatim: license.body.text)
                                .styleToneText(.caption, color: .textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .settingsCard()
                .modifier(OptionalIdentifier(identifier: accessibilityID))
            }
        }
    }

    private var thirdPartySection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.licensesThirdPartyTitle.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                if catalog.thirdParty.isEmpty {
                    SettingsBulletRow(
                        text: SettingsCopy.licensesThirdPartyNone.text,
                        systemImage: "checkmark.seal",
                        token: .success
                    )
                } else {
                    ForEach(catalog.thirdParty) { license in
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text(verbatim: license.name)
                                .styleToneText(.label)
                            Text(verbatim: license.body.text)
                                .styleToneText(.caption, color: .textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .settingsCard()
        }
    }
}

private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
