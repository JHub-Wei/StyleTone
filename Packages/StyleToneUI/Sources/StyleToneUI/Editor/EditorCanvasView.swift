import Foundation
import StyleToneCore
import SwiftUI

/// Photo preview with long-press compare, split compare and pinch zoom.
///
/// The canvas displays `displayedImage` (a proxy while dragging, full quality
/// after release). Split compare overlays the original on the left side and
/// keeps the rendered image on the right. Long press temporarily shows the
/// original without touching render state or export.
@MainActor
struct EditorCanvasView: View {
    let model: EditorViewModel

    @Environment(\.styleToneTheme) private var theme
    @State private var pinchStartScale: Double?
    @State private var splitDragStart: Double?
    @State private var lastPanTranslation: CGSize = .zero

    var body: some View {
        Group {
            if let ratio = photoAspectRatio {
                canvas.aspectRatio(ratio, contentMode: .fit)
            } else {
                emptyCanvas
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                theme.color(.photoBackground)

                photoLayer(size: size)

                if model.isSplitComparisonEnabled, !model.isShowingOriginal, model.image != nil {
                    splitLabels(size: size)
                        .allowsHitTesting(false)
                }

                if model.isSplitComparisonEnabled, !model.isShowingOriginal, model.image != nil {
                    splitHandle(size: size)
                }

                if model.isRendering {
                    renderingIndicator
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(theme.spacing.sm)
                        .allowsHitTesting(false)
                }

                if model.isPerformanceDegraded {
                    statusBadge(
                        EditorCopy.text(EditorCopy.degradedBadge),
                        systemImage: "speedometer"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(theme.spacing.sm)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }

                if model.displayedQuality == .preview, !model.isRendering {
                    statusBadge(
                        EditorCopy.text(EditorCopy.previewBadge),
                        systemImage: "hourglass"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(theme.spacing.sm)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
            }
        }
    }

    private var emptyCanvas: some View {
        PhotoCanvas(
            image: nil,
            aspectRatio: 4.0 / 5.0,
            emptyTitle: EditorCopy.text(EditorCopy.canvasEmptyTitle),
            emptyMessage: EditorCopy.text(EditorCopy.canvasEmptyMessage),
            accessibilityLabel: EditorCopy.text(EditorCopy.canvasEmptyTitle),
            accessibilityID: AccessibilityID.editorCanvas.rawValue
        )
    }

    private func photoLayer(size: CGSize) -> some View {
        ZStack {
            if let base = baseImage {
                photo(base, size: size)
            }

            if model.isSplitComparisonEnabled,
               !model.isShowingOriginal,
               let original = model.image {
                photo(original, size: size)
                    .mask(splitMask(size: size))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(magnificationGesture)
        .simultaneousGesture(panGesture(size: size))
        .onLongPressGesture(
            minimumDuration: 0.2,
            maximumDistance: 40,
            perform: {},
            onPressingChanged: { pressing in
                model.setShowingOriginal(pressing)
            }
        )
        .onTapGesture(count: 2) {
            model.toggleZoom()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: EditorCopy.text(EditorCopy.canvasLabel)))
        .accessibilityHint(Text(verbatim: EditorCopy.text(EditorCopy.canvasHint)))
        .accessibilityIdentifier(AccessibilityID.editorCanvas.rawValue)
    }

    private func photo(_ image: ImageAsset, size: CGSize) -> some View {
        Image(decorative: image.cgImage, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .scaleEffect(CGFloat(model.zoom.scale))
            .offset(
                x: CGFloat(model.zoom.offsetX) * size.width / 2,
                y: CGFloat(model.zoom.offsetY) * size.height / 2
            )
    }

    private var baseImage: ImageAsset? {
        if model.isShowingOriginal {
            return model.image ?? model.displayedImage
        }
        return model.displayedImage
    }

    private var photoAspectRatio: CGFloat? {
        guard let image = model.image, image.pixelSize.height > 0 else { return nil }
        return CGFloat(image.pixelSize.width) / CGFloat(image.pixelSize.height)
    }

    // MARK: - Split comparison

    private func splitMask(size: CGSize) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.white)
                .frame(width: max(0, size.width * CGFloat(model.splitPosition)))
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    private func splitLabels(size: CGSize) -> some View {
        HStack {
            Text(verbatim: EditorCopy.text(EditorCopy.compareOriginal))
                .styleToneText(.caption, color: .onPhoto)
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xxs)
                .background(theme.color(.scrim).opacity(0.55), in: Capsule())

            Spacer(minLength: theme.spacing.sm)

            Text(verbatim: EditorCopy.text(EditorCopy.compareEdited))
                .styleToneText(.caption, color: .onPhoto)
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xxs)
                .background(theme.color(.scrim).opacity(0.55), in: Capsule())
        }
        .padding(theme.spacing.sm)
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityHidden(true)
    }

    private func splitHandle(size: CGSize) -> some View {
        let x = max(0, min(size.width, size.width * CGFloat(model.splitPosition)))
        return ZStack {
            Rectangle()
                .fill(theme.color(.onPhoto))
                .frame(width: theme.metrics.hairline * 2, height: size.height)

            Circle()
                .fill(theme.color(.accent))
                .frame(
                    width: theme.metrics.iconLarge + theme.spacing.xs,
                    height: theme.metrics.iconLarge + theme.spacing.xs
                )
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(theme.color(.onAccent))
                        .accessibilityHidden(true)
                }
        }
        .frame(width: max(theme.metrics.minTouchTarget, theme.metrics.iconLarge), height: size.height)
        .contentShape(Rectangle())
        .position(x: x, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if splitDragStart == nil {
                        splitDragStart = model.splitPosition
                    }
                    let start = splitDragStart ?? model.splitPosition
                    let delta = Double(value.translation.width / max(size.width, 1))
                    model.setSplitPosition(start + delta)
                }
                .onEnded { _ in
                    splitDragStart = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: EditorCopy.text(EditorCopy.splitComparison)))
        .accessibilityValue(
            Text(verbatim: model.splitPosition.formatted(.percent.precision(.fractionLength(0))))
        )
        .accessibilityIdentifier(EditorAccessibility.splitHandle.rawValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                model.setSplitPosition(model.splitPosition + 0.02)
            case .decrement:
                model.setSplitPosition(model.splitPosition - 0.02)
            @unknown default:
                break
            }
        }
    }

    // MARK: - Status

    private var renderingIndicator: some View {
        HStack(spacing: theme.spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.color(.onPhoto))
                .accessibilityHidden(true)

            Text(verbatim: renderingText)
                .styleToneText(.caption, color: .onPhoto)
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .background(theme.color(.scrim).opacity(0.55), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: renderingText))
        .accessibilityIdentifier(EditorAccessibility.renderingIndicator.rawValue)
    }

    private var renderingText: String {
        switch model.renderState {
        case .rendering(.preview):
            return EditorCopy.text(EditorCopy.renderingPreview)
        case .rendering(.full):
            return EditorCopy.text(EditorCopy.renderingFull)
        case .idle, .ready(_), .failed:
            return EditorCopy.text(EditorCopy.renderingPreview)
        }
    }

    private func statusBadge(_ text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text)
                .styleToneText(.caption, color: .onPhoto)
        } icon: {
            Image(systemName: systemImage)
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.onPhoto))
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xxs)
        .background(theme.color(.scrim).opacity(0.55), in: Capsule())
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = model.zoom.scale
                }
                let start = pinchStartScale ?? model.zoom.scale
                model.setZoomScale(start * Double(value.magnification))
            }
            .onEnded { _ in
                pinchStartScale = nil
            }
    }

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard model.zoom.isZoomed else { return }
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                let deltaX = value.translation.width - lastPanTranslation.width
                let deltaY = value.translation.height - lastPanTranslation.height
                lastPanTranslation = value.translation
                model.panBy(
                    x: Double(deltaX / width) * 2,
                    y: Double(deltaY / height) * 2
                )
            }
            .onEnded { _ in
                lastPanTranslation = .zero
            }
    }
}
