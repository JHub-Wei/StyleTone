import StyleToneCore
import SwiftUI

/// Zoomable, pannable blemish picker.
///
/// The view maps a tap to a normalized image point through
/// ``SkinToolsImageGeometry`` and hands it to the view model; it does not run
/// any pixel work. Pinch zooms, drag pans, and the plus/minus buttons in the
/// panel offer the same zoom for users who cannot pinch.
@MainActor
struct SkinToolsBlemishCanvas: View {
    private let model: SkinToolsViewModel

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 220

    @State private var panOffset: CGSize = .zero
    @State private var dragStartPan: CGSize = .zero
    @State private var isDragging = false
    @State private var isMagnifying = false
    @State private var magnifyStartZoom: Double = 1

    init(model: SkinToolsViewModel) {
        self.model = model
    }

    var body: some View {
        GeometryReader { proxy in
            let imageSize = CGSize(
                width: CGFloat(model.displayedImage.pixelSize.width),
                height: CGFloat(model.displayedImage.pixelSize.height)
            )
            let imageGeometry = geometry(containerSize: proxy.size, imageSize: imageSize)

            ZStack(alignment: .topLeading) {
                theme.color(.photoBackground)

                Image(decorative: model.displayedImage.cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: imageGeometry.displayedSize.width,
                        height: imageGeometry.displayedSize.height
                    )
                    .position(
                        x: imageGeometry.imageOrigin.x + imageGeometry.displayedSize.width / 2,
                        y: imageGeometry.imageOrigin.y + imageGeometry.displayedSize.height / 2
                    )
                    .accessibilityHidden(true)

                markerLayer(geometry: imageGeometry)
                zoomBadge
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture(containerSize: proxy.size, imageSize: imageSize))
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                guard model.canApplyBlemish else { return }
                let tapGeometry = geometry(containerSize: proxy.size, imageSize: imageSize)
                guard let point = tapGeometry.normalizedPoint(at: location) else { return }
                model.addBlemish(at: point)
            }
            .onChange(of: model.zoomScale) { _, _ in
                panOffset = .zero
            }
        }
        .aspectRatio(imageAspectRatio, contentMode: .fit)
        .frame(minHeight: minimumHeight)
        .background(theme.color(.photoBackground))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(theme.color(.borderStrong), lineWidth: theme.metrics.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(SkinToolsAccessibilityID.blemishCanvas.rawValue)
        .accessibilityLabel(Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.canvasLabel)))
        .accessibilityValue(Text(verbatim: canvasValue))
        .accessibilityHint(Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.canvasHint)))
        .accessibilityAction(named: Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.applyAtCenter))) {
            Task { @MainActor in
                model.addBlemish(at: NormalizedPoint(x: 0.5, y: 0.5))
            }
        }
        .accessibilityAction(named: Text(verbatim: SkinToolsCopy.text(SkinToolsCopy.undoAction))) {
            Task { @MainActor in
                model.undoBlemish()
            }
        }
    }

    // MARK: Overlay

    @ViewBuilder
    private func markerLayer(geometry: SkinToolsImageGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.blemishes) { edit in
                marker(
                    geometry: geometry,
                    radius: edit.radius,
                    point: edit.point,
                    isPending: false
                )
            }

            if let pending = model.pendingBlemish {
                marker(
                    geometry: geometry,
                    radius: pending.radius,
                    point: pending.point,
                    isPending: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func marker(
        geometry: SkinToolsImageGeometry,
        radius: Double,
        point: NormalizedPoint,
        isPending: Bool
    ) -> some View {
        let diameter = geometry.markerDiameter(forRadius: radius)
        let center = geometry.viewPoint(for: point)

        return Group {
            if isPending {
                Circle()
                    .stroke(
                        theme.color(.warning),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                    )
            } else {
                Circle()
                    .fill(theme.color(.accent).opacity(0.16))
                    .overlay {
                        Circle()
                            .strokeBorder(theme.color(.accent), lineWidth: 2)
                    }
            }
        }
        .frame(width: diameter, height: diameter)
        .position(center)
        .accessibilityHidden(true)
    }

    private var zoomBadge: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Text(verbatim: SkinToolsCopy.format(
                    SkinToolsCopy.zoomValue,
                    Int(model.zoomScale.rounded())
                ))
                .styleToneText(.caption, color: .onPhoto)
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xxs)
                .background(theme.color(.scrim).opacity(0.55), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing.sm)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Gestures

    private func panGesture(containerSize: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard model.zoomScale > 1 else { return }
                if !isDragging {
                    isDragging = true
                    dragStartPan = panOffset
                }
                let geometry = SkinToolsImageGeometry(
                    containerSize: containerSize,
                    imageSize: imageSize,
                    zoomScale: model.zoomScale,
                    panOffset: dragStartPan
                )
                let proposed = CGSize(
                    width: dragStartPan.width + value.translation.width,
                    height: dragStartPan.height + value.translation.height
                )
                panOffset = geometry.clampedPanOffset(proposed)
            }
            .onEnded { _ in
                isDragging = false
                if model.zoomScale <= 1 {
                    panOffset = .zero
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isMagnifying {
                    isMagnifying = true
                    magnifyStartZoom = model.zoomScale
                }
                model.setZoom(magnifyStartZoom * Double(value.magnification))
            }
            .onEnded { _ in
                isMagnifying = false
                magnifyStartZoom = model.zoomScale
            }
    }

    // MARK: Geometry

    private func geometry(
        containerSize: CGSize,
        imageSize: CGSize
    ) -> SkinToolsImageGeometry {
        SkinToolsImageGeometry(
            containerSize: containerSize,
            imageSize: imageSize,
            zoomScale: model.zoomScale,
            panOffset: panOffset
        )
    }

    private var imageAspectRatio: CGFloat {
        let size = model.displayedImage.pixelSize
        guard size.height > 0, size.width > 0 else { return 1 }
        return CGFloat(size.width) / CGFloat(size.height)
    }

    private var canvasValue: String {
        let count = model.blemishes.count + (model.pendingBlemish == nil ? 0 : 1)
        return SkinToolsCopy.format(
            SkinToolsCopy.canvasValue,
            count,
            Int(model.zoomScale.rounded())
        )
    }
}
