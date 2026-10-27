import SwiftUI

/// Settings: privacy, diagnostics, licenses, version, support and local-data
/// deletion.
///
/// There is deliberately no account, login, cloud-sync or purchase entry. Data
/// deletion is a two-step flow and only reports success after the injected
/// coordinator verified that every local store is empty.
@MainActor
public struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel
    private let onAllDataDeleted: (@MainActor () -> Void)?

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Init

    public init(
        viewModel: SettingsViewModel,
        onAllDataDeleted: (@MainActor () -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onAllDataDeleted = onAllDataDeleted
    }

    public init(
        dependencies: SettingsDependencies,
        onAllDataDeleted: (@MainActor () -> Void)? = nil
    ) {
        self.init(
            viewModel: SettingsViewModel(dependencies: dependencies),
            onAllDataDeleted: onAllDataDeleted
        )
    }

    // MARK: Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header
                noticeRow
                deletionStatusRow
                privacySection
                diagnosticsSection
                subscriptionSection
                aboutSection
                supportSection
                footer
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.top, theme.spacing.screenVertical)
            .padding(.bottom, theme.spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .navigationTitle(Text(verbatim: SettingsCopy.title.text))
        .modifier(SettingsInlineNavigationTitle())
        .accessibilityIdentifier(SettingsAccessibilityID.screen.rawValue)
        .disabled(viewModel.isDeletionInProgress)
        .overlay(alignment: .center) {
            deletionOverlay
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: deleteSheetBinding) {
            SettingsDeleteDataSheet(viewModel: viewModel)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: viewModel.isDeletionInProgress
        )
    }

    // MARK: Header and status

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: SettingsCopy.title.text)
                .styleToneText(.display)

            Text(verbatim: SettingsCopy.subtitle.text)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var noticeRow: some View {
        if let notice = viewModel.notice {
            SettingsNoticeBanner(notice: notice) {
                viewModel.dismissNotice()
            }
        }
    }

    @ViewBuilder
    private var deletionStatusRow: some View {
        switch viewModel.deleteStage {
        case .deleted:
            deletionSuccess
        case .failed:
            deletionFailure
        default:
            EmptyView()
        }
    }

    private var deletionSuccess: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(theme.color(.success))
                    .accessibilityHidden(true)
                Text(verbatim: SettingsCopy.deleteSuccessTitle.text)
                    .styleToneText(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(verbatim: SettingsCopy.deleteSuccessBody.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onAllDataDeleted {
                PrimaryButton(
                    SettingsCopy.deleteStartOverButton.text,
                    systemImage: "arrow.counterclockwise",
                    role: .primary,
                    accessibilityID: SettingsAccessibilityID.deleteStartOverButton.rawValue
                ) {
                    onAllDataDeleted()
                }
            } else {
                Text(verbatim: SettingsCopy.deleteRestartHint.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settingsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SettingsAccessibilityID.deleteSuccess.rawValue)
    }

    private var deletionFailure: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.color(.error))
                    .accessibilityHidden(true)
                Text(verbatim: SettingsCopy.deleteFailedTitle.text)
                    .styleToneText(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(verbatim: SettingsCopy.deleteFailedBody.text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                SettingsCopy.deleteRetryButton.text,
                systemImage: "arrow.clockwise",
                role: .primary,
                accessibilityID: SettingsAccessibilityID.deleteRetryButton.rawValue
            ) {
                Task { @MainActor in
                    await viewModel.retryDeletion()
                }
            }
        }
        .settingsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SettingsAccessibilityID.deleteFailure.rawValue)
    }

    // MARK: Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(
                title: SettingsCopy.sectionPrivacy.text,
                subtitle: SettingsCopy.privacySummary.text,
                accessibilityID: SettingsAccessibilityID.privacyNote.rawValue
            )

            NavigationLink {
                SettingsPrivacyView(support: viewModel.support)
            } label: {
                SettingsLinkLabel(
                    title: SettingsCopy.privacyLink.text,
                    subtitle: SettingsCopy.privacyBody.text,
                    systemImage: "lock.shield"
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .settingsCard()
            .accessibilityIdentifier(SettingsAccessibilityID.privacyButton.rawValue)

            PrimaryButton(
                SettingsCopy.deleteDataButton.text,
                systemImage: "trash",
                role: .destructive,
                isEnabled: viewModel.canDeleteData,
                accessibilityID: SettingsAccessibilityID.deleteDataButton.rawValue,
                accessibilityHint: SettingsCopy.deleteDataHint.text
            ) {
                viewModel.requestDelete()
            }

            Text(verbatim: SettingsCopy.deleteDataHint.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(SettingsAccessibilityID.deleteDataHint.rawValue)
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(
                title: SettingsCopy.sectionDiagnostics.text,
                subtitle: SettingsCopy.diagnosticsSummary.text
            )

            VStack(alignment: .leading, spacing: theme.spacing.md) {
                diagnosticsToggleRow
                Text(verbatim: viewModel.diagnosticsNoteText)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                SettingsDivider()
                diagnosticsStatusRow
                SettingsDivider()
                diagnosticsCodeRow
                SettingsDivider()
                diagnosticsDataRows
            }
            .settingsCard()
            .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsSection.rawValue)
        }
    }

    private var diagnosticsToggleRow: some View {
        Toggle(isOn: diagnosticsBinding) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: SettingsCopy.diagnosticsToggle.text)
                    .styleToneText(.label)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: SettingsCopy.diagnosticsToggleHint.text)
                    .styleToneText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(theme.color(.accent))
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsToggle.rawValue)
        .accessibilityLabel(Text(verbatim: SettingsCopy.diagnosticsToggle.text))
        .accessibilityHint(Text(verbatim: SettingsCopy.diagnosticsToggleHint.text))
    }

    private var diagnosticsStatusRow: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                Text(verbatim: viewModel.diagnosticsStatusText)
                    .styleToneText(
                        .label,
                        color: viewModel.isDiagnosticsEnabled ? .success : .textTertiary
                    )
                    .accessibilityLabel(Text(verbatim: SettingsCopy.sectionDiagnostics.text))
                    .accessibilityValue(Text(verbatim: viewModel.diagnosticsStatusText))
                    .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsStatus.rawValue)

                Spacer(minLength: 0)

                if viewModel.isDiagnosticsEnabled {
                    Text(verbatim: SettingsCopy.entriesText(count: viewModel.diagnosticEntryCount))
                        .styleToneText(.caption, color: .textTertiary)
                        .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsEntries.rawValue)
                }
            }

            if viewModel.isDiagnosticsEnabled {
                Button {
                    Task { @MainActor in
                        await viewModel.clearDiagnostics()
                    }
                } label: {
                    Label(SettingsCopy.diagnosticsClearButton.text, systemImage: "trash")
                        .font(theme.typography.font(.label))
                        .foregroundStyle(theme.color(.accent))
                        .frame(minHeight: theme.metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsClearButton.rawValue)
            }
        }
    }

    private var diagnosticsCodeRow: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: SettingsCopy.diagnosticsCodeLabel.text)
                .styleToneText(.label)

            HStack(alignment: .top, spacing: theme.spacing.md) {
                Text(verbatim: viewModel.diagnosticCode)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.color(.textPrimary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: SettingsCopy.diagnosticsCodeLabel.text))
                    .accessibilityValue(Text(verbatim: viewModel.diagnosticCode))
                    .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsCode.rawValue)

                Spacer(minLength: 0)

                Button {
                    viewModel.copyDiagnosticCode()
                } label: {
                    Label(SettingsCopy.commonCopy.text, systemImage: "doc.on.doc")
                        .font(theme.typography.font(.label))
                        .foregroundStyle(theme.color(.accent))
                        .frame(minHeight: theme.metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: SettingsCopy.diagnosticsCopyButton.text))
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsCopyButton.rawValue)
            }

            Text(verbatim: SettingsCopy.diagnosticsCodeHint.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsCodeHint.rawValue)
        }
    }

    private var diagnosticsDataRows: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: SettingsCopy.diagnosticsDataTitle.text)
                .styleToneText(.label)
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsData.rawValue)

            SettingsBulletRow(
                text: SettingsCopy.diagnosticsDataBody.text,
                systemImage: "checkmark.circle",
                token: .success
            )

            Text(verbatim: SettingsCopy.diagnosticsNeverTitle.text)
                .styleToneText(.label)
                .padding(.top, theme.spacing.xs)
                .accessibilityIdentifier(SettingsAccessibilityID.diagnosticsNeverData.rawValue)

            SettingsBulletRow(
                text: SettingsCopy.diagnosticsNeverBody.text,
                systemImage: "xmark.circle",
                token: .error
            )
        }
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.sectionSubscription.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                HStack(alignment: .top, spacing: theme.spacing.sm) {
                    Image(systemName: "creditcard")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(theme.color(.accent))
                        .accessibilityHidden(true)

                    Text(verbatim: SettingsCopy.subscriptionBody.text)
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(verbatim: SettingsCopy.subscriptionHint.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(SettingsAccessibilityID.subscriptionNote.rawValue)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(title: SettingsCopy.sectionAbout.text)

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                NavigationLink {
                    SettingsLicensesView(catalog: viewModel.licenses)
                } label: {
                    SettingsLinkLabel(
                        title: SettingsCopy.licensesLink.text,
                        subtitle: SettingsCopy.licensesSummary.text,
                        systemImage: "doc.text"
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityIdentifier(SettingsAccessibilityID.licensesButton.rawValue)

                SettingsDivider()

                SettingsValueRow(
                    label: SettingsCopy.versionLabel.text,
                    value: viewModel.version.marketingVersion,
                    accessibilityID: SettingsAccessibilityID.versionRow.rawValue
                )

                SettingsDivider()

                SettingsValueRow(
                    label: SettingsCopy.buildLabel.text,
                    value: viewModel.version.buildNumber,
                    accessibilityID: SettingsAccessibilityID.buildRow.rawValue
                )

                SettingsDivider()

                SettingsValueRow(
                    label: SettingsCopy.systemLabel.text,
                    value: viewModel.version.systemDescription,
                    accessibilityID: SettingsAccessibilityID.systemRow.rawValue
                )
            }
            .settingsCard()
        }
    }

    // MARK: Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SectionHeader(
                title: SettingsCopy.sectionSupport.text,
                subtitle: SettingsCopy.supportSummary.text
            )

            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: SettingsCopy.supportBody.text)
                    .styleToneText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                supportEmailRow

                Button {
                    viewModel.copySupportEmail()
                } label: {
                    Label(SettingsCopy.supportCopyEmail.text, systemImage: "doc.on.doc")
                        .font(theme.typography.font(.label))
                        .foregroundStyle(theme.color(.accent))
                        .frame(minHeight: theme.metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SettingsAccessibilityID.supportCopyButton.rawValue)

                if let url = viewModel.support.privacyPolicyURL {
                    Link(destination: url) {
                        SettingsLinkLabel(
                            title: SettingsCopy.privacyPolicy.text,
                            subtitle: nil,
                            systemImage: "doc.text"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(SettingsAccessibilityID.supportPrivacyLink.rawValue)
                }

                Text(verbatim: viewModel.support.responseTime)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(SettingsAccessibilityID.supportResponse.rawValue)
            }
            .settingsCard()
            .accessibilityIdentifier(SettingsAccessibilityID.supportSection.rawValue)
        }
    }

    @ViewBuilder
    private var supportEmailRow: some View {
        if let mailtoURL = viewModel.support.mailtoURL {
            Link(destination: mailtoURL) {
                SettingsLinkLabel(
                    title: SettingsCopy.supportEmailLabel.text,
                    subtitle: viewModel.support.email,
                    systemImage: "envelope"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SettingsAccessibilityID.supportEmailLink.rawValue)
        } else {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "envelope")
                    .foregroundStyle(theme.color(.textTertiary))
                    .accessibilityHidden(true)
                Text(verbatim: viewModel.support.email)
                    .styleToneText(.label, color: .textSecondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Image(systemName: "lock")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            Text(verbatim: SettingsCopy.footerNote.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SettingsAccessibilityID.noAccountNote.rawValue)
    }

    // MARK: Overlay

    @ViewBuilder
    private var deletionOverlay: some View {
        if viewModel.isDeletionInProgress {
            LoadingView(
                message: SettingsCopy.deleteProgress.text,
                style: .overlay,
                accessibilityID: SettingsAccessibilityID.deleteProgress.rawValue
            )
        }
    }

    // MARK: Bindings

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDiagnosticsEnabled },
            set: { enabled in
                viewModel.requestDiagnosticsToggle(enabled)
            }
        )
    }

    private var deleteSheetBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.isFirstConfirmation || viewModel.isFinalConfirmation
            },
            set: { isPresented in
                guard !isPresented else { return }
                if viewModel.isFirstConfirmation || viewModel.isFinalConfirmation {
                    viewModel.cancelDelete()
                }
            }
        )
    }
}

#if DEBUG
#Preview("Settings") {
    NavigationStack {
        SettingsScreen(dependencies: .placeholder)
    }
    .styleToneTheme(.dark)
}

#Preview("Settings / privacy") {
    NavigationStack {
        SettingsPrivacyView(support: .placeholder)
    }
    .styleToneTheme(.dark)
}

#Preview("Settings / licenses") {
    NavigationStack {
        SettingsLicensesView()
    }
    .styleToneTheme(.dark)
}
#endif
