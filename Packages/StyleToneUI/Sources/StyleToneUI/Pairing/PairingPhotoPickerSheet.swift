import SwiftUI

/// Presents the system photo picker for one request.
///
/// The iOS implementation is a `PHPickerViewController`; every other platform
/// gets an explicit unavailable view instead of an empty sheet. The sheet never
/// asks for photo-library authorization: PHPicker runs out of process.
@MainActor
struct PairingPhotoPickerSheet: View {
    let request: PairingPickRequest
    let onPicked: @MainActor ([PairingPickedPhoto]) -> Void
    let onCancel: @MainActor () -> Void
    let onFailed: @MainActor (PairingImportError) -> Void
    let onDismissUnavailable: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        #if canImport(UIKit) && canImport(PhotosUI)
        PairingSystemPhotoPicker(
            selectionLimit: request.mode.selectionLimit,
            onPicked: onPicked,
            onCancel: onCancel,
            onFailed: onFailed
        )
        #else
        unavailableContent
        #endif
    }

    #if !canImport(UIKit) || !canImport(PhotosUI)
    private var unavailableContent: some View {
        VStack(spacing: theme.spacing.lg) {
            Spacer(minLength: 0)

            Image(systemName: "hand.raised.fill")
                .font(theme.typography.font(.screenTitle))
                .foregroundStyle(theme.color(.warning))
                .accessibilityHidden(true)

            Text(verbatim: PairingCopy.pickerUnavailableTitle.text)
                .styleToneText(.sectionTitle)
                .multilineTextAlignment(.center)

            Text(verbatim: PairingCopy.pickerUnavailableMessage.text)
                .styleToneText(.body, color: .textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(
                PairingCopy.cancel.text,
                role: .secondary,
                accessibilityID: PairingAccessibilityID.pickerUnavailableDismiss.rawValue
            ) {
                onDismissUnavailable()
            }

            Spacer(minLength: 0)
        }
        .padding(theme.spacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.background).ignoresSafeArea())
        .accessibilityIdentifier(PairingAccessibilityID.pickerUnavailable.rawValue)
    }
    #endif
}
