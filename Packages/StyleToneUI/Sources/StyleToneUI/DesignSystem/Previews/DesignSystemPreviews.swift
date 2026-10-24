#if DEBUG
import CoreGraphics
import StyleToneCore
import SwiftUI

/// Previews for the design-system tokens and components.
///
/// Everything here is synthetic: no real photographs are used. Run the Xcode
/// canvas on any component to inspect dark, light, increased-contrast and
/// accessibility Dynamic Type layouts.
enum DesignSystemPreviewData {
    static func sampleImage(size: CGSize = CGSize(width: 900, height: 1125)) -> ImageAsset? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }

        let gradientColors = [
            CGColor(colorSpace: space, components: [0.10, 0.12, 0.16, 1.0]),
            CGColor(colorSpace: space, components: [0.36, 0.30, 0.26, 1.0]),
            CGColor(colorSpace: space, components: [0.72, 0.58, 0.44, 1.0]),
        ].compactMap { $0 }

        if let gradient = CGGradient(
            colorsSpace: space,
            colors: gradientColors as CFArray,
            locations: [0, 0.6, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }

        // Abstract silhouette; synthetic, never a real person.
        if let hair = CGColor(colorSpace: space, components: [0.12, 0.10, 0.09, 1.0]),
           let skin = CGColor(colorSpace: space, components: [0.78, 0.64, 0.50, 1.0]) {
            context.setFillColor(hair)
            context.fillEllipse(
                in: CGRect(
                    x: size.width * 0.24,
                    y: size.height * 0.50,
                    width: size.width * 0.52,
                    height: size.height * 0.44
                )
            )
            context.setFillColor(skin)
            context.fillEllipse(
                in: CGRect(
                    x: size.width * 0.30,
                    y: size.height * 0.28,
                    width: size.width * 0.40,
                    height: size.height * 0.44
                )
            )
        }

        guard let cgImage = context.makeImage() else { return nil }
        return ImageAsset(cgImage: cgImage, colorSpace: space)
    }
}

private struct TokenGalleryPreview: View {
    @Environment(\.styleToneTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: theme.spacing.sm) {
                ForEach(ColorToken.allCases, id: \.self) { token in
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                            .fill(theme.color(token))
                            .frame(height: 56)
                            .overlay {
                                RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous)
                                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
                            }

                        Text(verbatim: token.rawValue)
                            .styleToneText(.caption)
                            .lineLimit(2)

                        Text(verbatim: theme.palette[token].hexString)
                            .styleToneText(.caption, color: .textSecondary)
                    }
                    .padding(theme.spacing.sm)
                    .background(
                        theme.color(.surface),
                        in: RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
                    )
                }
            }
            .padding(theme.spacing.screenHorizontal)
        }
        .background(theme.color(.background))
    }
}

private struct ComponentGalleryPreview: View {
    @State private var faceSlim = 0.35
    @State private var jaw = 0.20
    @State private var toast: ToastMessage? = ToastMessage(
        text: "Pair added. Quality checks arrive in WP-09.",
        kind: .success
    )

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                SectionHeader(
                    title: "Primary actions",
                    subtitle: "One primary action per screen; secondary actions stay quiet."
                )

                PrimaryButton(
                    "Start calibration",
                    systemImage: "slider.horizontal.3",
                    accessibilityID: AccessibilityID.calibrationStartButton.rawValue
                ) {}

                PrimaryButton(
                    "Continue with natural default",
                    role: .secondary,
                    accessibilityID: AccessibilityID.onboardingNaturalDefaultButton.rawValue
                ) {}

                PrimaryButton(
                    "Delete local data",
                    systemImage: "trash",
                    role: .destructive,
                    accessibilityID: AccessibilityID.settingsDeleteDataButton.rawValue
                ) {}

                PrimaryButton(
                    "Exporting",
                    isLoading: true,
                    accessibilityID: AccessibilityID.exportExportButton.rawValue
                ) {}

                PrimaryButton(
                    "Unavailable",
                    isEnabled: false,
                    accessibilityID: AccessibilityID.editorExportButton.rawValue
                ) {}

                SectionHeader(
                    title: "Tool sliders",
                    subtitle: "Value stays readable at accessibility text sizes."
                )

                SliderRow(
                    title: "Face slim",
                    value: $faceSlim,
                    systemImage: "face.smiling",
                    accessibilityID: AccessibilityID.editorFaceSlimSlider.rawValue
                )

                SliderRow(
                    title: "Jawline",
                    value: $jaw,
                    systemImage: "angle",
                    accessibilityID: "editor.jawSlider"
                )

                SectionHeader(
                    title: "Photo canvas",
                    subtitle: "Frozen 18% neutral grey behind photographs."
                )

                PhotoCanvas(
                    image: DesignSystemPreviewData.sampleImage(),
                    aspectRatio: 4.0 / 5.0,
                    emptyTitle: "Open a portrait",
                    accessibilityLabel: "Synthetic gradient preview image"
                )

                PhotoCanvas(
                    image: nil,
                    aspectRatio: 4.0 / 5.0,
                    emptyTitle: "Open a portrait to begin",
                    emptyMessage: "The photo picker is not connected in this shell build.",
                    accessibilityID: "designSystem.photoCanvas.empty"
                )

                SectionHeader(title: "Feedback")

                if let toast {
                    ToastView(
                        message: toast,
                        dismissLabel: "Dismiss",
                        onDismiss: { self.toast = nil }
                    )
                } else {
                    PrimaryButton(
                        "Show toast",
                        role: .secondary,
                        accessibilityID: "designSystem.toastPreview"
                    ) {
                        toast = ToastMessage(
                            text: "Pair import is not connected in this shell build.",
                            kind: .info
                        )
                    }
                }

                LoadingView(message: "Rendering at full resolution…", style: .inline)
                LoadingView(message: "Loading", style: .compact)
            }
            .padding(theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.screenVertical)
        }
        .background(theme.color(.background))
    }
}

#Preview("Design system / tokens") {
    TokenGalleryPreview()
        .styleToneTheme(.dark)
        .preferredColorScheme(.dark)
}

#Preview("Design system / components") {
    ComponentGalleryPreview()
        .styleToneTheme(.dark)
        .preferredColorScheme(.dark)
}

#Preview("Design system / large type") {
    ComponentGalleryPreview()
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility2)
        .styleToneTheme(.dark)
        .preferredColorScheme(.dark)
}

#Preview("Design system / increased contrast") {
    ComponentGalleryPreview()
        .styleToneTheme(.darkHighContrast)
        .preferredColorScheme(.dark)
}

#Preview("Design system / light") {
    ComponentGalleryPreview()
        .styleToneTheme(.light)
        .preferredColorScheme(.light)
}

#Preview("Photo canvas") {
    VStack(spacing: 16) {
        PhotoCanvas(
            image: DesignSystemPreviewData.sampleImage(),
            aspectRatio: 4.0 / 5.0,
            emptyTitle: "Open a portrait",
            accessibilityLabel: "Synthetic gradient preview image"
        )
        PhotoCanvas(
            image: nil,
            aspectRatio: 4.0 / 5.0,
            emptyTitle: "Open a portrait to begin",
            emptyMessage: "The photo picker is not connected in this shell build."
        )
    }
    .padding(20)
    .background(StyleToneTheme.dark.color(.background))
    .styleToneTheme(.dark)
    .preferredColorScheme(.dark)
}
#endif
