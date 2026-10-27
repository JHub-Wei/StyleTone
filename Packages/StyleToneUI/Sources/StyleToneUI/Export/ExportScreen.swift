import Foundation
import StyleToneCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Export sheet presented from the editor.
///
/// The view owns no services: it binds to `ExportViewModel` and forwards close
/// and purchase callbacks to the host. Accessibility identifiers follow
/// `export.*`; save/close reuse the frozen ids from WP-03.
@MainActor
public struct ExportScreen: View {
    @State private var viewModel: ExportViewModel
    private let onClose: @MainActor () -> Void
    private let onUpgrade: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var closeTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    // MARK: - Init

    public init(
        viewModel: ExportViewModel,
        onClose: @escaping @MainActor () -> Void,
        onUpgrade: @escaping @MainActor () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
        self.onUpgrade = onUpgrade
    }

    public init(
        source: ExportSource,
        dependencies: ExportDependencies = .placeholder,
        settings: ExportSettings = ExportSettings(),
        onClose: @escaping @MainActor () -> Void,
        onUpgrade: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            viewModel: ExportViewModel(
                source: source,
                dependencies: dependencies,
                settings: settings
            ),
            onClose: onClose,
            onUpgrade: onUpgrade
        )
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header
                mediaSections
                controlSections
                statusSections
                actionsSection
                footer
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.top, theme.spacing.screenVertical)
            .padding(.bottom, theme.spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            theme.color(.background)
                .ignoresSafeArea()
        }
        .navigationTitle(Text(verbatim: ExportCopy.title.text))
        .modifier(ExportInlineNavigationTitle())
        .accessibilityIdentifier(ExportAccessibilityID.screen.rawValue)
        .task {
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { @MainActor in
                await viewModel.refreshAuthorization()
                await viewModel.refreshEntitlement()
            }
        }
        .onDisappear {
            // The model keeps a pending share alive for its completion handler
            // and lets an in-flight PhotoKit save finish; all other paths clean
            // up immediately. If the share item was already dismissed without a
            // completion, the abandon path prevents a permanently busy model.
            viewModel.prepareForClose()
            viewModel.abandonShareIfPending()
        }
        .modifier(ExportSharePresenter(viewModel: viewModel))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(verbatim: ExportCopy.title.text)
                    .styleToneText(.screenTitle)

                Text(verbatim: ExportCopy.subtitle.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.prepareForClose()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(theme.typography.font(.body))
                    .foregroundStyle(theme.color(.textSecondary))
                    .frame(width: closeTarget, height: closeTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isCloseEnabled)
            .accessibilityLabel(Text(verbatim: ExportCopy.closeButton.text))
            .accessibilityIdentifier(ExportAccessibilityID.closeButton.rawValue)
        }
    }

    // MARK: - Preview

    private var mediaSections: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            previewSection
            metadataSection
        }
    }

    private var controlSections: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            quotaSection
            permissionSection
            formatSection
            largeNoticeSection
        }
    }

    @ViewBuilder
    private var statusSections: some View {
        if hasStatusContent {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                infoSection
                progressSection
                failureSection
                resultSection
                cancelledSection
            }
        }
    }

    private var hasStatusContent: Bool {
        viewModel.infoNotice != nil
            || viewModel.progress != nil
            || viewModel.failure != nil
            || viewModel.outcome != nil
            || viewModel.stage == .cancelled
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            PhotoCanvas(
                image: viewModel.previewImage,
                aspectRatio: viewModel.previewAspectRatio > 0
                    ? CGFloat(viewModel.previewAspectRatio)
                    : nil,
                emptyTitle: ExportCopy.previewEmptyTitle.text,
                accessibilityLabel: ExportCopy.previewAccessibilityLabel.text,
                accessibilityID: ExportAccessibilityID.preview.rawValue
            )

            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                Text(verbatim: viewModel.pixelSizeText)
                    .styleToneText(.caption, color: .textSecondary)
                    .accessibilityIdentifier(ExportAccessibilityID.pixelSize.rawValue)

                Text(verbatim: viewModel.megapixelsText)
                    .styleToneText(.caption, color: .textTertiary)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        HStack(alignment: .top, spacing: theme.spacing.xs) {
            Image(systemName: "location.slash")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            Text(verbatim: ExportCopy.locationRemoved.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ExportAccessibilityID.locationNote.rawValue)
    }

    // MARK: - Quota / permission

    @ViewBuilder
    private var quotaSection: some View {
        if viewModel.isQuotaExhausted {
            ExportQuotaExhaustedCard {
                onUpgrade()
            }
        } else if viewModel.quotaLoadFailed {
            ExportQuotaLoadFailedCard {
                Task { @MainActor in
                    await viewModel.refreshEntitlement()
                }
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.authorization.isDenied || viewModel.authorization.isUnavailable {
            ExportPermissionCard(
                access: viewModel.authorization,
                canShare: viewModel.supportsSystemShare && viewModel.canExport,
                onOpenSettings: openSettings,
                onShare: {
                    viewModel.shareInstead()
                },
                onRetry: {
                    Task { @MainActor in
                        await viewModel.refreshAuthorization()
                    }
                }
            )
        }
    }

    // MARK: - Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            SectionHeader(title: ExportCopy.formatSectionTitle.text)

            Text(verbatim: ExportCopy.formatLabel.text)
                .styleToneText(.caption, color: .textSecondary)

            Picker(
                ExportCopy.formatLabel.text,
                selection: formatBinding
            ) {
                ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                    Text(verbatim: ExportCopy.formatTitle(format).text)
                        .tag(format.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isBusy)
            .accessibilityIdentifier(ExportAccessibilityID.formatPicker.rawValue)

            Text(verbatim: ExportCopy.formatNote.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: ExportCopy.qualityLabel.text)
                .styleToneText(.caption, color: .textSecondary)
                .padding(.top, theme.spacing.xs)

            Picker(
                ExportCopy.qualityLabel.text,
                selection: qualityBinding
            ) {
                ForEach(ExportQuality.all) { quality in
                    Text(verbatim: ExportCopy.qualityTitle(quality).text)
                        .tag(quality)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.isBusy)
            .accessibilityIdentifier(ExportAccessibilityID.qualityPicker.rawValue)
        }
    }

    @ViewBuilder
    private var largeNoticeSection: some View {
        if viewModel.isLargeImage {
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.warning))
                    .accessibilityHidden(true)

                Text(verbatim: ExportCopy.largeImageNotice.text)
                    .styleToneText(.caption, color: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(ExportAccessibilityID.largeNotice.rawValue)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var infoSection: some View {
        if let info = viewModel.infoNotice {
            ExportInfoBanner(text: info.text) {
                viewModel.dismissInfoNotice()
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if viewModel.isBusy, let progress = viewModel.progress {
            ExportProgressCard(
                progress: progress,
                stageText: viewModel.stageText,
                percentText: viewModel.progressPercentText,
                canCancel: viewModel.canCancel,
                onCancel: {
                    viewModel.cancel()
                }
            )
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if let failure = viewModel.failure {
            ExportFailureCard(failure: failure) { recovery in
                perform(recovery)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if viewModel.outcome != nil {
            ExportResultCard(
                title: viewModel.outcomeTitle.text,
                message: viewModel.outcomeMessage.text,
                detail: viewModel.outcomeDetailText,
                countPending: viewModel.outcomeCountPending,
                onDone: {
                    viewModel.prepareForClose()
                    onClose()
                }
            )
        }
    }

    @ViewBuilder
    private var cancelledSection: some View {
        if viewModel.stage == .cancelled {
            ExportCancelledCard {
                viewModel.retry()
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            PrimaryButton(
                ExportCopy.saveButton.text,
                systemImage: "square.and.arrow.down",
                role: .primary,
                isLoading: viewModel.stage == .savingToLibrary,
                isEnabled: viewModel.canSaveToLibrary,
                accessibilityID: ExportAccessibilityID.saveButton.rawValue
            ) {
                viewModel.saveToLibrary()
            }

            if viewModel.supportsSystemShare {
                PrimaryButton(
                    ExportCopy.shareButton.text,
                    systemImage: "square.and.arrow.up",
                    role: .secondary,
                    isEnabled: viewModel.canShare,
                    accessibilityID: ExportAccessibilityID.shareButton.rawValue
                ) {
                    viewModel.share()
                }
            }

            if let quota = viewModel.quotaText {
                Text(verbatim: quota)
                    .styleToneText(.caption, color: .textTertiary)
                    .accessibilityIdentifier(ExportAccessibilityID.quota.rawValue)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Image(systemName: "photo.badge.plus")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.textTertiary))
                    .accessibilityHidden(true)

                Text(verbatim: ExportCopy.libraryAddOnlyNote.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Image(systemName: "lock.shield")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.textTertiary))
                    .accessibilityHidden(true)

                Text(verbatim: ExportCopy.privacyNote.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Helpers

    private var formatBinding: Binding<String> {
        Binding(
            get: { viewModel.format.rawValue },
            set: { rawValue in
                guard let format = ExportFormat(rawValue: rawValue) else { return }
                viewModel.format = format
            }
        )
    }

    private var qualityBinding: Binding<ExportQuality> {
        Binding(
            get: { viewModel.quality },
            set: { viewModel.quality = $0 }
        )
    }

    private var settingsURL: URL? {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
        #endif
    }

    private func openSettings() {
        guard let settingsURL else { return }
        _ = openURL(settingsURL)
    }

    private func perform(_ recovery: ExportFailure.Recovery) {
        switch recovery {
        case .retry:
            viewModel.retry()
        case .shareInstead:
            viewModel.shareInstead()
        case .saveInstead:
            viewModel.saveToLibrary()
        case .openSettings:
            openSettings()
        case .upgrade:
            onUpgrade()
        case .dismiss:
            viewModel.dismissFailure()
        }
    }
}

/// Inline navigation title on the platforms that have a navigation bar.
private struct ExportInlineNavigationTitle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
