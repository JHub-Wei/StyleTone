#if canImport(UIKit) && canImport(PhotosUI)
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// SwiftUI host for the out-of-process `PHPickerViewController`.
///
/// PHPicker needs no photo-library authorization: the picker runs in a
/// separate process and only hands back the items the user selected. The
/// configuration references the shared library only so the picker can attach
/// opaque asset identifiers, which let the UI notice an identical
/// original/edited pick. No permission check, authorization request or library
/// fetch happens anywhere in the module.
@MainActor
struct PairingSystemPhotoPicker: View {
    /// Maximum number of items the picker accepts.
    let selectionLimit: Int
    /// Called on the main actor with the selected payloads, in selection order.
    let onPicked: @MainActor ([PairingPickedPhoto]) -> Void
    /// Called on the main actor when the user cancels.
    let onCancel: @MainActor () -> Void
    /// Called on the main actor when a payload cannot be read.
    let onFailed: @MainActor (PairingImportError) -> Void

    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        PairingPHPickerViewController(
            selectionLimit: selectionLimit,
            onResults: { results in
                handle(results)
            }
        )
        .ignoresSafeArea()
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func handle(_ results: [PHPickerResult]) {
        guard !results.isEmpty else {
            onCancel()
            return
        }

        let items = results.map { result in
            PickedItem(
                provider: result.itemProvider,
                identifier: result.assetIdentifier
            )
        }

        loadTask?.cancel()
        loadTask = Task { @MainActor in
            var picked: [PairingPickedPhoto] = []
            do {
                for item in items {
                    try Task.checkCancellation()
                    let data = try await PairingPhotoDataLoader.load(from: item.provider)
                    picked.append(
                        PairingPickedPhoto(
                            data: data,
                            sourceIdentifier: item.identifier
                        )
                    )
                }
                guard !Task.isCancelled else { return }
                onPicked(picked)
            } catch is CancellationError {
                return
            } catch let error as PairingImportError {
                onFailed(error)
            } catch {
                onFailed(.unknown)
            }
        }
    }

    /// One selected item plus the identifier the picker attached to it.
    ///
    /// `NSItemProvider` is not `Sendable`, but its documented loading API is
    /// thread-safe and the value is only touched from the main-actor task that
    /// consumes it. The unchecked conformance states that contract explicitly
    /// instead of hopping the provider across actors.
    private struct PickedItem: @unchecked Sendable {
        let provider: NSItemProvider
        let identifier: String?
    }
}

/// Reads the file data behind one picked item.
///
/// Main-actor bound because `NSItemProvider` is not `Sendable` and the value is
/// only ever produced and consumed on the main actor.
@MainActor
enum PairingPhotoDataLoader {
    /// Loads the image payload for a picked item.
    ///
    /// The completion handler runs on an arbitrary queue, so it only resumes a
    /// continuation; all view-model work stays on the main actor.
    static func load(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let identifier = UTType.image.identifier
            guard provider.hasItemConformingToTypeIdentifier(identifier) else {
                continuation.resume(throwing: PairingImportError.unreadableData)
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if error != nil {
                    continuation.resume(throwing: PairingImportError.unreadableData)
                } else {
                    continuation.resume(throwing: PairingImportError.noImageData)
                }
            }
        }
    }
}

/// The raw `PHPickerViewController` wrapper.
@MainActor
private struct PairingPHPickerViewController: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onResults: @MainActor ([PHPickerResult]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResults: onResults)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, selectionLimit)
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onResults = onResults
    }

    /// Delegate bridge.
    ///
    /// `PHPickerViewControllerDelegate` is `@MainActor @preconcurrency` in the
    /// current SDK, so the coordinator is main-actor bound and can forward the
    /// results directly. No `Task` hop is needed, which matters because
    /// `PHPickerResult` is not `Sendable`.
    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onResults: @MainActor ([PHPickerResult]) -> Void

        init(onResults: @escaping @MainActor ([PHPickerResult]) -> Void) {
            self.onResults = onResults
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            onResults(results)
        }
    }
}
#endif
