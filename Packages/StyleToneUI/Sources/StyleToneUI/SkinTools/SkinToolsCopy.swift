import Foundation
import StyleToneCore

/// Skin-tools copy, owned by WP-16.
///
/// Every string resolves through `L10n.resolve` with an English development
/// fallback until WP-26 ships the zh-Hans string catalog. Keys stay under the
/// frozen `editor.` prefix, so the contract's prefix list needs no change.
/// No Chinese literal is hardcoded in Swift sources.
public enum SkinToolsCopy {
    // MARK: Section

    public static let sectionTitle = L10n.editorSectionSkin
    public static let sectionNote = L10n.editorSectionSkinNote
    public static let smoothing = L10n.editorSmoothing
    public static let evenness = LocalizationKey("editor.skin.evenness")
    public static let originalBadge = LocalizationKey("editor.skin.originalBadge")
    public static let resetButton = LocalizationKey("editor.skin.resetButton")
    public static let resetHint = LocalizationKey("editor.skin.resetHint")
    public static let maskMissing = LocalizationKey("editor.skin.maskMissing")

    // MARK: Unavailable

    public static let unavailableTitle = LocalizationKey("editor.skin.unavailable.title")
    public static let unavailableNoFace = LocalizationKey("editor.skin.unavailable.noFace")
    public static let unavailableMismatch = LocalizationKey("editor.skin.unavailable.analysisMismatch")

    // MARK: Blemish

    public static let blemishTitle = LocalizationKey("editor.skin.blemish.title")
    public static let blemishSubtitle = LocalizationKey("editor.skin.blemish.subtitle")
    public static let blemishStart = LocalizationKey("editor.skin.blemish.startButton")
    public static let blemishDone = LocalizationKey("editor.skin.blemish.doneButton")
    public static let blemishRadius = LocalizationKey("editor.skin.blemish.radius")
    public static let blemishRadiusHint = LocalizationKey("editor.skin.blemish.radiusHint")
    public static let blemishUndo = LocalizationKey("editor.skin.blemish.undoButton")
    public static let blemishClear = LocalizationKey("editor.skin.blemish.clearButton")
    public static let blemishCount = LocalizationKey("editor.skin.blemish.count")
    public static let blemishEmpty = LocalizationKey("editor.skin.blemish.empty")
    public static let canvasLabel = LocalizationKey("editor.skin.blemish.canvasLabel")
    public static let canvasValue = LocalizationKey("editor.skin.blemish.canvasValue")
    public static let canvasHint = LocalizationKey("editor.skin.blemish.canvasHint")
    public static let applyAtCenter = LocalizationKey("editor.skin.blemish.applyAtCenter")
    public static let undoAction = LocalizationKey("editor.skin.blemish.undoAction")

    // MARK: Zoom

    public static let zoomIn = LocalizationKey("editor.skin.zoom.inButton")
    public static let zoomOut = LocalizationKey("editor.skin.zoom.outButton")
    public static let zoomReset = LocalizationKey("editor.skin.zoom.resetButton")
    public static let zoomValue = LocalizationKey("editor.skin.zoom.value")
    public static let zoomAccessibility = LocalizationKey("editor.skin.zoom.accessibility")

    // MARK: Progress / errors

    public static let rendering = LocalizationKey("editor.skin.rendering")
    public static let cancel = LocalizationKey("editor.skin.cancelButton")
    public static let retry = LocalizationKey("editor.skin.retryButton")
    public static let errorTitle = LocalizationKey("editor.skin.error.title")
    public static let errorRetouch = LocalizationKey("editor.skin.error.retouch")
    public static let errorBlemish = LocalizationKey("editor.skin.error.blemish")
    public static let errorUndo = LocalizationKey("editor.skin.error.undo")
    public static let errorCode = LocalizationKey("editor.skin.error.code")
    public static let errorDismiss = LocalizationKey("editor.skin.error.dismissButton")

    // MARK: Notices

    public static let noticeCancelled = LocalizationKey("editor.skin.notice.cancelled")
    public static let noticeLimit = LocalizationKey("editor.skin.notice.limit")
    public static let noticeDismiss = LocalizationKey("editor.skin.notice.dismissButton")

    // MARK: - Mapping

    /// Message for a failed render or repair.
    public static func errorKey(for kind: SkinToolsFailure.Kind) -> LocalizationKey {
        switch kind {
        case .retouch: return errorRetouch
        case .blemish: return errorBlemish
        case .undo: return errorUndo
        }
    }

    /// Message for a non-error notice.
    public static func noticeKey(for notice: SkinToolsNotice) -> LocalizationKey {
        switch notice {
        case .renderingCancelled: return noticeCancelled
        case .blemishLimitReached: return noticeLimit
        }
    }

    /// Explanation shown when the controls are unavailable.
    public static func unavailableKey(for reason: SkinToolsUnavailableReason) -> LocalizationKey {
        switch reason {
        case .noFace: return unavailableNoFace
        case .analysisMismatch: return unavailableMismatch
        }
    }

    // MARK: - Resolution

    /// Resolves a key to its fallback while the string catalog is absent.
    public static func text(_ key: LocalizationKey) -> String {
        let fallback = fallbacks[key] ?? key.rawValue
        return L10n.resolve(key, fallback: fallback)
    }

    /// Resolves and formats a key. Only integer and string positional
    /// arguments are used by skin-tools copy.
    public static func format(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// The fallback for a key; exposed so tests can audit every string.
    public static func fallback(for key: LocalizationKey) -> String? {
        fallbacks[key]
    }

    /// Every skin-tools key, sorted for deterministic tests.
    public static var allKeys: [LocalizationKey] {
        fallbacks.keys.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Fallbacks

    private static let fallbacks: [LocalizationKey: String] = [
        sectionTitle: "Skin",
        sectionNote: "Texture-preserving smoothing and evenness; no whitening.",
        smoothing: "Smoothing",
        evenness: "Evenness",
        originalBadge: "Showing the original",
        resetButton: "Reset",
        resetHint: "Resets smoothing, evenness and every blemish mark.",
        maskMissing: "No skin mask was produced for this photo. Smoothing and evenness may have no effect.",

        unavailableTitle: "Skin tools unavailable",
        unavailableNoFace: "No face was detected. Try another portrait, or use light and tone instead.",
        unavailableMismatch: "This photo's analysis does not match its size. Reopen the photo and try again.",

        blemishTitle: "Blemish removal",
        blemishSubtitle: "Tap a small spot to repair it. Pinch to zoom; avoid eyes and lips.",
        blemishStart: "Remove a blemish",
        blemishDone: "Done",
        blemishRadius: "Brush size",
        blemishRadiusHint: "Size of the repaired area, relative to the photo's short edge.",
        blemishUndo: "Undo mark",
        blemishClear: "Clear marks",
        blemishCount: "%d marks",
        blemishEmpty: "No marks yet. Tap a blemish to repair it.",
        canvasLabel: "Blemish preview",
        canvasValue: "%d marks, %d× zoom",
        canvasHint: "Tap a spot to repair it. Pinch to zoom, drag to pan.",
        applyAtCenter: "Repair a spot at the centre",
        undoAction: "Undo the last mark",

        zoomIn: "Zoom in",
        zoomOut: "Zoom out",
        zoomReset: "Reset zoom",
        zoomValue: "%d×",
        zoomAccessibility: "Zoom %d×",

        rendering: "Applying skin adjustments…",
        cancel: "Cancel",
        retry: "Try again",
        errorTitle: "Skin adjustments failed",
        errorRetouch: "Smoothing could not be applied. Your previous result is unchanged.",
        errorBlemish: "That spot could not be repaired. Your previous result is unchanged.",
        errorUndo: "The mark change could not be applied. Your marks are unchanged.",
        errorCode: "Code %@",
        errorDismiss: "Dismiss",

        noticeCancelled: "Rendering cancelled. Your last result is unchanged.",
        noticeLimit: "Mark limit reached. Undo a mark to add another.",
        noticeDismiss: "Dismiss",
    ]
}
