import Foundation

/// Accessibility identifiers owned by the skin tools (WP-16).
///
/// The convention is the frozen `screen.element` one from
/// `docs/10-task-decomposition/contracts.md` §8. The smoothing slider reuses
/// the already-frozen `editor.smoothingSlider` identifier; everything else is
/// `editor.*` so WP-17 can address the skin area without depending on copy.
public enum SkinToolsAccessibilityID {
    // MARK: Container

    /// The whole skin-tools panel. Not rendered when the host asks the panel
    /// to hide itself for a photo without a face.
    public static let root = AccessibilityID(.editor, "skinTools")
    public static let header = AccessibilityID(.editor, "skinTools.header")
    public static let originalBadge = AccessibilityID(.editor, "skinTools.originalBadge")
    public static let resetButton = AccessibilityID(.editor, "skinResetButton")
    public static let unavailable = AccessibilityID(.editor, "skinToolsUnavailable")
    public static let maskWarning = AccessibilityID(.editor, "skinToolsMaskWarning")

    // MARK: Sliders

    /// Frozen by WP-03; do not rename.
    public static let smoothingSlider = AccessibilityID.editorSmoothingSlider
    public static let evennessSlider = AccessibilityID(.editor, "evennessSlider")

    // MARK: Blemish entry / canvas

    public static let blemishButton = AccessibilityID(.editor, "blemishButton")
    public static let blemishDoneButton = AccessibilityID(.editor, "blemishDoneButton")
    public static let blemishCanvas = AccessibilityID(.editor, "blemishCanvas")
    public static let blemishCount = AccessibilityID(.editor, "blemishCount")
    public static let blemishEmpty = AccessibilityID(.editor, "blemishEmpty")
    public static let blemishRadiusSlider = AccessibilityID(.editor, "blemishRadiusSlider")
    public static let blemishUndoButton = AccessibilityID(.editor, "blemishUndoButton")
    public static let blemishClearButton = AccessibilityID(.editor, "blemishClearButton")

    // MARK: Zoom

    public static let zoomInButton = AccessibilityID(.editor, "blemishZoomInButton")
    public static let zoomOutButton = AccessibilityID(.editor, "blemishZoomOutButton")
    public static let zoomResetButton = AccessibilityID(.editor, "blemishZoomResetButton")
    public static let zoomValue = AccessibilityID(.editor, "blemishZoomValue")

    // MARK: Progress / error / notice

    public static let progress = AccessibilityID(.editor, "skinToolsProgress")
    public static let cancelButton = AccessibilityID(.editor, "skinToolsCancelButton")
    public static let errorBanner = AccessibilityID(.editor, "skinToolsError")
    public static let errorCode = AccessibilityID(.editor, "skinToolsErrorCode")
    public static let retryButton = AccessibilityID(.editor, "skinToolsRetryButton")
    public static let dismissErrorButton = AccessibilityID(.editor, "skinToolsErrorDismissButton")
    public static let notice = AccessibilityID(.editor, "skinToolsNotice")
    public static let dismissNoticeButton = AccessibilityID(.editor, "skinToolsNoticeDismissButton")

    /// Every identifier introduced by WP-16, for convention tests.
    public static let all: [AccessibilityID] = [
        root,
        header,
        originalBadge,
        resetButton,
        unavailable,
        maskWarning,
        smoothingSlider,
        evennessSlider,
        blemishButton,
        blemishDoneButton,
        blemishCanvas,
        blemishCount,
        blemishEmpty,
        blemishRadiusSlider,
        blemishUndoButton,
        blemishClearButton,
        zoomInButton,
        zoomOutButton,
        zoomResetButton,
        zoomValue,
        progress,
        cancelButton,
        errorBanner,
        errorCode,
        retryButton,
        dismissErrorButton,
        notice,
        dismissNoticeButton,
    ]
}
