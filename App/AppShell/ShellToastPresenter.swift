import Observation
import StyleToneUI

/// Owns the shell's transient toast presentation and its dismissal timer.
///
/// The design system deliberately provides only the toast view and model; a
/// single presenter owns timing so screens cannot create competing timers.
/// WP-23 can replace this with the shared error presenter.
@MainActor
@Observable
final class ShellToastPresenter {
    private(set) var message: ToastMessage?
    private var dismissalTask: Task<Void, Never>?

    func show(_ message: ToastMessage) {
        dismissalTask?.cancel()
        dismissalTask = nil
        self.message = message

        guard message.duration > 0 else { return }
        let duration = message.duration
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        message = nil
    }
}
