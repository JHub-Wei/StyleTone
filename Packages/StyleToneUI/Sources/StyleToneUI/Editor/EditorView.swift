import Foundation
import StyleToneCore
import SwiftUI

/// The editor screen: preview, total strength, four tool areas, undo and
/// export.
///
/// The host supplies photo import, style navigation and, optionally, the export
/// destination. WP-19 can replace the built-in export button action later; the
/// orchestration and consistency rules stay here.
@MainActor
public struct EditorView: View {
    @State private var model: EditorViewModel
    private let onAddPhoto: (@MainActor () -> Void)?
    private let onOpenStyle: (@MainActor () -> Void)?
    private let onExported: (@MainActor (ExportResult) -> Void)?

    @Environment(\.styleToneTheme) private var theme

    public init(
        model: EditorViewModel,
        onAddPhoto: (@MainActor () -> Void)? = nil,
        onOpenStyle: (@MainActor () -> Void)? = nil,
        onExported: (@MainActor (ExportResult) -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.onAddPhoto = onAddPhoto
        self.onOpenStyle = onOpenStyle
        self.onExported = onExported
    }

    public init(
        dependencies: EditorDependencies = .placeholder,
        onAddPhoto: (@MainActor () -> Void)? = nil,
        onOpenStyle: (@MainActor () -> Void)? = nil,
        onExported: (@MainActor (ExportResult) -> Void)? = nil
    ) {
        self.init(
            model: EditorViewModel(dependencies: dependencies),
            onAddPhoto: onAddPhoto,
            onOpenStyle: onOpenStyle,
            onExported: onExported
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                header

                if let issue = model.issue {
                    issueBanner(issue)
                }

                if !model.warnings.isEmpty {
                    warningBanner
                }

                EditorCanvasView(model: model)

                if model.hasImage {
                    editorContent
                } else {
                    emptyContent
                }

                privacyNote
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.screenVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .accessibilityIdentifier(EditorAccessibility.root.rawValue)
        .alert(
            Text(verbatim: EditorCopy.text(EditorCopy.backgroundProtectionOffTitle)),
            isPresented: Binding(
                get: { model.pendingBackgroundProtectionDisable },
                set: { presented in
                    if !presented {
                        model.cancelBackgroundProtectionDisable()
                    }
                }
            )
        ) {
            Button(role: .cancel) {
                model.cancelBackgroundProtectionDisable()
            } label: {
                Text(verbatim: EditorCopy.text(EditorCopy.cancel))
            }

            Button(role: .destructive) {
                model.confirmBackgroundProtectionDisable()
            } label: {
                Text(verbatim: EditorCopy.text(EditorCopy.backgroundProtectionOffConfirm))
            }
        } message: {
            Text(verbatim: EditorCopy.text(EditorCopy.backgroundProtectionOffMessage))
        }
        .onDisappear {
            model.setShowingOriginal(false)
            model.cancelRendering()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(verbatim: EditorCopy.text(EditorCopy.title))
                .styleToneText(.screenTitle)

            Text(verbatim: EditorCopy.text(EditorCopy.subtitle))
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            PrimaryButton(
                EditorCopy.text(EditorCopy.addPhotoButton),
                systemImage: "photo.badge.plus",
                isEnabled: onAddPhoto != nil,
                accessibilityID: AccessibilityID.editorAddPhotoButton.rawValue
            ) {
                if let onAddPhoto {
                    onAddPhoto()
                }
            }

            Text(verbatim: EditorCopy.text(EditorCopy.emptyState))
                .styleToneText(.caption, color: .textTertiary)
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
            canvasActions

            if model.isAnalyzing {
                analysisStatus
            }

            strengthSection
            toolSection

            if model.selectedArea == .skin {
                blemishSection
            }

            backgroundProtectionSection
            historyActions
            footerActions
        }
    }

    private var canvasActions: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.sm) {
                EditorPillButton(
                    title: EditorCopy.text(EditorCopy.splitComparison),
                    systemImage: "rectangle.split.2x1",
                    isSelected: model.isSplitComparisonEnabled,
                    isEnabled: model.canEdit,
                    accessibilityID: EditorAccessibility.splitToggle.rawValue,
                    accessibilityValue: nil
                ) {
                    model.toggleSplitComparison()
                }

                EditorPillButton(
                    title: EditorCopy.text(EditorCopy.zoomReset),
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    isSelected: false,
                    isEnabled: model.zoom.isZoomed,
                    accessibilityID: EditorAccessibility.zoomResetButton.rawValue,
                    accessibilityValue: nil
                ) {
                    model.resetZoom()
                }

                Spacer(minLength: 0)
            }

            Text(verbatim: EditorCopy.text(EditorCopy.compareHint))
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(EditorAccessibility.compareHint.rawValue)
        }
    }

    private var analysisStatus: some View {
        HStack(spacing: theme.spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)

            Text(verbatim: EditorCopy.text(EditorCopy.analysisLoading))
                .styleToneText(.caption, color: .textSecondary)
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.color(.surface),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
    }

    private var strengthSection: some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                SectionHeader(
                    title: EditorCopy.text(EditorCopy.strength),
                    subtitle: EditorCopy.text(EditorCopy.strengthHint)
                )

                EditorSliderRow(
                    title: EditorCopy.text(EditorCopy.strength),
                    value: strengthBinding,
                    range: 0...EditorEditState.maximumStrength,
                    step: 0.01,
                    isEnabled: model.canEdit,
                    valueFormatter: { value in
                        value.formatted(.percent.precision(.fractionLength(0)))
                    },
                    accessibilityID: EditorAccessibility.strengthSlider.rawValue,
                    onEditingChanged: handleEditingChanged
                )

                HStack(spacing: theme.spacing.sm) {
                    EditorPillButton(
                        title: EditorCopy.text(EditorCopy.naturalPreset),
                        systemImage: "leaf",
                        isSelected: abs(model.edits.strength - EditorEditState.naturalStrength) < 0.001,
                        isEnabled: model.canEdit,
                        accessibilityID: EditorAccessibility.naturalButton.rawValue,
                        accessibilityValue: nil
                    ) {
                        model.applyNaturalPreset()
                    }

                    Spacer(minLength: 0)
                }

                Text(verbatim: EditorCopy.text(EditorCopy.naturalPresetHint))
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var toolSection: some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                toolTabs

                if let reason = selectedAreaUnavailableReason {
                    Text(verbatim: EditorCopy.text(reason))
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(model.selectedAdjustments) { adjustment in
                    EditorSliderRow(
                        title: EditorCopy.text(adjustment.titleKey),
                        value: adjustmentBinding(adjustment),
                        range: adjustment.range,
                        step: step(for: adjustment),
                        isEnabled: model.isAdjustmentEnabled(adjustment),
                        valueFormatter: { value in
                            formattedValue(value, for: adjustment)
                        },
                        accessibilityID: adjustment.accessibilityID.rawValue,
                        onEditingChanged: handleEditingChanged
                    )
                }
            }
        }
    }

    private var toolTabs: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(EditorToolArea.allCases) { area in
                toolTab(area)
            }
        }
    }

    private func toolTab(_ area: EditorToolArea) -> some View {
        let isAvailable = area.isAvailable(in: model.analysis) && model.canEdit
        let isSelected = area == model.selectedArea

        return Button {
            model.selectArea(area)
        } label: {
            Text(verbatim: EditorCopy.text(area.titleKey))
                .font(theme.typography.font(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, theme.spacing.sm)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
                .foregroundStyle(
                    isSelected ? theme.color(.onAccent) : theme.color(.textSecondary)
                )
                .background(
                    isSelected ? theme.color(.accent) : theme.color(.surfaceElevated),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
        .accessibilityIdentifier(area.accessibilityID.rawValue)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }

    private var selectedAreaUnavailableReason: LocalizationKey? {
        guard model.canEdit, !model.selectedAreaIsAvailable else { return nil }
        return model.selectedArea.unavailableReasonKey(in: model.analysis)
    }

    private var blemishSection: some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                SectionHeader(title: EditorCopy.text(EditorCopy.blemishPoints))

                Text(verbatim: blemishCountText)
                    .styleToneText(.body, color: .textSecondary)

                if model.edits.blemishPoints.isEmpty {
                    Text(verbatim: EditorCopy.text(EditorCopy.blemishEmpty))
                        .styleToneText(.caption, color: .textTertiary)
                }

                HStack(spacing: theme.spacing.sm) {
                    EditorPillButton(
                        title: EditorCopy.text(EditorCopy.blemishRemove),
                        systemImage: "arrow.uturn.backward",
                        isSelected: false,
                        isEnabled: model.canEdit && !model.edits.blemishPoints.isEmpty,
                        accessibilityID: EditorAccessibility.blemishRemoveButton.rawValue,
                        accessibilityValue: nil
                    ) {
                        model.removeLastBlemishPoint()
                    }

                    EditorPillButton(
                        title: EditorCopy.text(EditorCopy.blemishClear),
                        systemImage: "xmark.circle",
                        isSelected: false,
                        isEnabled: model.canEdit && !model.edits.blemishPoints.isEmpty,
                        accessibilityID: EditorAccessibility.blemishClearButton.rawValue,
                        accessibilityValue: nil
                    ) {
                        model.clearBlemishPoints()
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var blemishCountText: String {
        let count = model.edits.blemishPoints.count
        return "\(EditorCopy.text(EditorCopy.blemishPoints)): \(count)"
    }

    private var backgroundProtectionSection: some View {
        card {
            Toggle(
                isOn: Binding(
                    get: { model.edits.backgroundProtection },
                    set: { enabled in
                        model.requestBackgroundProtection(enabled)
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(verbatim: EditorCopy.text(EditorCopy.backgroundProtection))
                        .styleToneText(.body)

                    Text(verbatim: EditorCopy.text(EditorCopy.backgroundProtectionHint))
                        .styleToneText(.caption, color: .textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(theme.color(.accent))
            .disabled(!model.canEdit)
            .accessibilityIdentifier(EditorAccessibility.backgroundProtectionToggle.rawValue)
        }
    }

    private var historyActions: some View {
        HStack(spacing: theme.spacing.sm) {
            EditorPillButton(
                title: EditorCopy.text(EditorCopy.undo),
                systemImage: "arrow.uturn.backward",
                isSelected: false,
                isEnabled: model.canEdit && model.canUndo,
                accessibilityID: EditorAccessibility.undoButton.rawValue,
                accessibilityValue: "\(model.undoCount)"
            ) {
                model.undo()
            }

            EditorPillButton(
                title: EditorCopy.text(EditorCopy.redo),
                systemImage: "arrow.uturn.forward",
                isSelected: false,
                isEnabled: model.canEdit && model.canRedo,
                accessibilityID: EditorAccessibility.redoButton.rawValue,
                accessibilityValue: "\(model.redoCount)"
            ) {
                model.redo()
            }

            EditorPillButton(
                title: EditorCopy.text(EditorCopy.reset),
                systemImage: "arrow.counterclockwise",
                isSelected: false,
                isEnabled: model.canEdit && model.canReset,
                accessibilityID: EditorAccessibility.resetButton.rawValue,
                accessibilityValue: nil
            ) {
                model.reset()
            }

            Spacer(minLength: 0)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            PrimaryButton(
                EditorCopy.text(EditorCopy.exportButton),
                systemImage: "square.and.arrow.up",
                isLoading: model.exportState.isBusy,
                isEnabled: model.canExport,
                accessibilityID: AccessibilityID.editorExportButton.rawValue
            ) {
                performExport()
            }

            HStack(spacing: theme.spacing.md) {
                PrimaryButton(
                    EditorCopy.text(EditorCopy.addPhotoButton),
                    systemImage: "photo.badge.plus",
                    role: .secondary,
                    isEnabled: onAddPhoto != nil && !model.exportState.isBusy,
                    accessibilityID: AccessibilityID.editorAddPhotoButton.rawValue
                ) {
                    if let onAddPhoto {
                        onAddPhoto()
                    }
                }

                PrimaryButton(
                    EditorCopy.text(EditorCopy.styleButton),
                    systemImage: "person.crop.circle.badge.checkmark",
                    role: .secondary,
                    isEnabled: onOpenStyle != nil && !model.exportState.isBusy,
                    accessibilityID: AccessibilityID.editorStyleButton.rawValue
                ) {
                    if let onOpenStyle {
                        onOpenStyle()
                    }
                }
            }

            if model.exportState == .completed {
                Label {
                    Text(verbatim: EditorCopy.text(EditorCopy.exportCompleted))
                        .styleToneText(.caption, color: .success)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(theme.color(.success))
                }
            }
        }
    }

    private var privacyNote: some View {
        Label {
            Text(verbatim: EditorCopy.text(EditorCopy.note))
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock")
                .foregroundStyle(theme.color(.textTertiary))
        }
    }

    // MARK: - Banners

    private func issueBanner(_ issue: EditorIssue) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Label {
                Text(verbatim: issueTitle(issue))
                    .styleToneText(.sectionTitle)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.color(.warning))
            }

            Text(verbatim: issueMessage(issue))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: theme.spacing.md) {
                if issue.recovery != nil {
                    Button {
                        Task {
                            await model.recover()
                        }
                    } label: {
                        Text(verbatim: EditorCopy.text(EditorCopy.issueRetry))
                            .styleToneText(.label, color: .accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(EditorAccessibility.issueRetryButton.rawValue)
                }

                Button {
                    model.dismissIssue()
                } label: {
                    Text(verbatim: EditorCopy.text(EditorCopy.issueDismiss))
                        .styleToneText(.label, color: .textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(EditorAccessibility.issueDismissButton.rawValue)

                Spacer(minLength: 0)
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(theme.color(.warning), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(EditorAccessibility.issueBanner.rawValue)
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ForEach(model.warnings) { warning in
                Label {
                    Text(verbatim: EditorCopy.text(warning.messageKey))
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: warningIcon(warning))
                        .foregroundStyle(
                            warning.severity == .caution
                                ? theme.color(.warning)
                                : theme.color(.textTertiary)
                        )
                }
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.color(.surface),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(EditorAccessibility.warningBanner.rawValue)
    }

    // MARK: - Helpers

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { model.edits.strength },
            set: { value in
                model.setStrength(value)
            }
        )
    }

    private func adjustmentBinding(_ adjustment: EditorAdjustment) -> Binding<Double> {
        Binding(
            get: { adjustment.value(in: model.edits.adjustments) },
            set: { value in
                model.setAdjustment(adjustment, to: value)
            }
        )
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(theme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.color(.surface),
                in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
            }
    }

    private func handleEditingChanged(_ editing: Bool) {
        if editing {
            model.beginInteraction()
        } else {
            model.endInteraction()
        }
    }

    private func step(for adjustment: EditorAdjustment) -> Double {
        adjustment == .legLength ? 0.005 : 0.01
    }

    private func formattedValue(_ value: Double, for adjustment: EditorAdjustment) -> String {
        if adjustment == .legLength {
            return (value - 1.0).formatted(.percent.precision(.fractionLength(0)))
        }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func warningIcon(_ warning: EditorWarning) -> String {
        warning.severity == .caution ? "exclamationmark.triangle" : "info.circle"
    }

    private func issueTitle(_ issue: EditorIssue) -> String {
        guard let recovery = issue.recovery else {
            return EditorCopy.text(EditorCopy.issueRenderTitle)
        }
        switch recovery {
        case .retryAnalysis:
            return EditorCopy.text(EditorCopy.issueAnalysisTitle)
        case .retryRender:
            return EditorCopy.text(EditorCopy.issueRenderTitle)
        case .reloadStyle:
            return EditorCopy.text(EditorCopy.issueStyleTitle)
        case .retryExport:
            return EditorCopy.text(EditorCopy.issueExportTitle)
        }
    }

    private func issueMessage(_ issue: EditorIssue) -> String {
        guard let recovery = issue.recovery else {
            return EditorCopy.text(EditorCopy.issueRenderMessage)
        }
        switch recovery {
        case .retryAnalysis:
            return EditorCopy.text(EditorCopy.issueAnalysisMessage)
        case .retryRender:
            return EditorCopy.text(EditorCopy.issueRenderMessage)
        case .reloadStyle:
            return EditorCopy.text(EditorCopy.issueStyleMessage)
        case .retryExport:
            return EditorCopy.text(EditorCopy.issueExportMessage)
        }
    }

    private func performExport() {
        guard model.canExport else { return }
        Task {
            do {
                let result = try await model.export()
                onExported?(result)
            } catch {
                // The view model publishes the recoverable issue.
            }
        }
    }
}

// MARK: - Pill button

private struct EditorPillButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let isEnabled: Bool
    let accessibilityID: String
    let accessibilityValue: String?
    let action: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scaledMinHeight: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(theme.typography.font(.label))
                        .accessibilityHidden(true)
                }

                Text(verbatim: title)
                    .font(theme.typography.font(.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, theme.spacing.md)
            .frame(minHeight: scaledMinHeight)
            .foregroundStyle(
                isSelected ? theme.color(.onAccent) : theme.color(.textPrimary)
            )
            .background(
                isSelected ? theme.color(.accent) : theme.color(.surfaceElevated),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(Text(verbatim: title))
        .modifier(EditorAccessibilityValue(value: accessibilityValue))
    }
}

private struct EditorAccessibilityValue: ViewModifier {
    let value: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(Text(verbatim: value))
        } else {
            content
        }
    }
}
