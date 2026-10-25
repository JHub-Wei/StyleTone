import Foundation
import StyleToneCore

// MARK: - Text

/// A localization key plus the English development fallback.
///
/// The `zh-Hans` string catalog lands with WP-26; until then `text` resolves
/// through `L10n` and falls back to the development string. Feature code never
/// hardcodes Chinese and never constructs user-facing copy inline.
public struct ExportText: Sendable, Hashable {
    public let key: LocalizationKey
    public let fallback: String

    public init(_ key: String, fallback: String) {
        self.key = LocalizationKey(key)
        self.fallback = fallback
    }

    public var text: String {
        L10n.resolve(key, fallback: fallback)
    }
}

// MARK: - Catalog

/// All copy owned by the export flow.
///
/// The frozen prefix list (contracts §8) has no `export` prefix, so panel copy
/// stays under `editor.export.*` and error copy under `error.export.*`, matching
/// the keys already reserved by WP-03.
public enum ExportCopy {
    // MARK: Screen

    public static let title = ExportText("editor.export.title", fallback: "Export")
    public static let subtitle = ExportText(
        "editor.export.subtitle",
        fallback: "Full resolution, ready for Photos or sharing."
    )
    public static let closeButton = ExportText("common.closeButton", fallback: "Close")
    public static let previewAccessibilityLabel = ExportText(
        "editor.export.preview.accessibilityLabel",
        fallback: "Exported photo preview"
    )
    public static let previewEmptyTitle = ExportText(
        "editor.export.preview.emptyTitle",
        fallback: "Nothing to export yet"
    )
    public static let locationRemoved = ExportText(
        "editor.export.locationRemoved",
        fallback: "Location metadata removed"
    )
    public static let libraryAddOnlyNote = ExportText(
        "editor.export.library.note",
        fallback: "StyleTone only adds photos to your library. It never reads or uploads them."
    )
    public static let privacyNote = ExportText(
        "editor.export.privacy.note",
        fallback: "Rendering and encoding happen on this iPhone. Nothing is uploaded."
    )

    // MARK: Metadata formats

    /// `%d × %d`
    public static let pixelSizeFormat = ExportText(
        "editor.export.format.pixelSize",
        fallback: "%d × %d"
    )
    /// `%.1f MP`
    public static let megapixelsFormat = ExportText(
        "editor.export.format.megapixels",
        fallback: "%.1f MP"
    )
    /// `%.1f MB`
    public static let fileSizeFormat = ExportText(
        "editor.export.format.fileSize",
        fallback: "%.1f MB"
    )
    /// `Support code: %@`
    public static let diagnosticFormat = ExportText(
        "editor.export.diagnostic",
        fallback: "Support code: %@"
    )

    // MARK: Format / quality

    public static let formatSectionTitle = ExportText(
        "editor.export.format.sectionTitle",
        fallback: "Format"
    )
    public static let formatLabel = ExportText(
        "editor.export.format.label",
        fallback: "File format"
    )
    public static let formatHEIC = ExportText("editor.export.format.heic", fallback: "HEIC")
    public static let formatJPEG = ExportText("editor.export.format.jpeg", fallback: "JPEG")
    public static let formatNote = ExportText(
        "editor.export.format.note",
        fallback: "HEIC keeps more detail at a smaller size. JPEG opens everywhere."
    )
    public static let qualityLabel = ExportText(
        "editor.export.quality.label",
        fallback: "Quality"
    )
    public static let qualityStandard = ExportText(
        "editor.export.quality.standard",
        fallback: "Standard"
    )
    public static let qualityHigh = ExportText("editor.export.quality.high", fallback: "High")
    public static let qualityMaximum = ExportText(
        "editor.export.quality.maximum",
        fallback: "Maximum"
    )
    public static let largeImageNotice = ExportText(
        "editor.export.largeNotice",
        fallback: "This is a very large photo. Export can take up to 20 seconds."
    )

    // MARK: Quota

    /// `%d free exports left`
    public static let quotaFreeFormat = ExportText(
        "editor.export.quota.free",
        fallback: "%d free exports left"
    )
    public static let quotaFreeOne = ExportText(
        "editor.export.quota.freeOne",
        fallback: "1 free export left"
    )
    public static let quotaUnlimited = ExportText(
        "editor.export.quota.unlimited",
        fallback: "Unlimited exports"
    )
    public static let quotaExhausted = ExportText(
        "editor.export.quota.exhausted",
        fallback: "Free exports used"
    )
    public static let quotaExhaustedTitle = ExportText(
        "editor.export.quota.exhaustedTitle",
        fallback: "You've used your free exports"
    )
    public static let quotaExhaustedMessage = ExportText(
        "editor.export.quota.exhaustedMessage",
        fallback: "Subscribe for unlimited exports. You can keep editing without a subscription."
    )
    public static let upgradeButton = ExportText(
        "editor.export.quota.upgradeButton",
        fallback: "See plans"
    )
    public static let quotaLoadFailedTitle = ExportText(
        "editor.export.quotaLoad.title",
        fallback: "Couldn't check your exports"
    )
    public static let quotaLoadFailedMessage = ExportText(
        "editor.export.quotaLoad.message",
        fallback: "The free-export count couldn't be read. Try again before exporting."
    )
    public static let quotaRetryButton = ExportText(
        "editor.export.quotaLoad.retryButton",
        fallback: "Check again"
    )

    // MARK: Permission

    public static let permissionDeniedTitle = ExportText(
        "editor.export.permission.deniedTitle",
        fallback: "Photos access is off"
    )
    public static let permissionDeniedMessage = ExportText(
        "editor.export.permission.deniedMessage",
        fallback: "Allow StyleTone to add photos in Settings, or share the photo instead."
    )
    public static let permissionRestrictedTitle = ExportText(
        "editor.export.permission.restrictedTitle",
        fallback: "Adding photos is restricted"
    )
    public static let permissionRestrictedMessage = ExportText(
        "editor.export.permission.restrictedMessage",
        fallback: "This device doesn't allow apps to add to the photo library. Share the photo instead."
    )
    public static let permissionUnavailableNote = ExportText(
        "editor.export.permission.unavailable",
        fallback: "Saving to Photos isn't available in this build. Share the photo instead."
    )
    public static let permissionSettingsButton = ExportText(
        "editor.export.permission.settingsButton",
        fallback: "Open Settings"
    )
    public static let permissionShareButton = ExportText(
        "editor.export.permission.shareButton",
        fallback: "Share instead"
    )
    public static let permissionRetryButton = ExportText(
        "editor.export.permission.retryButton",
        fallback: "Check again"
    )

    // MARK: Actions

    public static let saveButton = ExportText(
        "editor.export.saveButton",
        fallback: "Save to Photos"
    )
    public static let shareButton = ExportText("editor.export.shareButton", fallback: "Share…")
    public static let cancelButton = ExportText("editor.export.cancelButton", fallback: "Cancel")
    public static let retryButton = ExportText("editor.export.retryButton", fallback: "Try again")
    public static let dismissButton = ExportText("editor.export.dismissButton", fallback: "Dismiss")
    public static let doneButton = ExportText("editor.export.doneButton", fallback: "Done")

    // MARK: Progress

    public static let progressIdle = ExportText(
        "editor.export.progress.idle",
        fallback: "Ready to export"
    )
    public static let progressPreparing = ExportText(
        "editor.export.progress.preparing",
        fallback: "Preparing export…"
    )
    public static let progressRequestingAccess = ExportText(
        "editor.export.progress.requestingAccess",
        fallback: "Checking Photos access…"
    )
    public static let progressRendering = ExportText(
        "editor.export.progress.rendering",
        fallback: "Rendering at full resolution…"
    )
    public static let progressEncoding = ExportText(
        "editor.export.progress.encoding",
        fallback: "Encoding the photo…"
    )
    public static let progressSavingToLibrary = ExportText(
        "editor.export.progress.savingToLibrary",
        fallback: "Saving to Photos…"
    )
    public static let progressAwaitingShare = ExportText(
        "editor.export.progress.awaitingShare",
        fallback: "Waiting for the share sheet…"
    )
    public static let progressFinished = ExportText(
        "editor.export.progress.finished",
        fallback: "Export complete"
    )
    public static let progressFailed = ExportText(
        "editor.export.progress.failed",
        fallback: "Export failed"
    )
    public static let progressCancelled = ExportText(
        "editor.export.progress.cancelled",
        fallback: "Export cancelled"
    )

    // MARK: Outcome

    public static let outcomeSavedTitle = ExportText(
        "editor.export.outcome.savedTitle",
        fallback: "Saved to Photos"
    )
    public static let outcomeSavedMessage = ExportText(
        "editor.export.outcome.savedMessage",
        fallback: "Your full-resolution photo is in Photos."
    )
    public static let outcomeSharedTitle = ExportText(
        "editor.export.outcome.sharedTitle",
        fallback: "Photo shared"
    )
    public static let outcomeSharedMessage = ExportText(
        "editor.export.outcome.sharedMessage",
        fallback: "The full-resolution file was handed to the share sheet."
    )
    public static let outcomeCountPending = ExportText(
        "editor.export.outcome.countPending",
        fallback: "The photo was delivered, but the free-export count couldn't be updated."
    )
    public static let shareCancelled = ExportText(
        "editor.export.outcome.shareCancelled",
        fallback: "Sharing didn't complete. Nothing was counted."
    )
    public static let cancelledMessage = ExportText(
        "editor.export.outcome.cancelled",
        fallback: "Export cancelled. Nothing was saved or counted."
    )

    // MARK: Recovery actions

    public static let recoveryRetry = ExportText("editor.export.recovery.retry", fallback: "Try again")
    public static let recoveryShareInstead = ExportText(
        "editor.export.recovery.shareInstead",
        fallback: "Share instead"
    )
    public static let recoverySaveInstead = ExportText(
        "editor.export.recovery.saveInstead",
        fallback: "Save to Photos instead"
    )
    public static let recoveryOpenSettings = ExportText(
        "editor.export.recovery.openSettings",
        fallback: "Open Settings"
    )
    public static let recoveryUpgrade = ExportText(
        "editor.export.recovery.upgrade",
        fallback: "See plans"
    )
    public static let recoveryDismiss = ExportText(
        "editor.export.recovery.dismiss",
        fallback: "Dismiss"
    )

    // MARK: Failure copy

    public static let failureUnavailableTitle = ExportText(
        "error.export.unavailable.title",
        fallback: "Export isn't available"
    )
    public static let failureUnavailableMessage = ExportText(
        "error.export.unavailable.message",
        fallback: "The export engine isn't ready in this build. Restart the app and try again."
    )
    public static let failureRenderTitle = ExportText(
        "error.export.render.title",
        fallback: "Couldn't render the photo"
    )
    public static let failureRenderMessage = ExportText(
        "error.export.render.message",
        fallback: "The full-resolution render failed. Your original is untouched. Try again."
    )
    public static let failureResolutionTitle = ExportText(
        "error.export.resolution.title",
        fallback: "Export would be low resolution"
    )
    public static let failureResolutionMessage = ExportText(
        "error.export.resolution.message",
        fallback: "The render came back smaller than the original. Try again to get a full-resolution copy."
    )
    public static let failureEncodeTitle = ExportText(
        "error.export.encode.title",
        fallback: "Couldn't encode the photo"
    )
    public static let failureEncodeMessage = ExportText(
        "error.export.encode.message",
        fallback: "The file could not be written. Try again, or choose the other format."
    )
    public static let failurePermissionTitle = ExportText(
        "error.export.permission.title",
        fallback: "Photos access is off"
    )
    public static let failurePermissionMessage = ExportText(
        "error.export.permission.message",
        fallback: "StyleTone can only add photos; it never reads your library. Allow access in Settings, or share the photo instead."
    )
    public static let failureRestrictedTitle = ExportText(
        "error.export.restricted.title",
        fallback: "Adding photos is restricted"
    )
    public static let failureRestrictedMessage = ExportText(
        "error.export.restricted.message",
        fallback: "This device restricts photo-library changes. Share the photo instead."
    )
    public static let failureLibraryUnavailableTitle = ExportText(
        "error.export.libraryUnavailable.title",
        fallback: "Saving to Photos isn't available"
    )
    public static let failureLibraryUnavailableMessage = ExportText(
        "error.export.libraryUnavailable.message",
        fallback: "This build cannot add photos to the library. Share the full-resolution file instead."
    )
    public static let failureSaveTitle = ExportText(
        "error.export.save.title",
        fallback: "Couldn't save to Photos"
    )
    public static let failureSaveMessage = ExportText(
        "error.export.save.message",
        fallback: "The photo was not added. Try again or share the file instead."
    )
    public static let failureShareTitle = ExportText(
        "error.export.share.title",
        fallback: "Sharing isn't available"
    )
    public static let failureShareMessage = ExportText(
        "error.export.share.message",
        fallback: "The share sheet cannot open in this build. Save to Photos instead."
    )
    public static let failureQuotaTitle = ExportText(
        "error.export.quota.title",
        fallback: "Free exports used"
    )
    public static let failureQuotaMessage = ExportText(
        "error.export.quota.message",
        fallback: "Subscribe for unlimited exports, or keep editing without saving a new copy."
    )
    public static let failureQuotaUnavailableTitle = ExportText(
        "error.export.quotaUnavailable.title",
        fallback: "Couldn't check your exports"
    )
    public static let failureQuotaUnavailableMessage = ExportText(
        "error.export.quotaUnavailable.message",
        fallback: "The free-export count couldn't be read. Try again in a moment."
    )
    public static let failureImageTitle = ExportText(
        "error.export.image.title",
        fallback: "Couldn't export this photo"
    )
    public static let failureImageMessage = ExportText(
        "error.export.image.message",
        fallback: "The photo is missing or unreadable. Go back and choose it again."
    )
    public static let failureUnknownTitle = ExportText(
        "error.export.unknown.title",
        fallback: "Export failed"
    )
    public static let failureUnknownMessage = ExportText(
        "error.export.unknown.message",
        fallback: "Something went wrong. Try again."
    )

    // MARK: - Helpers

    public static func formatTitle(_ format: ExportFormat) -> ExportText {
        format == .heic ? formatHEIC : formatJPEG
    }

    public static func qualityTitle(_ quality: ExportQuality) -> ExportText {
        switch quality.id {
        case "standard": return qualityStandard
        case "maximum": return qualityMaximum
        default: return qualityHigh
        }
    }

    public static func progressText(_ stage: ExportStage) -> ExportText {
        switch stage {
        case .idle: return progressIdle
        case .preparing: return progressPreparing
        case .requestingAccess: return progressRequestingAccess
        case .rendering: return progressRendering
        case .encoding: return progressEncoding
        case .savingToLibrary: return progressSavingToLibrary
        case .awaitingShare: return progressAwaitingShare
        case .finished: return progressFinished
        case .failed: return progressFailed
        case .cancelled: return progressCancelled
        }
    }

    public static func recoveryTitle(_ recovery: ExportFailure.Recovery) -> ExportText {
        switch recovery {
        case .retry: return recoveryRetry
        case .shareInstead: return recoveryShareInstead
        case .saveInstead: return recoverySaveInstead
        case .openSettings: return recoveryOpenSettings
        case .upgrade: return recoveryUpgrade
        case .dismiss: return recoveryDismiss
        }
    }

    public static func failureTitle(_ kind: ExportFailure.Kind) -> ExportText {
        switch kind {
        case .unavailable: return failureUnavailableTitle
        case .renderFailed: return failureRenderTitle
        case .resolutionMismatch: return failureResolutionTitle
        case .encodeFailed: return failureEncodeTitle
        case .permissionDenied: return failurePermissionTitle
        case .permissionRestricted: return failureRestrictedTitle
        case .photoLibraryUnavailable: return failureLibraryUnavailableTitle
        case .librarySaveFailed: return failureSaveTitle
        case .shareUnavailable: return failureShareTitle
        case .quotaExhausted: return failureQuotaTitle
        case .quotaUnavailable: return failureQuotaUnavailableTitle
        case .invalidImage: return failureImageTitle
        case .unknown: return failureUnknownTitle
        }
    }

    public static func failureMessage(_ kind: ExportFailure.Kind) -> ExportText {
        switch kind {
        case .unavailable: return failureUnavailableMessage
        case .renderFailed: return failureRenderMessage
        case .resolutionMismatch: return failureResolutionMessage
        case .encodeFailed: return failureEncodeMessage
        case .permissionDenied: return failurePermissionMessage
        case .permissionRestricted: return failureRestrictedMessage
        case .photoLibraryUnavailable: return failureLibraryUnavailableMessage
        case .librarySaveFailed: return failureSaveMessage
        case .shareUnavailable: return failureShareMessage
        case .quotaExhausted: return failureQuotaMessage
        case .quotaUnavailable: return failureQuotaUnavailableMessage
        case .invalidImage: return failureImageMessage
        case .unknown: return failureUnknownMessage
        }
    }

    /// `3 free exports left` / `1 free export left`.
    public static func quotaText(remaining: Int) -> String {
        let count = max(0, remaining)
        if count == 1 {
            return quotaFreeOne.text
        }
        return String(format: quotaFreeFormat.text, count)
    }

    /// `4032 × 3024`.
    public static func pixelSizeText(_ size: PixelSize) -> String {
        String(format: pixelSizeFormat.text, size.width, size.height)
    }

    /// `12.2 MP`.
    public static func megapixelsText(_ megapixels: Double) -> String {
        String(format: megapixelsFormat.text, megapixels)
    }

    /// `4.2 MB` using decimal megabytes, matching how Photos reports size.
    public static func fileSizeText(bytes: Int) -> String {
        String(format: fileSizeFormat.text, Double(max(0, bytes)) / 1_000_000)
    }

    /// `Support code: ST-EXPORT-PERMISSION`.
    public static func diagnosticText(_ code: String) -> String {
        String(format: diagnosticFormat.text, code as NSString)
    }

    /// Every text owned by this flow, for catalog/key tests.
    public static let all: [ExportText] = [
        title, subtitle, closeButton, previewAccessibilityLabel, previewEmptyTitle,
        locationRemoved, libraryAddOnlyNote, privacyNote,
        pixelSizeFormat, megapixelsFormat, fileSizeFormat, diagnosticFormat,
        formatSectionTitle, formatLabel, formatHEIC, formatJPEG, formatNote,
        qualityLabel, qualityStandard, qualityHigh, qualityMaximum, largeImageNotice,
        quotaFreeFormat, quotaFreeOne, quotaUnlimited, quotaExhausted,
        quotaExhaustedTitle, quotaExhaustedMessage,
        upgradeButton, quotaLoadFailedTitle, quotaLoadFailedMessage, quotaRetryButton,
        permissionDeniedTitle, permissionDeniedMessage, permissionRestrictedTitle,
        permissionRestrictedMessage, permissionUnavailableNote, permissionSettingsButton,
        permissionShareButton, permissionRetryButton,
        saveButton, shareButton, cancelButton, retryButton, dismissButton, doneButton,
        progressIdle, progressPreparing, progressRequestingAccess, progressRendering,
        progressEncoding, progressSavingToLibrary, progressAwaitingShare,
        progressFinished, progressFailed, progressCancelled,
        outcomeSavedTitle, outcomeSavedMessage, outcomeSharedTitle, outcomeSharedMessage,
        outcomeCountPending, shareCancelled, cancelledMessage,
        recoveryRetry, recoveryShareInstead, recoverySaveInstead, recoveryOpenSettings,
        recoveryUpgrade, recoveryDismiss,
        failureUnavailableTitle, failureUnavailableMessage,
        failureRenderTitle, failureRenderMessage,
        failureResolutionTitle, failureResolutionMessage,
        failureEncodeTitle, failureEncodeMessage,
        failurePermissionTitle, failurePermissionMessage,
        failureRestrictedTitle, failureRestrictedMessage,
        failureLibraryUnavailableTitle, failureLibraryUnavailableMessage,
        failureSaveTitle, failureSaveMessage,
        failureShareTitle, failureShareMessage,
        failureQuotaTitle, failureQuotaMessage,
        failureQuotaUnavailableTitle, failureQuotaUnavailableMessage,
        failureImageTitle, failureImageMessage,
        failureUnknownTitle, failureUnknownMessage,
    ]
}
