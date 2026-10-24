import Foundation
import SwiftUI

/// A transient status message.
///
/// Presentation timing is owned by the presenter (the app shell for placeholder
/// screens, WP-23 for error presentation); this value only carries copy and
/// metadata so it stays testable and `Sendable`.
public struct ToastMessage: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case info
        case success
        case warning
        case error
    }

    public let id: UUID
    /// Already-localized message text.
    public let text: String
    public let kind: Kind
    /// Seconds before auto-dismissal. `0` marks a persistent message.
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        text: String,
        kind: Kind = .info,
        duration: TimeInterval = 4
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.duration = max(0, duration)
    }

    public var isPersistent: Bool {
        duration == 0
    }
}

/// Toast surface. Place it in a safe-area inset or overlay managed by the
/// presenter; the design system does not schedule dismissal.
public struct ToastView: View {
    private let message: ToastMessage
    private let dismissLabel: String
    private let accessibilityID: String
    private let onDismiss: (@MainActor () -> Void)?

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scaledDismissTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    public init(
        message: ToastMessage,
        dismissLabel: String,
        accessibilityID: String = AccessibilityID.designSystemToast.rawValue,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.message = message
        self.dismissLabel = dismissLabel
        self.accessibilityID = accessibilityID
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: symbolName)
                .font(theme.typography.font(.body))
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            Text(verbatim: message.text)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.textPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(theme.color(.textSecondary))
                        .frame(width: scaledDismissTarget, height: scaledDismissTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityID).dismissButton")
                .accessibilityLabel(Text(verbatim: dismissLabel))
            }
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: theme.metrics.toastMaxWidth)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.borderStrong), lineWidth: theme.metrics.hairline)
        }
        .shadow(
            color: theme.color(.scrim).opacity(0.35),
            radius: 12,
            x: 0,
            y: 6
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }

    private var symbolName: String {
        switch message.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var accentColor: Color {
        switch message.kind {
        case .info: return theme.color(.accent)
        case .success: return theme.color(.success)
        case .warning: return theme.color(.warning)
        case .error: return theme.color(.error)
        }
    }
}
