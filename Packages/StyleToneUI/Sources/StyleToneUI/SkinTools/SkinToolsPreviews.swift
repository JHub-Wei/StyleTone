#if DEBUG
import CoreGraphics
import Foundation
import StyleToneCore
import SwiftUI

/// Deterministic preview fixtures for the skin-tools panel.
///
/// The image is the design-system synthetic gradient (no real photograph).
/// The preview engine returns its input, so previews exercise layout, copy,
/// markers and gestures without running the real pixel pipeline.
@MainActor
private enum SkinToolsPreviewData {
    static func model(face: Bool) -> SkinToolsViewModel? {
        guard let image = DesignSystemPreviewData.sampleImage() else { return nil }

        let analysis = analysis(for: image, face: face)
        return SkinToolsViewModel(
            image: image,
            analysis: analysis,
            retoucher: SkinToolsPreviewEngine(),
            blemishRemover: SkinToolsPreviewEngine(),
            configuration: .standard
        )
    }

    private static func analysis(for image: ImageAsset, face: Bool) -> PortraitAnalysis {
        let faces: [FaceObservation]
        if face {
            faces = [
                FaceObservation(
                    boundingBox: NormalizedRect(x: 0.28, y: 0.18, width: 0.44, height: 0.44),
                    landmarks: [:],
                    confidence: 0.9
                )
            ]
        } else {
            faces = []
        }

        let mask = try? MaskBuffer(
            width: image.pixelSize.width,
            height: image.pixelSize.height,
            bytes: Data(
                repeating: 255,
                count: image.pixelSize.width * image.pixelSize.height
            )
        )

        return PortraitAnalysis(
            imageSize: image.pixelSize,
            faces: faces,
            body: nil,
            personMask: nil,
            skinMask: mask,
            backgroundEdgeMask: nil,
            warnings: faces.isEmpty ? [.noFace] : []
        )
    }
}

private struct SkinToolsPreviewEngine: RetouchRendering, BlemishRemoving {
    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        image
    }

    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        image
    }
}

@MainActor
private struct SkinToolsPanelPreview: View {
    let model: SkinToolsViewModel?

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ScrollView {
            if let model {
                SkinToolsPanel(model: model)
                    .padding(theme.spacing.lg)
            } else {
                Text(verbatim: "Preview image unavailable")
                    .padding(theme.spacing.lg)
            }
        }
        .background(theme.color(.background).ignoresSafeArea())
        .preferredColorScheme(theme.colorScheme)
    }
}

#Preview("Skin tools / face") {
    SkinToolsPanelPreview(model: SkinToolsPreviewData.model(face: true))
        .styleToneTheme(.dark)
}

#Preview("Skin tools / no face") {
    SkinToolsPanelPreview(model: SkinToolsPreviewData.model(face: false))
        .styleToneTheme(.dark)
}

#Preview("Skin tools / light") {
    SkinToolsPanelPreview(model: SkinToolsPreviewData.model(face: true))
        .styleToneTheme(.light)
}

#Preview("Skin tools / large type") {
    SkinToolsPanelPreview(model: SkinToolsPreviewData.model(face: true))
        .styleToneTheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
