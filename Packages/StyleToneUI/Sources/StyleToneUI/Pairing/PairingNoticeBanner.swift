import SwiftUI

/// Inline banner for restored sessions, save failures and picker problems.
@MainActor
struct PairingNoticeBanner: View {
    let notice: PairingNotice
    let onAction: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: symbolName)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(token))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(verbatim: notice.title.text)
                    .styleToneText(.label)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = notice.message {
                    Text(verbatim: message.text)
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if notice.action != nil, let actionTitle = notice.actionTitle {
                    Button(action: onAction) {
                        Text(verbatim: actionTitle.text)
                            .font(theme.typography.font(.label))
                            .foregroundStyle(theme.color(.accent))
                            .frame(minHeight: theme.metrics.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: actionTitle.text))
                    .accessibilityIdentifier(
                        PairingAccessibilityID.noticeAction.rawValue
                    )
                }
            }

            Spacer(minLength: 0)

            if notice.isDismissible {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(theme.color(.textSecondary))
                        .frame(
                            width: theme.metrics.minTouchTarget,
                            height: theme.metrics.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: PairingCopy.dismissNotice.text))
                .accessibilityIdentifier(
                    PairingAccessibilityID.noticeDismiss.rawValue
                )
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.color(token).opacity(0.12),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(
                    theme.color(token).opacity(0.35),
                    lineWidth: theme.metrics.hairline
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PairingAccessibilityID.notice.rawValue)
    }

    private var token: ColorToken {
        switch notice.kind {
        case .info: return .accent
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }

    private var symbolName: String {
        switch notice.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
