import Foundation

/// Accessibility identifiers owned by the export sheet.
///
/// The convention is the frozen `screen.element` one from
/// `docs/10-task-decomposition/contracts.md` §8. `export.exportButton` and
/// `export.closeButton` are reused from `AccessibilityID` instead of declared
/// again; everything else is specific to this screen.
public enum ExportAccessibilityID {
    // MARK: Screen-level

    public static let screen = AccessibilityID(.export, "root")
    public static let preview = AccessibilityID(.export, "preview")
    public static let pixelSize = AccessibilityID(.export, "pixelSize")
    public static let locationNote = AccessibilityID(.export, "locationNote")
    public static let largeNotice = AccessibilityID(.export, "largeNotice")
    public static let formatPicker = AccessibilityID(.export, "formatPicker")
    public static let qualityPicker = AccessibilityID(.export, "qualityPicker")
    public static let quota = AccessibilityID(.export, "quota")
    public static let quotaNotice = AccessibilityID(.export, "quotaNotice")
    public static let quotaUpgradeButton = AccessibilityID(.export, "quotaNotice.upgradeButton")
    public static let quotaRetryButton = AccessibilityID(.export, "quotaNotice.retryButton")

    // MARK: Permission

    public static let permissionNotice = AccessibilityID(.export, "permissionNotice")
    public static let permissionSettingsButton = AccessibilityID(
        .export,
        "permissionNotice.settingsButton"
    )
    public static let permissionShareButton = AccessibilityID(
        .export,
        "permissionNotice.shareButton"
    )
    public static let permissionRetryButton = AccessibilityID(
        .export,
        "permissionNotice.retryButton"
    )

    // MARK: Progress

    public static let progress = AccessibilityID(.export, "progress")
    public static let progressValue = AccessibilityID(.export, "progress.value")
    public static let cancelButton = AccessibilityID(.export, "cancelButton")

    // MARK: Failure

    public static let failure = AccessibilityID(.export, "failure")
    public static let failureRetryButton = AccessibilityID(.export, "failure.retryButton")
    public static let failureShareButton = AccessibilityID(.export, "failure.shareButton")
    public static let failureSaveButton = AccessibilityID(.export, "failure.saveButton")
    public static let failureSettingsButton = AccessibilityID(.export, "failure.settingsButton")
    public static let failureUpgradeButton = AccessibilityID(.export, "failure.upgradeButton")
    public static let failureDismissButton = AccessibilityID(.export, "failure.dismissButton")
    public static let failureDiagnostic = AccessibilityID(.export, "failure.diagnostic")

    // MARK: Result / notices

    public static let result = AccessibilityID(.export, "result")
    public static let resultDetail = AccessibilityID(.export, "result.detail")
    public static let resultDoneButton = AccessibilityID(.export, "result.doneButton")
    public static let resultCountPending = AccessibilityID(.export, "result.countPending")
    public static let infoNotice = AccessibilityID(.export, "infoNotice")
    public static let infoDismissButton = AccessibilityID(.export, "infoNotice.dismissButton")
    public static let cancelledNotice = AccessibilityID(.export, "cancelledNotice")
    public static let cancelledRetryButton = AccessibilityID(
        .export,
        "cancelledNotice.retryButton"
    )

    // MARK: Frozen actions

    public static let saveButton = AccessibilityID.exportExportButton
    public static let shareButton = AccessibilityID(.export, "shareButton")
    public static let closeButton = AccessibilityID.exportCloseButton

    /// Identifier used for one recovery action inside the failure card.
    public static func failureButton(_ recovery: ExportFailure.Recovery) -> AccessibilityID {
        switch recovery {
        case .retry: return failureRetryButton
        case .shareInstead: return failureShareButton
        case .saveInstead: return failureSaveButton
        case .openSettings: return failureSettingsButton
        case .upgrade: return failureUpgradeButton
        case .dismiss: return failureDismissButton
        }
    }

    /// Every identifier this screen exposes, for convention tests.
    public static let all: [AccessibilityID] = [
        screen,
        preview,
        pixelSize,
        locationNote,
        largeNotice,
        formatPicker,
        qualityPicker,
        quota,
        quotaNotice,
        quotaUpgradeButton,
        quotaRetryButton,
        permissionNotice,
        permissionSettingsButton,
        permissionShareButton,
        permissionRetryButton,
        progress,
        progressValue,
        cancelButton,
        failure,
        failureRetryButton,
        failureShareButton,
        failureSaveButton,
        failureSettingsButton,
        failureUpgradeButton,
        failureDismissButton,
        failureDiagnostic,
        result,
        resultDetail,
        resultDoneButton,
        resultCountPending,
        infoNotice,
        infoDismissButton,
        cancelledNotice,
        cancelledRetryButton,
        saveButton,
        shareButton,
        closeButton,
    ]
}
