import StyleToneCore
import SwiftUI

/// WP-10 calibration screen: pair depth selection, optional AB, learning and
/// the resulting style card placeholder.
///
/// The host supplies navigation and pair-picking callbacks. The screen itself
/// never presents an account, login or purchase entry.
@MainActor
public struct CalibrationView: View {
    @State private var model: CalibrationViewModel
    @State private var isSavingToClose = false

    private let addPairs: (@MainActor () -> Void)?
    private let openStyleCard: (@MainActor (StyleProfile) -> Void)?
    private let useStyle: (@MainActor (StyleProfile) -> Void)?
    private let close: (@MainActor () -> Void)?

    @Environment(\.styleToneTheme) private var theme

    public init(
        model: CalibrationViewModel,
        onAddPairs: (@MainActor () -> Void)? = nil,
        onOpenStyleCard: (@MainActor (StyleProfile) -> Void)? = nil,
        onContinue: (@MainActor (StyleProfile) -> Void)? = nil,
        onClose: (@MainActor () -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.addPairs = onAddPairs
        self.openStyleCard = onOpenStyleCard
        self.useStyle = onContinue
        self.close = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                if let notice = model.notice {
                    CalibrationNoticeBanner(
                        notice: notice,
                        dismiss: model.dismissNotice
                    )
                }

                stageContent

                footer
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.screenVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .accessibilityIdentifier(AccessibilityID.calibrationRoot.rawValue)
        .task {
            await model.restoreIfNeeded()
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.flow.phase {
        case .pairs:
            CalibrationPairStageView(model: model, addPairs: addPairs)
        case .comparisons:
            CalibrationABStageView(model: model)
        case .learning:
            CalibrationLearningView(model: model)
        case .failed:
            if let failure = model.flow.failure {
                CalibrationFailureView(
                    failure: failure,
                    retry: model.retry,
                    backToComparisons: model.returnToComparisons,
                    useNaturalDefault: model.skipToNaturalDefault,
                    backToPairs: model.recalibrate
                )
            } else {
                CalibrationPairStageView(model: model, addPairs: addPairs)
            }
        case .result:
            if let profile = model.flow.profile {
                CalibrationResultView(
                    model: model,
                    profile: profile,
                    openStyleCard: openCardAction(for: profile),
                    useStyle: useAction(for: profile)
                )
            } else {
                CalibrationPairStageView(model: model, addPairs: addPairs)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            if showsSaveLater, let close {
                Button {
                    guard !isSavingToClose else { return }
                    isSavingToClose = true
                    Task {
                        await model.pause()
                        isSavingToClose = false
                        close()
                    }
                } label: {
                    HStack(spacing: theme.spacing.sm) {
                        if isSavingToClose {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "clock.arrow.circlepath")
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: CalibrationCopy.text(CalibrationCopy.cancel))
                            .styleToneText(.label, color: .textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSavingToClose)
                .accessibilityIdentifier(AccessibilityID.calibrationPauseButton.rawValue)
                .accessibilityHint(Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsSaveLater)))
            }

            Label {
                Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsLocalOnly))
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .accessibilityIdentifier(AccessibilityID.calibrationNoAccountNote.rawValue)
        }
    }

    private var showsSaveLater: Bool {
        switch model.flow.phase {
        case .pairs, .comparisons: return true
        case .learning, .failed, .result: return false
        }
    }

    private func openCardAction(for profile: StyleProfile) -> (@MainActor () -> Void)? {
        guard let openStyleCard else { return nil }
        return { openStyleCard(profile) }
    }

    private func useAction(for profile: StyleProfile) -> (@MainActor () -> Void)? {
        guard let useStyle else { return nil }
        return { useStyle(profile) }
    }
}
