import SwiftUI
import StyleToneUI

/// Editor shell placeholder: canvas plus one face section and one skin section.
///
/// The four tool areas, proxy rendering, undo and real photo import belong to
/// WP-17/WP-16/WP-09; this screen exists to exercise the design system and
/// routing.
struct EditorPlaceholderScreen: View {
    let actions: ShellActions

    @Environment(\.styleToneTheme) private var theme
    @State private var faceSlim = 0.35
    @State private var jaw = 0.20
    @State private var smoothing = 0.25

    var body: some View {
        PlaceholderScreen(
            title: ShellCopy.editorTitle,
            subtitle: ShellCopy.editorSubtitle,
            screen: .editor
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                PhotoCanvas(
                    image: nil,
                    aspectRatio: 4.0 / 5.0,
                    emptyTitle: ShellCopy.editorCanvasEmptyTitle,
                    emptyMessage: ShellCopy.editorCanvasEmptyMessage,
                    accessibilityLabel: ShellCopy.editorCanvasEmptyTitle,
                    accessibilityID: AccessibilityID.editorCanvas.rawValue
                )

                SectionHeader(
                    title: ShellCopy.editorSectionFace,
                    subtitle: ShellCopy.editorSectionFaceNote
                )

                SliderRow(
                    title: ShellCopy.editorFaceSlim,
                    value: $faceSlim,
                    systemImage: "face.smiling",
                    accessibilityID: AccessibilityID.editorFaceSlimSlider.rawValue
                )

                SliderRow(
                    title: ShellCopy.editorJaw,
                    value: $jaw,
                    systemImage: "angle",
                    accessibilityID: AccessibilityID.editorJawSlider.rawValue
                )

                SectionHeader(
                    title: ShellCopy.editorSectionSkin,
                    subtitle: ShellCopy.editorSectionSkinNote
                )

                SliderRow(
                    title: ShellCopy.editorSmoothing,
                    value: $smoothing,
                    systemImage: "sparkles",
                    accessibilityID: AccessibilityID.editorSmoothingSlider.rawValue
                )

                VStack(spacing: theme.spacing.md) {
                    PrimaryButton(
                        ShellCopy.editorAddPhotoButton,
                        systemImage: "photo.badge.plus",
                        accessibilityID: AccessibilityID.editorAddPhotoButton.rawValue
                    ) {
                        actions.presentToast(ToastMessage(text: ShellCopy.editorToast, kind: .info))
                    }

                    PrimaryButton(
                        ShellCopy.editorExportButton,
                        systemImage: "square.and.arrow.up",
                        role: .secondary,
                        accessibilityID: AccessibilityID.editorExportButton.rawValue
                    ) {
                        actions.navigate(.export)
                    }

                    PrimaryButton(
                        ShellCopy.editorStyleButton,
                        systemImage: "person.crop.circle.badge.checkmark",
                        role: .secondary,
                        accessibilityID: AccessibilityID.editorStyleButton.rawValue
                    ) {
                        actions.navigate(.styleProfile)
                    }
                }

                Text(verbatim: ShellCopy.editorNote)
                    .styleToneText(.caption, color: .textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
