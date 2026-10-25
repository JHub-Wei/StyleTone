import StyleToneCore
import SwiftUI

/// The editor's skin-tools panel (WP-16).
///
/// The panel owns only the skin section: smoothing, evenness and point-based
/// blemish repair. It calls the injected `RetouchRendering` /
/// `BlemishRemoving` engines through ``SkinToolsViewModel`` and never imports
/// Vision, Metal or the retouch implementation. WP-17 embeds it in the editor
/// and observes `renderRevision` to refresh its preview.
///
/// When the photo has no face (or the analysis does not match the image), the
/// controls are removed and an explanatory card is shown; with
/// ``SkinToolsUnavailableBehavior/hide`` the whole panel disappears instead.
@MainActor
public struct SkinToolsPanel: View {
    private let model: SkinToolsViewModel
    private let unavailableBehavior: SkinToolsUnavailableBehavior
    private let onDisplayedImageChange: (@MainActor (ImageAsset) -> Void)?

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scaledTouchTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    /// - Parameters:
    ///   - model: The editor-owned skin controller.
    ///   - unavailableBehavior: Whether a photo without a usable face hides
    ///     the panel or shows a disabled explanation. Defaults to `disable`.
    ///   - onDisplayedImageChange: Called with the new image whenever
    ///     `renderRevision` advances (successful render, reset, new source).
    public init(
        model: SkinToolsViewModel,
        unavailableBehavior: SkinToolsUnavailableBehavior = .disable,
        onDisplayedImageChange: (@MainActor (ImageAsset) -> Void)? = nil
    ) {
        self.model = model
        self.unavailableBehavior = unavailableBehavior
        self.onDisplayedImageChange = onDisplayedImageChange
    }

    public var body: some View {
        if isHiddenForUnavailablePhoto {
            EmptyView()
        } else {
            content
        }
    }

    /// Exposed to the package tests so the hide policy can be asserted without
    /// an XCUITest bundle.
    var isHiddenForUnavailablePhoto: Bool {
        unavailableBehavior == .hide && model.unavailableReason != nil
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            header

            if model.isRendering {
                progressRow
            }

            if let failure = model.failure {
                failureBanner(failure)
            }

            if let notice = model.notice {
                noticeBanner(notice)
            }

            if let reason = model.unavailableReason {
                unavailableCard(reason)
            } else {
                sliders

                if !model.isSkinMaskAvailable {
                    maskWarning
                }

                blemishSection
            }

            if model.areControlsEnabled, model.isAtOriginal {
                originalBadge
            }
        }
        .modifier(SkinToolsCardModifier())
        .accessibilityIdentifier(SkinToolsAccessibilityID.root.rawValue)
        .onChange(of: model.renderRevision) { _, _ in
            onDisplayedImageChange?(model.displayedImage)
        }
    }

    // MARK: Header

    private var header: some View {
        SectionHeader(
            title: SkinToolsCopy.text(SkinToolsCopy.sectionTitle),
            subtitle: SkinToolsCopy.text(SkinToolsCopy.sectionNote),
            accessibilityID: SkinToolsAccessibilityID.header.rawValue
        ) {
            Button {
                model.reset()
            } label: {
                Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.resetButton))
                    .styleToneText(
                        .caption,
                        color: model.canReset ? .accent : .textTertiary
                    )
                    .frame(
                        minWidth: scaledTouchTarget,
                        minHeight: scaledTouchTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canReset)
            .accessibilityIdentifier(SkinToolsAccessibilityID.resetButton.rawValue)
            .accessibilityLabel(Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.resetButton)))
            .accessibilityHint(Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.resetHint)))
        }
    }

    // MARK: Sliders

    private var sliders: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            SliderRow(
                title: SkinToolsCopy.text(SkinToolsCopy.smoothing),
                value: Binding(
                    get: { model.smoothing },
                    set: { model.setSmoothing($0) }
                ),
                systemImage: "sparkles",
                isEnabled: model.areControlsEnabled && model.pendingBlemish == nil,
                accessibilityID: SkinToolsAccessibilityID.smoothingSlider.rawValue
            )

            SliderRow(
                title: SkinToolsCopy.text(SkinToolsCopy.evenness),
                value: Binding(
                    get: { model.evenness },
                    set: { model.setEvenness($0) }
                ),
                systemImage: "circle.lefthalf.filled",
                isEnabled: model.areControlsEnabled && model.pendingBlemish == nil,
                accessibilityID: SkinToolsAccessibilityID.evennessSlider.rawValue
            )
        }
    }

    private var maskWarning: some View {
        Label {
            Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.maskMissing))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.color(.warning))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SkinToolsAccessibilityID.maskWarning.rawValue)
    }

    // MARK: Blemish

    private var blemishSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.blemishTitle))
                        .styleToneText(.sectionTitle)
                        .accessibilityAddTraits(.isHeader)

                    Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.blemishSubtitle))
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if !model.blemishes.isEmpty {
                    Text(verbatim: SkinToolsCopy.format(
                        SkinToolsCopy.blemishCount,
                        model.blemishes.count
                    ))
                    .styleToneText(.value, color: .textSecondary)
                    .accessibilityIdentifier(SkinToolsAccessibilityID.blemishCount.rawValue)
                }
            }

            if model.isBlemishMode {
                blemishEditor
            } else {
                PrimaryButton(
                    SkinToolsCopy.text(SkinToolsCopy.blemishStart),
                    systemImage: "bandage",
                    role: .secondary,
                    isEnabled: model.areControlsEnabled,
                    accessibilityID: SkinToolsAccessibilityID.blemishButton.rawValue,
                    accessibilityHint: SkinToolsCopy.text(SkinToolsCopy.canvasHint)
                ) {
                    model.beginBlemishMode()
                }
            }
        }
    }

    private var blemishEditor: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            SkinToolsBlemishCanvas(model: model)
            zoomControls

            SliderRow(
                title: SkinToolsCopy.text(SkinToolsCopy.blemishRadius),
                value: Binding(
                    get: { model.radius },
                    set: { model.setRadius($0) }
                ),
                range: SkinToolsLimits.minimumRadius...SkinToolsLimits.maximumRadius,
                step: SkinToolsLimits.radiusStep,
                systemImage: "circle.dashed",
                isEnabled: model.areControlsEnabled,
                valueFormatter: { value in
                    value.formatted(.percent.precision(.fractionLength(1)))
                },
                accessibilityID: SkinToolsAccessibilityID.blemishRadiusSlider.rawValue
            )

            Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.blemishRadiusHint))
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.blemishes.isEmpty {
                Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.blemishEmpty))
                    .styleToneText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(SkinToolsAccessibilityID.blemishEmpty.rawValue)
            } else {
                HStack(spacing: theme.spacing.sm) {
                    PrimaryButton(
                        SkinToolsCopy.text(SkinToolsCopy.blemishUndo),
                        systemImage: "arrow.uturn.backward",
                        role: .secondary,
                        isEnabled: model.canUndoBlemish,
                        accessibilityID: SkinToolsAccessibilityID.blemishUndoButton.rawValue
                    ) {
                        model.undoBlemish()
                    }

                    PrimaryButton(
                        SkinToolsCopy.text(SkinToolsCopy.blemishClear),
                        systemImage: "eraser",
                        role: .secondary,
                        isEnabled: model.canClearBlemishes,
                        accessibilityID: SkinToolsAccessibilityID.blemishClearButton.rawValue
                    ) {
                        model.clearBlemishes()
                    }
                }
            }

            PrimaryButton(
                SkinToolsCopy.text(SkinToolsCopy.blemishDone),
                systemImage: "checkmark",
                role: .secondary,
                accessibilityID: SkinToolsAccessibilityID.blemishDoneButton.rawValue
            ) {
                model.endBlemishMode()
            }
        }
    }

    // MARK: Zoom

    private var zoomControls: some View {
        HStack(spacing: theme.spacing.sm) {
            zoomButton(
                title: SkinToolsCopy.text(SkinToolsCopy.zoomOut),
                systemImage: "minus.magnifyingglass",
                accessibilityID: SkinToolsAccessibilityID.zoomOutButton,
                isEnabled: model.canZoomOut
            ) {
                model.zoomOut()
            }

            Text(verbatim: zoomText)
                .styleToneText(.value, color: .textPrimary)
                .frame(minWidth: 56)
                .accessibilityIdentifier(SkinToolsAccessibilityID.zoomValue.rawValue)
                .accessibilityLabel(Text(verbatim: SkinToolsCopy.format(
                    SkinToolsCopy.zoomAccessibility,
                    zoomLevel
                )))

            zoomButton(
                title: SkinToolsCopy.text(SkinToolsCopy.zoomIn),
                systemImage: "plus.magnifyingglass",
                accessibilityID: SkinToolsAccessibilityID.zoomInButton,
                isEnabled: model.canZoomIn
            ) {
                model.zoomIn()
            }

            zoomButton(
                title: SkinToolsCopy.text(SkinToolsCopy.zoomReset),
                systemImage: "arrow.counterclockwise",
                accessibilityID: SkinToolsAccessibilityID.zoomResetButton,
                isEnabled: model.canResetZoom
            ) {
                model.resetZoom()
            }

            Spacer(minLength: 0)
        }
    }

    private func zoomButton(
        title: String,
        systemImage: String,
        accessibilityID: AccessibilityID,
        isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(theme.typography.font(.body))
                .foregroundStyle(
                    isEnabled ? theme.color(.textPrimary) : theme.color(.textTertiary)
                )
                .frame(width: scaledTouchTarget, height: scaledTouchTarget)
                .background(
                    theme.color(.surfaceElevated),
                    in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                        .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityID.rawValue)
        .accessibilityLabel(Text(verbatim: title))
    }

    private var zoomLevel: Int {
        Int(model.zoomScale.rounded())
    }

    private var zoomText: String {
        SkinToolsCopy.format(SkinToolsCopy.zoomValue, zoomLevel)
    }

    // MARK: Progress

    private var progressRow: some View {
        HStack(spacing: theme.spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.rendering))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                model.cancelRendering()
            } label: {
                Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.cancel))
                    .styleToneText(.label, color: .accent)
                    .frame(minHeight: scaledTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SkinToolsAccessibilityID.cancelButton.rawValue)
            .accessibilityLabel(Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.cancel)))
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xs)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SkinToolsAccessibilityID.progress.rawValue)
    }

    // MARK: Error / notice

    private func failureBanner(_ failure: SkinToolsFailure) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.color(.error))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.errorTitle))
                        .styleToneText(.label)

                    Text(verbatim: SkinToolsCopy.text(
                        SkinToolsCopy.errorKey(for: failure.kind)
                    ))
                    .styleToneText(.caption, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(verbatim: SkinToolsCopy.format(
                        SkinToolsCopy.errorCode,
                        failure.diagnosticCode
                    ))
                    .styleToneText(.caption, color: .textTertiary)
                    .accessibilityIdentifier(SkinToolsAccessibilityID.errorCode.rawValue)
                }

                Spacer(minLength: 0)

                Button {
                    model.dismissFailure()
                } label: {
                    Image(systemName: "xmark")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(theme.color(.textSecondary))
                        .frame(width: scaledTouchTarget, height: scaledTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(SkinToolsAccessibilityID.dismissErrorButton.rawValue)
                .accessibilityLabel(Text(verbatim: SkinToolsCopy.text(
                    SkinToolsCopy.errorDismiss
                )))
            }

            PrimaryButton(
                SkinToolsCopy.text(SkinToolsCopy.retry),
                systemImage: "arrow.clockwise",
                role: .secondary,
                isEnabled: !model.isRendering,
                accessibilityID: SkinToolsAccessibilityID.retryButton.rawValue
            ) {
                model.retry()
            }
        }
        .padding(theme.spacing.md)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(
                    theme.color(.error).opacity(0.55),
                    lineWidth: theme.metrics.hairline
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SkinToolsAccessibilityID.errorBanner.rawValue)
    }

    private func noticeBanner(_ notice: SkinToolsNotice) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Image(systemName: notice == .renderingCancelled
                ? "arrow.uturn.backward.circle"
                : "exclamationmark.circle")
                .foregroundStyle(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.noticeKey(for: notice)))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                model.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.textSecondary))
                    .frame(width: scaledTouchTarget, height: scaledTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SkinToolsAccessibilityID.dismissNoticeButton.rawValue)
            .accessibilityLabel(Text(verbatim: SkinToolsCopy.text(
                SkinToolsCopy.noticeDismiss
            )))
        }
        .padding(.leading, theme.spacing.md)
        .padding(.trailing, theme.spacing.xs)
        .padding(.vertical, theme.spacing.xs)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(SkinToolsAccessibilityID.notice.rawValue)
    }

    // MARK: Unavailable / original

    private func unavailableCard(_ reason: SkinToolsUnavailableReason) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(theme.typography.font(.screenTitle))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.unavailableTitle))
                    .styleToneText(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Text(verbatim: SkinToolsCopy.text(
                    SkinToolsCopy.unavailableKey(for: reason)
                ))
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(theme.spacing.md)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SkinToolsAccessibilityID.unavailable.rawValue)
    }

    private var originalBadge: some View {
        Label {
            Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.originalBadge))
                .styleToneText(.caption, color: .textSecondary)
        } icon: {
            Image(systemName: "photo")
                .foregroundStyle(theme.color(.textTertiary))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SkinToolsAccessibilityID.originalBadge.rawValue)
    }
}

// MARK: - Card surface

private struct SkinToolsCardModifier: ViewModifier {
    @Environment(\.styleToneTheme) private var theme

    func body(content: Content) -> some View {
        content
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
    }
}
