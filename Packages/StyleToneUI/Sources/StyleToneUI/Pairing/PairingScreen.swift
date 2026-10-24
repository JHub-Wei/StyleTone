import StyleToneCore
import SwiftUI

/// Pairing screen: collect original/edited pairs, show on-device quality
/// grades, and hand the usable samples to calibration.
///
/// The view owns no services. The host injects a `PairingViewModel` (or the
/// dependencies it needs) and receives either the finished samples or the
/// skip signal. Accessibility identifiers follow `pairing.*`.
@MainActor
public struct PairingScreen: View {
    @State private var viewModel: PairingViewModel
    private let onFinish: @MainActor ([PairSample], PairingSessionSummary) -> Void
    private let onSkip: @MainActor (PairingSessionSummary) -> Void

    @Environment(\.styleToneTheme) private var theme

    // MARK: - Init

    public init(
        viewModel: PairingViewModel,
        onFinish: @escaping @MainActor ([PairSample], PairingSessionSummary) -> Void,
        onSkip: @escaping @MainActor (PairingSessionSummary) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    public init(
        dependencies: PairingDependencies = .placeholder,
        onFinish: @escaping @MainActor ([PairSample], PairingSessionSummary) -> Void,
        onSkip: @escaping @MainActor (PairingSessionSummary) -> Void
    ) {
        self.init(
            viewModel: PairingViewModel(dependencies: dependencies),
            onFinish: onFinish,
            onSkip: onSkip
        )
    }

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header
                progressHeader
                loadingRow
                noticeRow
                content
                actions
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
        .navigationTitle(Text(verbatim: PairingCopy.title.text))
        .modifier(PairingInlineNavigationTitle())
        .accessibilityIdentifier(PairingAccessibilityID.screen.rawValue)
        .task {
            await viewModel.start()
        }
        .sheet(item: $viewModel.pendingPick) { request in
            pickerSheet(for: request)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            undoInset
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.undo != nil)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text(verbatim: PairingCopy.title.text)
                .styleToneText(.display)

            Text(verbatim: PairingCopy.subtitle.text)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Progress

    private var progressHeader: some View {
        PairingProgressHeader(
            progress: viewModel.progress,
            target: viewModel.target,
            isEnabled: viewModel.isEditable,
            onSelectTarget: { target in
                viewModel.selectTarget(target)
            }
        )
    }

    @ViewBuilder
    private var loadingRow: some View {
        if viewModel.isLoading {
            LoadingView(
                message: PairingCopy.loading.text,
                style: .inline,
                accessibilityID: PairingAccessibilityID.loading.rawValue
            )
        }
    }

    // MARK: - Notice

    @ViewBuilder
    private var noticeRow: some View {
        if let notice = viewModel.notice {
            PairingNoticeBanner(
                notice: notice,
                onAction: {
                    guard let action = notice.action else { return }
                    Task { @MainActor in
                        await viewModel.perform(action)
                    }
                },
                onDismiss: {
                    viewModel.dismissNotice()
                }
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.showsEmptyState {
            PairingEmptyStateView()
        } else if !viewModel.rows.isEmpty {
            LazyVStack(alignment: .leading, spacing: theme.spacing.md) {
                ForEach(viewModel.rows) { row in
                    PairingPairCard(
                        row: row,
                        isImporting: viewModel.importingPairID == row.id,
                        isEditable: viewModel.isEditable,
                        onPick: { slot in
                            viewModel.pick(slot, in: row.id)
                        },
                        onRemovePhoto: { slot in
                            viewModel.removePhoto(slot, in: row.id)
                        },
                        onDelete: {
                            viewModel.deletePair(row.id)
                        },
                        onRetry: {
                            Task { @MainActor in
                                await viewModel.retryAssessment(pairID: row.id)
                            }
                        }
                    )
                }
            }
            .accessibilityIdentifier(PairingAccessibilityID.pairList.rawValue)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            PrimaryButton(
                PairingCopy.addPairButton.text,
                systemImage: "plus",
                role: .secondary,
                isEnabled: viewModel.canAddPair,
                accessibilityID: PairingAccessibilityID.addPairButton.rawValue
            ) {
                viewModel.addPair()
            }

            Text(verbatim: PairingCopy.importHint.text)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                PairingCopy.continueButton.text,
                systemImage: "arrow.right",
                role: .primary,
                isEnabled: viewModel.canContinue,
                accessibilityID: PairingAccessibilityID.continueButton.rawValue
            ) {
                guard let samples = viewModel.finish() else { return }
                onFinish(samples, viewModel.summary)
            }

            if let hint = viewModel.continueHint {
                Text(verbatim: hint)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        PairingAccessibilityID.continueHint.rawValue
                    )
            }

            PrimaryButton(
                PairingCopy.skipButton.text,
                role: .secondary,
                isEnabled: viewModel.hasLoaded,
                accessibilityID: PairingAccessibilityID.skipButton.rawValue
            ) {
                viewModel.skip()
                onSkip(viewModel.summary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Image(systemName: "lock.shield")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.textTertiary))
                    .accessibilityHidden(true)

                Text(verbatim: PairingCopy.pickerNote.text)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(PairingAccessibilityID.pickerNote.rawValue)

            HStack(spacing: theme.spacing.xs) {
                Image(systemName: saveSymbol)
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(saveColor))
                    .accessibilityHidden(true)

                Text(verbatim: viewModel.saveText)
                    .styleToneText(.caption, color: saveColor)
                    .accessibilityIdentifier(
                        PairingAccessibilityID.saveState.rawValue
                    )
            }
        }
    }

    private var saveSymbol: String {
        switch viewModel.saveState {
        case .idle: return "internaldrive"
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var saveColor: ColorToken {
        viewModel.saveState.didFail ? .warning : .textTertiary
    }

    // MARK: - Undo

    @ViewBuilder
    private var undoInset: some View {
        if let undo = viewModel.undo {
            PairingUndoBar(backup: undo) {
                viewModel.undoDelete()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Picker

    private func pickerSheet(for request: PairingPickRequest) -> some View {
        PairingPhotoPickerSheet(
            request: request,
            onPicked: { picked in
                Task { @MainActor in
                    await viewModel.importPickedPhotos(picked)
                }
            },
            onCancel: {
                viewModel.cancelPick()
            },
            onFailed: { error in
                viewModel.reportImportFailure(error)
            },
            onDismissUnavailable: {
                viewModel.cancelPick()
            }
        )
    }
}

/// Inline navigation title on the platforms that have a navigation bar.
private struct PairingInlineNavigationTitle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
