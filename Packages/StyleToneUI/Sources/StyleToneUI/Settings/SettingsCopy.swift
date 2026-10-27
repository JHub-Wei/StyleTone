import Foundation

/// A localization key plus the English development fallback.
///
/// The `zh-Hans` string catalog arrives with WP-26. Until then `text` resolves
/// through `L10n` and falls back to the development string; the settings
/// feature never embeds user-facing copy in a view.
public struct SettingsText: Sendable, Hashable {
    public let key: LocalizationKey
    public let fallback: String

    public init(_ key: String, fallback: String) {
        self.key = LocalizationKey(key)
        self.fallback = fallback
    }

    /// The string to display.
    public var text: String {
        L10n.resolve(key, fallback: fallback)
    }

    /// Resolves a format string, for example `"%d entries"`.
    public func formatted(_ arguments: CVarArg...) -> String {
        String(format: text, arguments: arguments)
    }

    /// Settings copy lives under the frozen `settings.` prefix, or under
    /// `error.settings.` for recovery strings.
    public var isSettingsKey: Bool {
        key.rawValue.hasPrefix("settings.") || key.rawValue.hasPrefix("error.settings.")
    }
}

// MARK: - Copy catalog

/// All copy owned by the settings screen and its detail pages.
///
/// The fallbacks are deliberately plain English: they are development copy for
/// the catalog, not final marketing copy. Legal wording is reviewed by WP-28.
public enum SettingsCopy {
    // MARK: Screen

    public static let title = SettingsText("settings.title", fallback: "Settings")
    public static let subtitle = SettingsText(
        "settings.subtitle",
        fallback: "Local-first privacy, diagnostics and purchase information."
    )
    public static let sectionPrivacy = SettingsText("settings.section.privacy", fallback: "Privacy")
    public static let sectionDiagnostics = SettingsText(
        "settings.section.diagnostics",
        fallback: "Diagnostics"
    )
    public static let sectionSubscription = SettingsText(
        "settings.section.subscription",
        fallback: "Subscription"
    )
    public static let sectionAbout = SettingsText("settings.section.about", fallback: "About")
    public static let sectionSupport = SettingsText("settings.section.support", fallback: "Support")

    // MARK: Privacy

    public static let privacySummary = SettingsText(
        "settings.privacy.summary",
        fallback: "Photos stay on this iPhone."
    )
    public static let privacyBody = SettingsText(
        "settings.privacy.body",
        fallback: "StyleTone has no account, no cloud sync and no upload. "
            + "Styles, calibration data and edit history are stored locally."
    )
    public static let privacyLink = SettingsText(
        "settings.privacy.link",
        fallback: "How your data is handled"
    )
    public static let privacyPolicy = SettingsText(
        "settings.privacy.policy",
        fallback: "Privacy policy"
    )
    public static let privacyPolicyUnavailable = SettingsText(
        "settings.privacy.policyUnavailable",
        fallback: "The privacy policy will be available in the App Store listing."
    )
    public static let privacyNoAccount = SettingsText(
        "settings.privacy.noAccount",
        fallback: "No account. No sign-in."
    )

    public static let privacyDetailTitle = SettingsText(
        "settings.privacy.detailTitle",
        fallback: "Privacy"
    )
    public static let privacyIntro = SettingsText(
        "settings.privacy.intro",
        fallback: "StyleTone processes portrait photos entirely on this iPhone. Nothing is uploaded to a server."
    )
    public static let privacyLocalTitle = SettingsText(
        "settings.privacy.localTitle",
        fallback: "Stays on this iPhone"
    )
    public static let privacyLocalPhotos = SettingsText(
        "settings.privacy.localPhotos",
        fallback: "Original and edited photos you open"
    )
    public static let privacyLocalStyle = SettingsText(
        "settings.privacy.localStyle",
        fallback: "Style profile, calibration answers and saved pair metadata"
    )
    public static let privacyLocalHistory = SettingsText(
        "settings.privacy.localHistory",
        fallback: "Edit history and export count"
    )
    public static let privacyLocalDiagnostics = SettingsText(
        "settings.privacy.localDiagnostics",
        fallback: "Local diagnostics, only if you turn them on"
    )
    public static let privacyLeavesTitle = SettingsText(
        "settings.privacy.leavesTitle",
        fallback: "Leaves this iPhone"
    )
    public static let privacyLeavesNothing = SettingsText(
        "settings.privacy.leavesNothing",
        fallback: "StyleTone does not collect or upload photos, edits or style data."
    )
    public static let privacyLeavesApple = SettingsText(
        "settings.privacy.leavesApple",
        fallback: "Purchases, receipts and subscription status are handled by Apple."
    )
    public static let privacyCollectTitle = SettingsText(
        "settings.privacy.collectTitle",
        fallback: "Diagnostics"
    )
    public static let privacyCollectBody = SettingsText(
        "settings.privacy.collectBody",
        fallback: "Off by default. When on, StyleTone stores app events, error codes, timestamps, "
            + "app version and OS version on this iPhone. It never records photos, file names, "
            + "photo library identifiers, location, contacts or account information."
    )
    public static let privacyControlsTitle = SettingsText(
        "settings.privacy.controlsTitle",
        fallback: "Your choices"
    )
    public static let privacyControlsBody = SettingsText(
        "settings.privacy.controlsBody",
        fallback: "Turn diagnostics off at any time; turning it off deletes the local diagnostic log. "
            + "Delete all local data at any time; deletion cannot be undone."
    )
    public static let privacyNoAccountNote = SettingsText(
        "settings.privacy.noAccountNote",
        fallback: "No account is needed or created. There is no sign-in and no cloud sync."
    )

    // MARK: Subscription

    public static let subscriptionBody = SettingsText(
        "settings.subscription.body",
        fallback: "Subscriptions are managed by your Apple ID. Deleting local data or this app "
            + "does not cancel a subscription. Manage or cancel it in your App Store account settings."
    )
    public static let subscriptionHint = SettingsText(
        "settings.subscription.hint",
        fallback: "Your purchase remains active after deletion. "
            + "Restore it from the subscription screen on this or another device."
    )

    // MARK: Delete

    public static let deleteDataButton = SettingsText(
        "settings.deleteDataButton",
        fallback: "Delete all local data"
    )
    public static let deleteDataHint = SettingsText(
        "settings.deleteData.hint",
        fallback: "Removes styles, calibration, history, quota, diagnostics and preferences."
    )
    public static let deleteSheetTitle = SettingsText(
        "settings.deleteData.sheetTitle",
        fallback: "Delete all local data?"
    )
    public static let deleteSheetIntro = SettingsText(
        "settings.deleteData.sheetIntro",
        fallback: "This removes the data StyleTone keeps on this iPhone. It cannot be undone."
    )
    public static let deleteRemoveTitle = SettingsText(
        "settings.deleteData.removeTitle",
        fallback: "Deleted"
    )
    public static let deleteRemoveProfiles = SettingsText(
        "settings.deleteData.removeProfiles",
        fallback: "Style profile and calibration data"
    )
    public static let deleteRemovePairs = SettingsText(
        "settings.deleteData.removePairs",
        fallback: "Saved pair metadata and edit history"
    )
    public static let deleteRemoveQuota = SettingsText(
        "settings.deleteData.removeQuota",
        fallback: "Export count and caches"
    )
    public static let deleteRemoveDiagnostics = SettingsText(
        "settings.deleteData.removeDiagnostics",
        fallback: "Local diagnostics and preferences"
    )
    public static let deleteRemoveTemporary = SettingsText(
        "settings.deleteData.removeTemporary",
        fallback: "Temporary files"
    )
    public static let deleteKeepTitle = SettingsText(
        "settings.deleteData.keepTitle",
        fallback: "Kept"
    )
    public static let deleteKeepPhotos = SettingsText(
        "settings.deleteData.keepPhotos",
        fallback: "Photos already saved in your photo library"
    )
    public static let deleteKeepPurchase = SettingsText(
        "settings.deleteData.keepPurchase",
        fallback: "Your Apple ID purchase and subscription"
    )
    public static let deleteKeepSubscription = SettingsText(
        "settings.deleteData.keepSubscription",
        fallback: "Deleting data does not cancel a subscription. Manage it in your App Store account settings."
    )
    public static let deleteCancelButton = SettingsText(
        "settings.deleteData.cancel",
        fallback: "Cancel"
    )
    public static let deleteContinueButton = SettingsText(
        "settings.deleteData.continue",
        fallback: "Continue"
    )
    public static let deleteBackButton = SettingsText(
        "settings.deleteData.back",
        fallback: "Back"
    )
    public static let deleteFinalTitle = SettingsText(
        "settings.deleteData.finalTitle",
        fallback: "Delete everything?"
    )
    public static let deleteFinalMessage = SettingsText(
        "settings.deleteData.finalMessage",
        fallback: "All local StyleTone data will be removed permanently. This cannot be undone."
    )
    public static let deleteFinalConfirm = SettingsText(
        "settings.deleteData.finalConfirm",
        fallback: "Delete everything"
    )
    public static let deleteProgress = SettingsText(
        "settings.deleteData.progress",
        fallback: "Deleting local data..."
    )
    public static let deleteSuccessTitle = SettingsText(
        "settings.deleteData.successTitle",
        fallback: "All local data deleted"
    )
    public static let deleteSuccessBody = SettingsText(
        "settings.deleteData.successBody",
        fallback: "StyleTone starts from onboarding next time. Your subscription is not cancelled."
    )
    public static let deleteStartOverButton = SettingsText(
        "settings.deleteData.startOver",
        fallback: "Start over"
    )
    public static let deleteRestartHint = SettingsText(
        "settings.deleteData.restartHint",
        fallback: "Restart StyleTone to begin again."
    )
    public static let deleteFailedTitle = SettingsText(
        "settings.deleteData.failedTitle",
        fallback: "Some data could not be deleted"
    )
    public static let deleteFailedBody = SettingsText(
        "settings.deleteData.failedBody",
        fallback: "Try again. If the problem continues, restart the app and retry."
    )
    public static let deleteRetryButton = SettingsText(
        "settings.deleteData.retry",
        fallback: "Try again"
    )
    public static let deleteNoticeDeleted = SettingsText(
        "settings.deleteData.noticeDeleted",
        fallback: "All local data deleted."
    )
    public static let deleteNoticeFailed = SettingsText(
        "settings.deleteData.noticeFailed",
        fallback: "Local data could not be fully deleted."
    )

    // MARK: Diagnostics

    public static let diagnosticsSummary = SettingsText(
        "settings.diagnostics.summary",
        fallback: "Optional. Stored only on this iPhone."
    )
    public static let diagnosticsToggle = SettingsText(
        "settings.diagnostics.toggle",
        fallback: "Share local diagnostics"
    )
    public static let diagnosticsToggleHint = SettingsText(
        "settings.diagnostics.toggleHint",
        fallback: "App events and error codes; never photos or file names."
    )
    public static let diagnosticsOnNote = SettingsText(
        "settings.diagnostics.onNote",
        fallback: "Diagnostics are on. Turning them off deletes the local log."
    )
    public static let diagnosticsOffNote = SettingsText(
        "settings.diagnostics.offNote",
        fallback: "Diagnostics are off. Nothing is collected."
    )
    public static let diagnosticsDataTitle = SettingsText(
        "settings.diagnostics.dataTitle",
        fallback: "What is collected"
    )
    public static let diagnosticsDataBody = SettingsText(
        "settings.diagnostics.dataBody",
        fallback: "Event names, error codes, timestamps, app version and OS version."
    )
    public static let diagnosticsNeverTitle = SettingsText(
        "settings.diagnostics.neverTitle",
        fallback: "Never collected"
    )
    public static let diagnosticsNeverBody = SettingsText(
        "settings.diagnostics.neverBody",
        fallback: "Photos, file names, photo library identifiers, location, contacts, email or account information."
    )
    public static let diagnosticsCodeLabel = SettingsText(
        "settings.diagnostics.codeLabel",
        fallback: "Diagnostic code"
    )
    public static let diagnosticsCodeHint = SettingsText(
        "settings.diagnostics.codeHint",
        fallback: "Include this code when you contact support."
    )
    public static let diagnosticsCopyButton = SettingsText(
        "settings.diagnostics.copyButton",
        fallback: "Copy diagnostic code"
    )
    public static let diagnosticsCopied = SettingsText(
        "settings.diagnostics.copied",
        fallback: "Diagnostic code copied."
    )
    public static let diagnosticsCopyFailed = SettingsText(
        "settings.diagnostics.copyFailed",
        fallback: "Could not copy the code."
    )
    public static let diagnosticsClearButton = SettingsText(
        "settings.diagnostics.clearButton",
        fallback: "Clear local diagnostics"
    )
    public static let diagnosticsCleared = SettingsText(
        "settings.diagnostics.cleared",
        fallback: "Local diagnostics cleared."
    )
    public static let diagnosticsClearFailed = SettingsText(
        "settings.diagnostics.clearFailed",
        fallback: "Could not clear diagnostics. Try again."
    )
    public static let diagnosticsEntries = SettingsText(
        "settings.diagnostics.entries",
        fallback: "%d entries stored on this iPhone."
    )
    public static let diagnosticsEnabledNotice = SettingsText(
        "settings.diagnostics.enabledNotice",
        fallback: "Local diagnostics on."
    )
    public static let diagnosticsDisabledNotice = SettingsText(
        "settings.diagnostics.disabledNotice",
        fallback: "Local diagnostics off. The local log was deleted."
    )
    public static let diagnosticsEnableFailed = SettingsText(
        "settings.diagnostics.enableFailed",
        fallback: "Could not turn diagnostics on."
    )
    public static let diagnosticsDisableFailed = SettingsText(
        "settings.diagnostics.disableFailed",
        fallback: "Could not turn diagnostics off. Try again."
    )
    public static let diagnosticsStatusOn = SettingsText(
        "settings.diagnostics.statusOn",
        fallback: "On"
    )
    public static let diagnosticsStatusOff = SettingsText(
        "settings.diagnostics.statusOff",
        fallback: "Off"
    )

    // MARK: Licenses

    public static let licensesLink = SettingsText("settings.licenses.link", fallback: "Licenses")
    public static let licensesSummary = SettingsText(
        "settings.licenses.summary",
        fallback: "No third-party runtime libraries."
    )
    public static let licensesDetailTitle = SettingsText(
        "settings.licenses.detailTitle",
        fallback: "Licenses"
    )
    public static let licensesIntro = SettingsText(
        "settings.licenses.intro",
        fallback: "StyleTone is built with Apple system frameworks."
    )
    public static let licensesApplicationTitle = SettingsText(
        "settings.licenses.applicationTitle",
        fallback: "Application"
    )
    public static let licensesSystemTitle = SettingsText(
        "settings.licenses.systemTitle",
        fallback: "System frameworks"
    )
    public static let licensesThirdPartyTitle = SettingsText(
        "settings.licenses.thirdPartyTitle",
        fallback: "Third-party components"
    )
    public static let licensesThirdPartyNone = SettingsText(
        "settings.licenses.thirdPartyNone",
        fallback: "This build contains no third-party runtime libraries."
    )
    public static let licensesAppBody = SettingsText(
        "settings.licenses.appBody",
        fallback: "StyleTone is proprietary software. Copyright 2026 StyleTone. All rights reserved."
    )
    public static let licensesSystemBody = SettingsText(
        "settings.licenses.systemBody",
        fallback: "SwiftUI, Foundation, Observation and StoreKit are provided by Apple under the Apple SDK License."
    )

    // MARK: Version

    public static let versionLabel = SettingsText("settings.about.version", fallback: "Version")
    public static let systemLabel = SettingsText("settings.about.system", fallback: "System")
    public static let buildLabel = SettingsText("settings.about.build", fallback: "Build")

    // MARK: Support

    public static let supportSummary = SettingsText(
        "settings.support.summary",
        fallback: "Questions or a problem? We read every message."
    )
    public static let supportBody = SettingsText(
        "settings.support.body",
        fallback: "Email us and include the diagnostic code from Diagnostics. "
            + "That helps us find the issue without asking for photos."
    )
    public static let supportEmailLabel = SettingsText(
        "settings.support.emailLabel",
        fallback: "Email support"
    )
    public static let supportCopyEmail = SettingsText(
        "settings.support.copyEmail",
        fallback: "Copy email address"
    )
    public static let supportEmailCopied = SettingsText(
        "settings.support.emailCopied",
        fallback: "Support email copied."
    )
    public static let supportResponse = SettingsText(
        "settings.support.response",
        fallback: "We usually reply within two business days."
    )
    public static let supportDiagnosticsHint = SettingsText(
        "settings.support.diagnosticsHint",
        fallback: "Include the diagnostic code from Diagnostics."
    )

    // MARK: Common

    public static let commonCancel = SettingsText("settings.common.cancel", fallback: "Cancel")
    public static let commonClose = SettingsText("settings.common.close", fallback: "Close")
    public static let commonDismiss = SettingsText("settings.common.dismiss", fallback: "Dismiss")
    public static let commonCopy = SettingsText("settings.common.copy", fallback: "Copy")
    public static let footerNote = SettingsText(
        "settings.footer.note",
        fallback: "No account. No sign-in. No cloud sync. Photos are processed on this iPhone."
    )

    // MARK: Errors

    public static let copyFailed = SettingsText(
        "error.settings.copyFailed",
        fallback: "Could not copy to the clipboard."
    )

    /// Every text this feature defines, for catalog and key tests.
    public static let all: [SettingsText] = [
        title, subtitle, sectionPrivacy, sectionDiagnostics, sectionSubscription, sectionAbout,
        sectionSupport,
        privacySummary, privacyBody, privacyLink, privacyPolicy, privacyPolicyUnavailable,
        privacyNoAccount, privacyDetailTitle, privacyIntro, privacyLocalTitle, privacyLocalPhotos,
        privacyLocalStyle, privacyLocalHistory, privacyLocalDiagnostics, privacyLeavesTitle,
        privacyLeavesNothing, privacyLeavesApple, privacyCollectTitle, privacyCollectBody,
        privacyControlsTitle, privacyControlsBody, privacyNoAccountNote,
        subscriptionBody, subscriptionHint,
        deleteDataButton, deleteDataHint, deleteSheetTitle, deleteSheetIntro, deleteRemoveTitle,
        deleteRemoveProfiles, deleteRemovePairs, deleteRemoveQuota, deleteRemoveDiagnostics,
        deleteRemoveTemporary, deleteKeepTitle, deleteKeepPhotos, deleteKeepPurchase,
        deleteKeepSubscription, deleteCancelButton, deleteContinueButton, deleteBackButton,
        deleteFinalTitle, deleteFinalMessage, deleteFinalConfirm, deleteProgress,
        deleteSuccessTitle, deleteSuccessBody, deleteStartOverButton, deleteRestartHint,
        deleteFailedTitle, deleteFailedBody, deleteRetryButton, deleteNoticeDeleted,
        deleteNoticeFailed,
        diagnosticsSummary, diagnosticsToggle, diagnosticsToggleHint, diagnosticsOnNote,
        diagnosticsOffNote, diagnosticsDataTitle, diagnosticsDataBody, diagnosticsNeverTitle,
        diagnosticsNeverBody, diagnosticsCodeLabel, diagnosticsCodeHint, diagnosticsCopyButton,
        diagnosticsCopied, diagnosticsCopyFailed, diagnosticsClearButton, diagnosticsCleared,
        diagnosticsClearFailed, diagnosticsEntries, diagnosticsEnabledNotice,
        diagnosticsDisabledNotice, diagnosticsEnableFailed, diagnosticsDisableFailed,
        diagnosticsStatusOn, diagnosticsStatusOff,
        licensesLink, licensesSummary, licensesDetailTitle, licensesIntro,
        licensesApplicationTitle, licensesSystemTitle, licensesThirdPartyTitle,
        licensesThirdPartyNone, licensesAppBody, licensesSystemBody,
        versionLabel, systemLabel, buildLabel,
        supportSummary, supportBody, supportEmailLabel, supportCopyEmail, supportEmailCopied,
        supportResponse, supportDiagnosticsHint,
        commonCancel, commonClose, commonDismiss, commonCopy, footerNote, copyFailed,
    ]

    /// The entries line for the diagnostics card.
    public static func entriesText(count: Int) -> String {
        diagnosticsEntries.formatted(max(0, count))
    }
}
