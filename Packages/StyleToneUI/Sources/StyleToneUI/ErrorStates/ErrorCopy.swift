import Foundation

// MARK: - Text

/// A localization key plus the English development fallback.
///
/// The `zh-Hans` catalog is owned by WP-26. Until it lands, `text` resolves
/// through `L10n` and falls back to the development string, so the error
/// surfaces stay readable without hardcoding Chinese in Swift sources.
public struct ErrorText: Sendable, Hashable {
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

/// All copy owned by the unified error surface.
///
/// Keys stay under the frozen `error.*` prefix from contracts §8. Several keys
/// intentionally match `AppError.map` and `ExportCopy`, so the older page-level
/// surfaces keep the same wording while they migrate to `ErrorStateCard`.
public enum ErrorCopy {
    // MARK: Titles and messages

    public static func title(_ kind: ErrorKind) -> ErrorText {
        switch kind {
        case .offline:
            return ErrorText("error.offline.title", fallback: "You're offline")
        case .networkUnavailable:
            return ErrorText("error.networkUnavailable.title", fallback: "Can't reach the store")
        case .lowBattery:
            return ErrorText("error.lowBattery.title", fallback: "Low battery")
        case .thermalPressure:
            return ErrorText(
                "error.thermalPressure.title",
                fallback: "iPhone is warm"
            )
        case .interrupted:
            return ErrorText("error.interrupted.title", fallback: "Session interrupted")
        case .cancelled:
            return ErrorText("error.cancelled.title", fallback: "Cancelled")
        case .photoPermissionDenied:
            return ErrorText(
                "error.photoPermission.title",
                fallback: "Photos access is off"
            )
        case .photoPermissionRestricted:
            return ErrorText(
                "error.photoPermissionRestricted.title",
                fallback: "Photos access is restricted"
            )
        case .photoLibraryUnavailable:
            return ErrorText(
                "error.photoLibraryUnavailable.title",
                fallback: "Photos isn't available"
            )
        case .storageLow:
            return ErrorText("error.storageLow.title", fallback: "Storage is almost full")
        case .storageFull:
            return ErrorText("error.storageFull.title", fallback: "Not enough storage")
        case .storageUnavailable:
            return ErrorText(
                "error.storageUnavailable.title",
                fallback: "Storage isn't available"
            )
        case .storageWriteFailed:
            return ErrorText("error.storageWrite.title", fallback: "Couldn't save locally")
        case .purchaseUnavailable:
            return ErrorText(
                "error.purchaseUnavailable.title",
                fallback: "Store isn't available"
            )
        case .purchaseFailed:
            return ErrorText("error.purchase.title", fallback: "Purchase didn't complete")
        case .purchaseVerificationFailed:
            return ErrorText(
                "error.purchaseVerification.title",
                fallback: "Couldn't verify purchase"
            )
        case .restoreFailed:
            return ErrorText("error.restore.title", fallback: "Restore didn't finish")
        case .exportUnavailable:
            return ErrorText(
                "error.export.unavailable.title",
                fallback: "Export isn't available"
            )
        case .exportRenderFailed:
            return ErrorText(
                "error.export.render.title",
                fallback: "Couldn't render the photo"
            )
        case .exportResolutionMismatch:
            return ErrorText(
                "error.export.resolution.title",
                fallback: "Export would be low resolution"
            )
        case .exportEncodeFailed:
            return ErrorText(
                "error.export.encode.title",
                fallback: "Couldn't prepare the file"
            )
        case .exportShareUnavailable:
            return ErrorText(
                "error.export.share.title",
                fallback: "Sharing isn't available"
            )
        case .exportLibrarySaveFailed:
            return ErrorText(
                "error.export.save.title",
                fallback: "Couldn't save to Photos"
            )
        case .exportQuotaExhausted:
            return ErrorText("error.export.quota.title", fallback: "Free exports used")
        case .exportQuotaUnavailable:
            return ErrorText(
                "error.export.quotaUnavailable.title",
                fallback: "Couldn't check exports"
            )
        case .exportInvalidImage:
            return ErrorText(
                "error.export.image.title",
                fallback: "This photo can't be exported"
            )
        case .invalidImage:
            return ErrorText("error.image.title", fallback: "This photo can't be used")
        case .unsupportedFormat:
            return ErrorText("error.image.title", fallback: "This photo can't be used")
        case .imageTooSmall:
            return ErrorText("error.imageTooSmall.title", fallback: "Photo is too small")
        case .analysisFailed:
            return ErrorText(
                "error.analysis.title",
                fallback: "Couldn't analyze the photo"
            )
        case .noFace:
            return ErrorText("error.noFace.title", fallback: "No face found")
        case .noBody:
            return ErrorText("error.noBody.title", fallback: "No body found")
        case .renderFailed:
            return ErrorText(
                "error.render.title",
                fallback: "Couldn't apply the edit"
            )
        case .invalidMask:
            return ErrorText("error.mask.title", fallback: "Couldn't prepare the mask")
        case .invalidState:
            return ErrorText("error.state.title", fallback: "Something's out of step")
        case .persistenceFailed:
            return ErrorText("error.storage.title", fallback: "Couldn't load your data")
        case .schemaUnsupported:
            return ErrorText(
                "error.schema.title",
                fallback: "Style needs recalibration"
            )
        case .unknown:
            return ErrorText("error.unknown.title", fallback: "Something went wrong")
        }
    }

    public static func message(_ kind: ErrorKind) -> ErrorText {
        switch kind {
        case .offline:
            return ErrorText(
                "error.offline.message",
                fallback: "Editing, style matching, and saving to Photos keep working. "
                    + "Purchases and restore need a connection."
            )
        case .networkUnavailable:
            return ErrorText(
                "error.networkUnavailable.message",
                fallback: "The connection timed out. Check your network and try again."
            )
        case .lowBattery:
            return ErrorText(
                "error.lowBattery.message",
                fallback: "Rendering may pause to save power. Your edits are safe."
            )
        case .thermalPressure:
            return ErrorText(
                "error.thermalPressure.message",
                fallback: "Preview quality may drop until the phone cools down. "
                    + "Editing stays available."
            )
        case .interrupted:
            return ErrorText(
                "error.interrupted.message",
                fallback: "Your edits were kept. Resume when you're ready."
            )
        case .cancelled:
            return ErrorText(
                "error.cancelled.message",
                fallback: "Nothing was changed."
            )
        case .photoPermissionDenied:
            return ErrorText(
                "error.photoPermission.message",
                fallback: "Allow add-only access in Settings, or share the photo instead."
            )
        case .photoPermissionRestricted:
            return ErrorText(
                "error.photoPermissionRestricted.message",
                fallback: "This device can't add photos. You can still share the file."
            )
        case .photoLibraryUnavailable:
            return ErrorText(
                "error.photoLibraryUnavailable.message",
                fallback: "Saving to Photos isn't available right now. Share the photo instead."
            )
        case .storageLow:
            return ErrorText(
                "error.storageLow.message",
                fallback: "Free up space before exporting a large photo."
            )
        case .storageFull:
            return ErrorText(
                "error.storageFull.message",
                fallback: "Free up space, then try again. Your original is untouched."
            )
        case .storageUnavailable:
            return ErrorText(
                "error.storageUnavailable.message",
                fallback: "The app can't read or write local data right now. Try again."
            )
        case .storageWriteFailed:
            return ErrorText(
                "error.storageWrite.message",
                fallback: "The data couldn't be written. Try again."
            )
        case .purchaseUnavailable:
            return ErrorText(
                "error.purchaseUnavailable.message",
                fallback: "The App Store couldn't load right now. You can keep editing for free."
            )
        case .purchaseFailed:
            return ErrorText(
                "error.purchase.message",
                fallback: "No charge was made. Try again or restore a purchase."
            )
        case .purchaseVerificationFailed:
            return ErrorText(
                "error.purchaseVerification.message",
                fallback: "The App Store receipt couldn't be verified. Try restoring your purchase."
            )
        case .restoreFailed:
            return ErrorText(
                "error.restore.message",
                fallback: "No purchase was changed. Check your connection and try again."
            )
        case .exportUnavailable:
            return ErrorText(
                "error.export.unavailable.message",
                fallback: "The export engine isn't ready in this build. "
                    + "Restart the app and try again."
            )
        case .exportRenderFailed:
            return ErrorText(
                "error.export.render.message",
                fallback: "The full-resolution render failed. Your original is untouched."
            )
        case .exportResolutionMismatch:
            return ErrorText(
                "error.export.resolution.message",
                fallback: "This photo can't be exported at full size. "
                    + "Try a different photo or format."
            )
        case .exportEncodeFailed:
            return ErrorText(
                "error.export.encode.message",
                fallback: "The photo couldn't be encoded. Try again or choose JPEG."
            )
        case .exportShareUnavailable:
            return ErrorText(
                "error.export.share.message",
                fallback: "The system share sheet couldn't open. Save to Photos instead."
            )
        case .exportLibrarySaveFailed:
            return ErrorText(
                "error.export.save.message",
                fallback: "The photo was prepared but Photos didn't accept it. "
                    + "Try again or share instead."
            )
        case .exportQuotaExhausted:
            return ErrorText(
                "error.export.quota.message",
                fallback: "Your three free exports are used. Subscribe to keep exporting, "
                    + "or keep editing."
            )
        case .exportQuotaUnavailable:
            return ErrorText(
                "error.export.quotaUnavailable.message",
                fallback: "The export count couldn't be read. Try again."
            )
        case .exportInvalidImage:
            return ErrorText(
                "error.export.image.message",
                fallback: "The image data is invalid or unsupported. Choose another photo."
            )
        case .invalidImage:
            return ErrorText(
                "error.image.message",
                fallback: "The image is damaged or unsupported. Choose another photo."
            )
        case .unsupportedFormat:
            return ErrorText(
                "error.image.message",
                fallback: "The image is damaged or unsupported. Choose another photo."
            )
        case .imageTooSmall:
            return ErrorText(
                "error.imageTooSmall.message",
                fallback: "Choose a photo with a longer edge so details stay sharp."
            )
        case .analysisFailed:
            return ErrorText(
                "error.analysis.message",
                fallback: "The portrait analysis didn't finish. Try again."
            )
        case .noFace:
            return ErrorText(
                "error.noFace.message",
                fallback: "Use the natural style, or choose a photo where the face is clear."
            )
        case .noBody:
            return ErrorText(
                "error.noBody.message",
                fallback: "Body tools need a full-length photo. Use the natural style "
                    + "or choose another photo."
            )
        case .renderFailed:
            return ErrorText(
                "error.render.message",
                fallback: "The render failed. Your last good preview is still here. "
                    + "Try a lower strength."
            )
        case .invalidMask:
            return ErrorText(
                "error.mask.message",
                fallback: "The subject mask was invalid. Try again or choose another photo."
            )
        case .invalidState:
            return ErrorText(
                "error.state.message",
                fallback: "The app couldn't continue this action. Try again."
            )
        case .persistenceFailed:
            return ErrorText(
                "error.storage.message",
                fallback: "Local data couldn't be read or saved. Try again."
            )
        case .schemaUnsupported:
            return ErrorText(
                "error.schema.message",
                fallback: "This style was made by a newer version. Recalibrate to continue."
            )
        case .unknown:
            return ErrorText(
                "error.unknown.message",
                fallback: "The action didn't finish. Try again. If it keeps happening, "
                    + "share the support code."
            )
        }
    }

    // MARK: Actions

    public static func actionTitle(_ action: RecoveryAction) -> ErrorText {
        switch action {
        case .retry:
            return ErrorText("error.action.retry", fallback: "Try again")
        case .resume:
            return ErrorText("error.action.resume", fallback: "Resume")
        case .continueOffline:
            return ErrorText("error.action.continueOffline", fallback: "Continue editing")
        case .continueAnyway:
            return ErrorText("error.action.continueAnyway", fallback: "Continue")
        case .openSettings:
            return ErrorText("error.action.openSettings", fallback: "Open Settings")
        case .freeUpSpace:
            return ErrorText("error.action.freeUpSpace", fallback: "Free up space")
        case .restorePurchase:
            return ErrorText("error.action.restorePurchase", fallback: "Restore purchase")
        case .shareInstead:
            return ErrorText("error.action.shareInstead", fallback: "Share instead")
        case .saveInstead:
            return ErrorText("error.action.saveInstead", fallback: "Save to Photos instead")
        case .upgrade:
            return ErrorText("error.action.upgrade", fallback: "See plans")
        case .chooseAnotherPhoto:
            return ErrorText(
                "error.action.chooseAnotherPhoto",
                fallback: "Choose another photo"
            )
        case .useNaturalStyle:
            return ErrorText("error.action.useNaturalStyle", fallback: "Use natural style")
        case .reduceStrength:
            return ErrorText("error.action.reduceStrength", fallback: "Lower strength")
        case .recalibrate:
            return ErrorText("error.action.recalibrate", fallback: "Recalibrate")
        case .dismiss:
            return ErrorText("error.action.dismiss", fallback: "Dismiss")
        }
    }

    // MARK: Diagnostics

    /// `Support code: %@`
    public static let diagnosticFormat = ErrorText(
        "error.diagnosticLabel",
        fallback: "Support code: %@"
    )

    public static func diagnosticText(_ code: String) -> String {
        String(format: diagnosticFormat.text, code as NSString)
    }

    // MARK: Test surface

    /// Every title, message, action and diagnostic string owned by this file.
    ///
    /// Used by the edge-case tests to keep the catalog complete without
    /// duplicating the key list.
    public static var allTexts: [ErrorText] {
        var texts: [ErrorText] = []
        for kind in ErrorKind.allCases {
            texts.append(title(kind))
            texts.append(message(kind))
        }
        for action in RecoveryAction.allCases {
            texts.append(actionTitle(action))
        }
        texts.append(diagnosticFormat)
        return texts
    }
}
