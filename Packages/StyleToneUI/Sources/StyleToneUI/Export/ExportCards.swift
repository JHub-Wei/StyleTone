import SwiftUI

/// Shared card surface for export status panels.
@MainActor
struct ExportCard<Content: View>: View {
    private let borderColor: ColorToken
    private let content: Content

    @Environment(\.styleToneTheme) private var theme

    init(borderColor: ColorToken = .border, @ViewBuilder content: () -> Content) {
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(theme.spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.color(.surface),
                in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(
                        theme.color(borderColor),
                        lineWidth: theme.metrics.hairline
                    )
            }
    }
}

// MARK: - Progress

@MainActor
struct ExportProgressCard: View {
    let progress: ExportProgress
    let stageText: String
    let percentText: String
    let canCancel: Bool
    let onCancel: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                    Text(verbatim: stageText)
                        .styleToneText(.label)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Text(verbatim: percentText)
                        .styleToneText(.value, color: .textSecondary)
                        .accessibilityIdentifier(ExportAccessibilityID.progressValue.rawValue)
                }

                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(theme.color(.accent))

                if canCancel {
                    PrimaryButton(
                        ExportCopy.cancelButton.text,
                        role: .secondary,
                        accessibilityID: ExportAccessibilityID.cancelButton.rawValue
                    ) {
                        onCancel()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.progress.rawValue)
    }
}

// MARK: - Permission

@MainActor
struct ExportPermissionCard: View {
    let access: PhotoLibraryAccess
    let canShare: Bool
    let onOpenSettings: @MainActor () -> Void
    let onShare: @MainActor () -> Void
    let onRetry: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard(borderColor: .warning) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: title.text)
                    .styleToneText(.sectionTitle)

                Text(verbatim: message.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if access == .denied {
                    PrimaryButton(
                        ExportCopy.permissionSettingsButton.text,
                        systemImage: "gearshape",
                        role: .secondary,
                        accessibilityID: ExportAccessibilityID.permissionSettingsButton.rawValue
                    ) {
                        onOpenSettings()
                    }
                }

                if canShare {
                    PrimaryButton(
                        ExportCopy.permissionShareButton.text,
                        systemImage: "square.and.arrow.up",
                        role: .primary,
                        accessibilityID: ExportAccessibilityID.permissionShareButton.rawValue
                    ) {
                        onShare()
                    }
                }

                if access == .denied || access == .restricted || access == .unavailable {
                    PrimaryButton(
                        ExportCopy.permissionRetryButton.text,
                        role: .secondary,
                        accessibilityID: ExportAccessibilityID.permissionRetryButton.rawValue
                    ) {
                        onRetry()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.permissionNotice.rawValue)
    }

    private var title: ExportText {
        switch access {
        case .restricted: return ExportCopy.permissionRestrictedTitle
        case .unavailable: return ExportCopy.failureLibraryUnavailableTitle
        case .denied, .notDetermined, .authorized, .limited:
            return ExportCopy.permissionDeniedTitle
        }
    }

    private var message: ExportText {
        switch access {
        case .restricted: return ExportCopy.permissionRestrictedMessage
        case .unavailable: return ExportCopy.permissionUnavailableNote
        case .denied, .notDetermined, .authorized, .limited:
            return ExportCopy.permissionDeniedMessage
        }
    }
}

// MARK: - Quota

@MainActor
struct ExportQuotaExhaustedCard: View {
    let onUpgrade: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard(borderColor: .borderStrong) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: ExportCopy.quotaExhaustedTitle.text)
                    .styleToneText(.sectionTitle)

                Text(verbatim: ExportCopy.quotaExhaustedMessage.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    ExportCopy.upgradeButton.text,
                    systemImage: "sparkles",
                    role: .primary,
                    accessibilityID: ExportAccessibilityID.quotaUpgradeButton.rawValue
                ) {
                    onUpgrade()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.quotaNotice.rawValue)
    }
}

@MainActor
struct ExportQuotaLoadFailedCard: View {
    let onRetry: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard(borderColor: .warning) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: ExportCopy.quotaLoadFailedTitle.text)
                    .styleToneText(.sectionTitle)

                Text(verbatim: ExportCopy.quotaLoadFailedMessage.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    ExportCopy.quotaRetryButton.text,
                    role: .secondary,
                    accessibilityID: ExportAccessibilityID.quotaRetryButton.rawValue
                ) {
                    onRetry()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.quotaNotice.rawValue)
    }
}

// MARK: - Failure

@MainActor
struct ExportFailureCard: View {
    let failure: ExportFailure
    let onRecovery: @MainActor (ExportFailure.Recovery) -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard(borderColor: .error) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: failure.title.text)
                    .styleToneText(.sectionTitle)

                Text(verbatim: failure.message.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(failure.recoveries, id: \.self) { recovery in
                    PrimaryButton(
                        ExportCopy.recoveryTitle(recovery).text,
                        systemImage: symbolName(for: recovery),
                        role: role(for: recovery),
                        accessibilityID: ExportAccessibilityID.failureButton(recovery).rawValue
                    ) {
                        onRecovery(recovery)
                    }
                }

                Text(verbatim: ExportCopy.diagnosticText(failure.diagnosticCode))
                    .styleToneText(.caption, color: .textTertiary)
                    .accessibilityIdentifier(ExportAccessibilityID.failureDiagnostic.rawValue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.failure.rawValue)
    }

    private func role(for recovery: ExportFailure.Recovery) -> PrimaryButton.Role {
        recovery == .retry || recovery == .upgrade ? .primary : .secondary
    }

    private func symbolName(for recovery: ExportFailure.Recovery) -> String {
        switch recovery {
        case .retry: return "arrow.clockwise"
        case .shareInstead: return "square.and.arrow.up"
        case .saveInstead: return "square.and.arrow.down"
        case .openSettings: return "gearshape"
        case .upgrade: return "sparkles"
        case .dismiss: return "xmark"
        }
    }
}

// MARK: - Result

@MainActor
struct ExportResultCard: View {
    let title: String
    let message: String
    let detail: String?
    let countPending: Bool
    let onDone: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard(borderColor: .success) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(theme.typography.font(.sectionTitle))
                        .foregroundStyle(theme.color(.success))
                        .accessibilityHidden(true)

                    Text(verbatim: title)
                        .styleToneText(.sectionTitle)
                }

                Text(verbatim: message)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(verbatim: detail)
                        .styleToneText(.caption, color: .textTertiary)
                        .accessibilityIdentifier(ExportAccessibilityID.resultDetail.rawValue)
                }

                if countPending {
                    Text(verbatim: ExportCopy.outcomeCountPending.text)
                        .styleToneText(.caption, color: .warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            ExportAccessibilityID.resultCountPending.rawValue
                        )
                }

                PrimaryButton(
                    ExportCopy.doneButton.text,
                    role: .secondary,
                    accessibilityID: ExportAccessibilityID.resultDoneButton.rawValue
                ) {
                    onDone()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.result.rawValue)
    }
}

// MARK: - Cancelled / info

@MainActor
struct ExportCancelledCard: View {
    let onRetry: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ExportCard {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(verbatim: ExportCopy.cancelledMessage.text)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    ExportCopy.retryButton.text,
                    systemImage: "arrow.clockwise",
                    role: .secondary,
                    accessibilityID: ExportAccessibilityID.cancelledRetryButton.rawValue
                ) {
                    onRetry()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.cancelledNotice.rawValue)
    }
}

@MainActor
struct ExportInfoBanner: View {
    let text: String
    let onDismiss: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var dismissTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: "info.circle.fill")
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: text)
                .styleToneText(.body, color: .textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.textSecondary))
                    .frame(width: dismissTarget, height: dismissTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: ExportCopy.dismissButton.text))
            .accessibilityIdentifier(ExportAccessibilityID.infoDismissButton.rawValue)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ExportAccessibilityID.infoNotice.rawValue)
    }
}
