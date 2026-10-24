import StyleToneCore
import SwiftUI

/// One photo slot inside a pair card: preview, replace and remove actions.
@MainActor
struct PairingPhotoSlotView: View {
    let slot: PairingSlot
    let pairNumber: Int
    let photo: PairingPhoto?
    let needsReselect: Bool
    let isEnabled: Bool
    let onPick: @MainActor () -> Void
    let onRemove: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            canvas

            Text(verbatim: PairingCopy.slotTitle(slot).text)
                .styleToneText(.label)
                .accessibilityIdentifier(
                    PairingAccessibilityID.slot(slot, pair: pairNumber).rawValue
                )

            if needsReselect {
                staleNote
            }

            pickButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack(alignment: .topTrailing) {
            PhotoCanvas(
                image: photo?.asset,
                aspectRatio: 4.0 / 5.0,
                emptyTitle: PairingCopy.slotEmptyHint.text,
                accessibilityLabel: photoAccessibilityLabel,
                accessibilityID: PairingAccessibilityID.photo(slot, pair: pairNumber).rawValue
            )

            if photo != nil {
                removeButton
                    .padding(theme.spacing.xs)
            }
        }
    }

    private var photoAccessibilityLabel: String {
        let title = PairingCopy.slotTitle(slot).text
        if let photo {
            let size = photo.displayPixelSize
            return "\(title), \(size.width) by \(size.height)"
        }
        if needsReselect {
            return "\(title). \(PairingCopy.slotStaleMessage.text)"
        }
        return "\(title). \(PairingCopy.slotEmptyHint.text)"
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(theme.typography.font(.sectionTitle))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    theme.color(.onPhoto),
                    theme.color(.scrim).opacity(0.65)
                )
                .frame(
                    width: theme.metrics.minTouchTarget,
                    height: theme.metrics.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text(verbatim: PairingCopy.removeTitle(slot).text))
        .accessibilityIdentifier(
            PairingAccessibilityID.removeButton(slot, pair: pairNumber).rawValue
        )
    }

    // MARK: - Stale note

    private var staleNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            Image(systemName: "clock.arrow.circlepath")
                .font(theme.typography.font(.caption))
                .accessibilityHidden(true)

            Text(verbatim: PairingCopy.slotStaleMessage.text)
                .styleToneText(.caption, color: .warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(
            PairingAccessibilityID.slotNote(slot, pair: pairNumber).rawValue
        )
    }

    // MARK: - Pick action

    private var pickButton: some View {
        Button(action: onPick) {
            HStack(spacing: theme.spacing.xs) {
                Image(systemName: photo == nil ? "plus" : "arrow.triangle.2.circlepath")
                    .imageScale(.small)
                    .accessibilityHidden(true)

                Text(verbatim: pickTitle)
                    .font(theme.typography.font(.label))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.color(.textPrimary))
            .frame(maxWidth: .infinity, minHeight: theme.metrics.minTouchTarget)
            .padding(.horizontal, theme.spacing.sm)
            .background(
                theme.color(.surfacePressed),
                in: RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: theme.radii.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(Text(verbatim: pickTitle))
        .accessibilityIdentifier(
            PairingAccessibilityID.pickButton(slot, pair: pairNumber).rawValue
        )
    }

    private var pickTitle: String {
        if photo == nil {
            return PairingCopy.chooseTitle(slot).text
        }
        return PairingCopy.replaceTitle(slot).text
    }
}
