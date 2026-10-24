import CoreGraphics
import StyleToneCore
import SwiftUI

/// Photo preview surface with the frozen 18% grey background.
///
/// The canvas is colour-neutral so the photograph dominates judgement. When no
/// image is supplied it shows a localized empty state instead of a blank box.
public struct PhotoCanvas: View {
    private let image: ImageAsset?
    private let aspectRatio: CGFloat?
    private let emptyTitle: String
    private let emptyMessage: String?
    private let accessibilityLabel: String?
    private let accessibilityID: String

    @Environment(\.styleToneTheme) private var theme

    /// - Parameters:
    ///   - image: Optional immutable image from `StyleToneCore`.
    ///   - aspectRatio: Optional width / height ratio. Without it the canvas
    ///     uses `LayoutMetrics.photoMinHeight`.
    ///   - emptyTitle: Localized empty-state title (also the accessibility
    ///     label when no image is present).
    ///   - emptyMessage: Optional localized empty-state detail.
    ///   - accessibilityLabel: Localized description for a real photo. When
    ///     omitted and an image is present, the photo is treated as decorative.
    ///   - accessibilityID: `screen.element` identifier for the canvas.
    public init(
        image: ImageAsset?,
        aspectRatio: CGFloat? = nil,
        emptyTitle: String,
        emptyMessage: String? = nil,
        accessibilityLabel: String? = nil,
        accessibilityID: String = AccessibilityID.designSystemPhotoCanvas.rawValue
    ) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityID = accessibilityID
    }

    public var body: some View {
        accessibleCanvas
    }

    @ViewBuilder
    private var accessibleCanvas: some View {
        if let label = resolvedAccessibilityLabel {
            sizedCanvas
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityIdentifier(accessibilityID)
        } else {
            sizedCanvas
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var sizedCanvas: some View {
        if let aspectRatio, aspectRatio > 0 {
            canvas.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            canvas.frame(minHeight: theme.metrics.photoMinHeight)
        }
    }

    private var canvas: some View {
        ZStack {
            theme.color(.photoBackground)

            if let image {
                Image(decorative: image.cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                emptyState
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.sm) {
            Image(systemName: "photo")
                .font(theme.typography.font(.screenTitle))
                .foregroundStyle(theme.color(.onPhotoSecondary))
                .accessibilityHidden(true)

            Text(verbatim: emptyTitle)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.onPhoto))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let emptyMessage {
                Text(verbatim: emptyMessage)
                    .font(theme.typography.font(.caption))
                    .foregroundStyle(theme.color(.onPhotoSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.spacing.lg)
    }

    private var resolvedAccessibilityLabel: String? {
        if let accessibilityLabel {
            return accessibilityLabel
        }
        return image == nil ? emptyTitle : nil
    }
}
