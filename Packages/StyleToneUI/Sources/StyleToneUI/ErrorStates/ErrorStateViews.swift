import SwiftUI

// MARK: - Card

/// Shared error surface: title, message, recovery buttons and support code.
///
/// Pages may embed the card inline or let ``ErrorPresenter`` present it through
/// the ``SwiftUI/View/errorStatePresentation(_:)`` modifier. The card uses only
/// design-system tokens and public components, so adopting it does not change a
/// screen's visual language.
@MainActor
public struct ErrorStateCard: View {
    private let state: ErrorState
    private let onRecovery: @MainActor (RecoveryAction) -> Void

    @Environment(\.styleToneTheme) private var theme

    public init(
        state: ErrorState,
        onRecovery: @escaping @MainActor (RecoveryAction) -> Void
    ) {
        self.state = state
        self.onRecovery = onRecovery
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                Image(systemName: symbolName)
                    .font(theme.typography.font(.sectionTitle))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                Text(verbatim: state.title.text)
                    .styleToneText(.sectionTitle)
            }

            Text(verbatim: state.message.text)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(state.recoveryActions, id: \.self) { action in
                PrimaryButton(
                    action.title.text,
                    systemImage: action.systemImage,
                    role: role(for: action),
                    accessibilityID: ErrorStateAccessibility.actionButton(action).rawValue
                ) {
                    onRecovery(action)
                }
            }

            Text(verbatim: state.diagnosticText)
                .styleToneText(.caption, color: .textTertiary)
                .accessibilityIdentifier(ErrorStateAccessibility.diagnostic.rawValue)
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(accentColor, lineWidth: theme.metrics.hairline)
        }
        .shadow(
            color: theme.color(.scrim).opacity(0.35),
            radius: 12,
            x: 0,
            y: 6
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ErrorStateAccessibility.card.rawValue)
    }

    private var accentColor: Color {
        state.severity == .notice ? theme.color(.warning) : theme.color(.error)
    }

    private var symbolName: String {
        state.severity == .notice
            ? "exclamationmark.triangle.fill"
            : "xmark.octagon.fill"
    }

    private func role(for action: RecoveryAction) -> PrimaryButton.Role {
        guard let primary = state.primaryAction else { return .secondary }
        return primary == action ? .primary : .secondary
    }
}

// MARK: - Presentation hook

/// One-line page hook: overlays the current error card and transient toast.
///
/// The owning screen keeps its view model, tasks and recovery commands. It only
/// needs to inject the shared presenter and call `present(_:)` with a mapped
/// state.
@MainActor
public extension View {
    func errorStatePresentation(_ presenter: ErrorPresenter) -> some View {
        modifier(ErrorStatePresentationModifier(presenter: presenter))
    }
}

@MainActor
private struct ErrorStatePresentationModifier: ViewModifier {
    let presenter: ErrorPresenter

    @Environment(\.styleToneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let state = presenter.current {
                    ErrorStateCard(state: state) { action in
                        presenter.perform(action)
                    }
                    .padding(theme.spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let toast = presenter.toast {
                    ToastView(
                        message: toast,
                        dismissLabel: ErrorCopy.actionTitle(.dismiss).text,
                        onDismiss: { presenter.dismissToast(id: toast.id) }
                    )
                    .padding(theme.spacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        guard toast.duration > 0 else { return }
                        try? await Task.sleep(for: .seconds(toast.duration))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            presenter.dismissToast(id: toast.id)
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: presenter.current?.id)
            .animation(.easeOut(duration: 0.2), value: presenter.toast?.id)
    }
}
