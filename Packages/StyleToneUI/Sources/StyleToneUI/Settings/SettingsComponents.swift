import SwiftUI

// MARK: - Card surface

/// The card surface shared by settings sections.
struct SettingsCardModifier: ViewModifier {
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

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Notice banner

/// Inline status banner for copy, diagnostics and deletion results.
@MainActor
struct SettingsNoticeBanner: View {
    let notice: SettingsNotice
    let dismiss: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: symbolName)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(token))
                .accessibilityHidden(true)

            Text(verbatim: notice.text)
                .styleToneText(.caption, color: .textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
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
            .accessibilityLabel(Text(verbatim: SettingsCopy.commonDismiss.text))
            .accessibilityIdentifier(
                "\(SettingsAccessibilityID.notice.rawValue).dismissButton"
            )
        }
        .padding(.leading, theme.spacing.md)
        .padding(.trailing, theme.spacing.xs)
        .padding(.vertical, theme.spacing.xs)
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
        .accessibilityIdentifier(SettingsAccessibilityID.notice.rawValue)
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

// MARK: - Link row

/// A navigation row with an icon, title, optional subtitle and chevron.
struct SettingsLinkLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: systemImage)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.accent))
                .frame(width: theme.metrics.iconLarge)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: title)
                    .styleToneText(.label)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: theme.spacing.sm)

            Image(systemName: "chevron.right")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Value row

/// A label/value row that stacks at accessibility Dynamic Type sizes.
struct SettingsValueRow: View {
    let label: String
    let value: String
    let accessibilityID: String

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize >= .accessibility1
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: theme.spacing.md))

        layout {
            Text(verbatim: label)
                .styleToneText(.caption, color: .textSecondary)

            if !isAccessibilitySize {
                Spacer(minLength: 0)
            }

            Text(verbatim: value)
                .styleToneText(.value, color: .textPrimary)
                .multilineTextAlignment(isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: theme.metrics.minTouchTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(label), \(value)"))
        .accessibilityIdentifier(accessibilityID)
    }
}

// MARK: - Bullet row

/// One line in a "what is collected" or "what stays here" list.
struct SettingsBulletRow: View {
    let text: String
    let systemImage: String
    let token: ColorToken

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Image(systemName: systemImage)
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(token))
                .frame(width: theme.metrics.iconSmall)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .styleToneText(.caption, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section divider

/// A thin divider using the border token.
struct SettingsDivider: View {
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        Divider()
            .overlay(theme.color(.border))
    }
}

// MARK: - Navigation title

/// Inline navigation title on platforms with a navigation bar.
struct SettingsInlineNavigationTitle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
