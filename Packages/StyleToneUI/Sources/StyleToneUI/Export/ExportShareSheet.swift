import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

/// System share sheet for one staged export file.
///
/// The completion handler is the only reliable signal that the user actually
/// shared the photo. It is de-duplicated so a sheet dismissal racing the
/// handler cannot count twice, and it always hops back to the main actor.
struct ExportShareSheet: UIViewControllerRepresentable {
    let request: ExportShareRequest
    let onComplete: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [request.url],
            applicationActivities: nil
        )
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, completed, _, _ in
            coordinator.finish(completed: completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    /// Bridges the Objective-C completion callback to the main-actor workflow.
    final class Coordinator: @unchecked Sendable {
        private let completion: ShareCompletion

        init(onComplete: @escaping @MainActor (Bool) -> Void) {
            self.completion = ShareCompletion(onComplete)
        }

        func finish(completed: Bool) {
            completion.finish(completed)
        }
    }
}

/// Runs the main-actor completion exactly once, whichever thread reports it.
private final class ShareCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let action: @MainActor (Bool) -> Void

    init(_ action: @escaping @MainActor (Bool) -> Void) {
        self.action = action
    }

    func finish(_ completed: Bool) {
        lock.lock()
        if didFinish {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        Task { @MainActor in
            self.action(completed)
        }
    }
}

/// Presents `ExportShareSheet` when the view model stages a share request.
@MainActor
struct ExportSharePresenter: ViewModifier {
    let viewModel: ExportViewModel

    init(viewModel: ExportViewModel) {
        self.viewModel = viewModel
    }

    func body(content: Content) -> some View {
        content.sheet(
            item: Binding<ExportShareRequest?>(
                get: { viewModel.pendingShare },
                set: { viewModel.pendingShare = $0 }
            )
        ) { request in
            ExportShareSheet(request: request) { completed in
                Task { @MainActor in
                    await viewModel.completeShare(request, completed: completed)
                }
            }
            .ignoresSafeArea()
        }
    }
}

#else

/// macOS/test fallback: the export screen is shipped on iOS only, where the
/// system share sheet exists.
@MainActor
struct ExportSharePresenter: ViewModifier {
    let viewModel: ExportViewModel

    init(viewModel: ExportViewModel) {
        self.viewModel = viewModel
    }

    func body(content: Content) -> some View {
        content
    }
}

#endif
