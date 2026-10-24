import StyleToneUI

/// Development copy for the app shell.
///
/// Every visible string is resolved from a frozen `L10n` key. Until the zh-Hans
/// string catalog lands (WP-26), `L10n.resolve` returns these English
/// development fallbacks; no Chinese literal is hardcoded in Swift sources.
enum ShellCopy {
    // MARK: Shell

    static let tabEditor = L10n.resolve(L10n.shellTabEditor, fallback: "Editor")
    static let tabStyle = L10n.resolve(L10n.shellTabStyle, fallback: "Style")
    static let tabSettings = L10n.resolve(L10n.shellTabSettings, fallback: "Settings")
    static let placeholderBadge = L10n.resolve(
        L10n.shellPlaceholderBadge,
        fallback: "Placeholder screen · feature lands in a later work package"
    )
    static let dismissButton = L10n.resolve(L10n.commonDismissButton, fallback: "Dismiss")
    static let closeButton = L10n.resolve(L10n.commonCloseButton, fallback: "Close")
    static let toastPlaceholder = L10n.resolve(
        L10n.shellToastPlaceholder,
        fallback: "This action is a placeholder in the shell build."
    )

    // MARK: Onboarding

    static let onboardingTitle = L10n.resolve(L10n.onboardingTitle, fallback: "Welcome to StyleTone")
    static let onboardingSubtitle = L10n.resolve(
        L10n.onboardingSubtitle,
        fallback: "A personal photo style, learned and applied on this iPhone."
    )
    static let onboardingNote = L10n.resolve(
        L10n.onboardingNote,
        fallback: "No account, no upload. Calibrate with a few before/after pairs, or start with the natural default."
    )
    static let onboardingStartButton = L10n.resolve(L10n.onboardingStartButton, fallback: "Start calibration")
    static let onboardingNaturalDefaultButton = L10n.resolve(
        L10n.onboardingNaturalDefaultButton,
        fallback: "Use natural default"
    )

    // MARK: Pairing

    static let pairingTitle = L10n.resolve(L10n.pairingTitle, fallback: "Add photo pairs")
    static let pairingSubtitle = L10n.resolve(
        L10n.pairingSubtitle,
        fallback: "Choose a finished photo you like, then the original from the same scene."
    )
    static let pairingNote = L10n.resolve(
        L10n.pairingNote,
        fallback: "Pair import, quality checks and session persistence arrive with WP-09."
    )
    static let pairingChecklistTitle = L10n.resolve(L10n.pairingChecklistTitle, fallback: "What to choose")
    static let pairingAddPairButton = L10n.resolve(L10n.pairingAddPairButton, fallback: "Add a pair")
    static let pairingContinueButton = L10n.resolve(
        L10n.pairingContinueButton,
        fallback: "Continue to calibration"
    )
    static let pairingToast = L10n.resolve(
        L10n.pairingToastPlaceholder,
        fallback: "Pair import is not connected in this shell build."
    )

    // MARK: Calibration

    static let calibrationTitle = L10n.resolve(L10n.calibrationTitle, fallback: "Calibrate your style")
    static let calibrationSubtitle = L10n.resolve(
        L10n.calibrationSubtitle,
        fallback: "Three pairs unlock a trial style; five to eight make it stable."
    )
    static let calibrationNote = L10n.resolve(
        L10n.calibrationNote,
        fallback: "The A/B flow is a placeholder until WP-10. Your calibration will stay local."
    )
    static let calibrationPathTitle = L10n.resolve(L10n.calibrationPath, fallback: "Calibration path")
    static let calibrationStartButton = L10n.resolve(
        L10n.calibrationStartButton,
        fallback: "Start A/B calibration"
    )
    static let calibrationAddPairsButton = L10n.resolve(L10n.calibrationAddPairsButton, fallback: "Add photo pairs")
    static let calibrationStyleCardButton = L10n.resolve(
        L10n.calibrationStyleCardButton,
        fallback: "View style card"
    )
    static let calibrationStyleCardTitle = L10n.resolve(
        L10n.calibrationStyleCardTitle,
        fallback: "Your style card"
    )
    static let calibrationStyleCardNote = L10n.resolve(
        L10n.calibrationStyleCardNote,
        fallback: "No profile yet. Calibrate when you are ready, or keep the natural default."
    )
    static let calibrationRecalibrateButton = L10n.resolve(
        L10n.calibrationRecalibrateButton,
        fallback: "Recalibrate"
    )
    static let calibrationToast = L10n.resolve(
        L10n.calibrationToastPlaceholder,
        fallback: "Calibration is not connected in this shell build."
    )

    // MARK: Editor

    static let editorTitle = L10n.resolve(L10n.editorTitle, fallback: "Editor")
    static let editorSubtitle = L10n.resolve(
        L10n.editorSubtitle,
        fallback: "Four tool areas; at most five sliders each. Keep the photo in charge."
    )
    static let editorNote = L10n.resolve(
        L10n.editorNote,
        fallback: "Preview only. Rendering, proxy previews and undo arrive with WP-17."
    )
    static let editorCanvasEmptyTitle = L10n.resolve(
        L10n.editorCanvasEmptyTitle,
        fallback: "Open a portrait to begin"
    )
    static let editorCanvasEmptyMessage = L10n.resolve(
        L10n.editorCanvasEmptyMessage,
        fallback: "The photo picker is not connected in this shell build."
    )
    static let editorSectionFace = L10n.resolve(L10n.editorSectionFace, fallback: "Face")
    static let editorSectionFaceNote = L10n.resolve(
        L10n.editorSectionFaceNote,
        fallback: "Slimming and jawline, kept subtle by default."
    )
    static let editorSectionSkin = L10n.resolve(L10n.editorSectionSkin, fallback: "Skin")
    static let editorSectionSkinNote = L10n.resolve(
        L10n.editorSectionSkinNote,
        fallback: "Texture-preserving smoothing; no whitening."
    )
    static let editorFaceSlim = L10n.resolve(L10n.editorFaceSlim, fallback: "Face slim")
    static let editorJaw = L10n.resolve(L10n.editorJaw, fallback: "Jawline")
    static let editorSmoothing = L10n.resolve(L10n.editorSmoothing, fallback: "Smoothing")
    static let editorAddPhotoButton = L10n.resolve(L10n.editorAddPhotoButton, fallback: "Choose a photo")
    static let editorExportButton = L10n.resolve(L10n.editorExportButton, fallback: "Export")
    static let editorStyleButton = L10n.resolve(L10n.editorStyleButton, fallback: "Style card")
    static let editorToast = L10n.resolve(
        L10n.editorToastPlaceholder,
        fallback: "Photo import is not connected in this shell build."
    )

    // MARK: Settings

    static let settingsTitle = L10n.resolve(L10n.settingsTitle, fallback: "Settings")
    static let settingsSubtitle = L10n.resolve(
        L10n.settingsSubtitle,
        fallback: "Local-first privacy, diagnostics and purchase information."
    )
    static let settingsNote = L10n.resolve(
        L10n.settingsNote,
        fallback: "Data deletion, diagnostics and legal copy arrive with WP-21."
    )
    static let settingsLocalDataTitle = L10n.resolve(L10n.settingsLocalDataTitle, fallback: "Local data")
    static let settingsPrivacyNote = L10n.resolve(
        L10n.settingsPrivacyNote,
        fallback: "Photos, edits and styles stay on this device. No account is required."
    )
    static let settingsStyleCardButton = L10n.resolve(
        L10n.settingsStyleCardButton,
        fallback: "Style card"
    )
    static let settingsPaywallButton = L10n.resolve(L10n.settingsPaywallButton, fallback: "Subscription")
    static let settingsOnboardingButton = L10n.resolve(
        L10n.settingsOnboardingButton,
        fallback: "Replay onboarding"
    )
    static let settingsDeleteDataButton = L10n.resolve(
        L10n.settingsDeleteDataButton,
        fallback: "Delete local data"
    )
    static let settingsDeleteDataToast = L10n.resolve(
        L10n.settingsDeleteDataToast,
        fallback: "Deletion is not connected in this shell build."
    )

    // MARK: Paywall

    static let paywallTitle = L10n.resolve(L10n.paywallTitle, fallback: "StyleTone Pro")
    static let paywallSubtitle = L10n.resolve(
        L10n.paywallSubtitle,
        fallback: "Unlimited exports after three free ones."
    )
    static let paywallNote = L10n.resolve(
        L10n.paywallNote,
        fallback: "Monthly plan, price and restore flow arrive with WP-20. Nothing is charged in this build."
    )
    static let paywallSubscribeButton = L10n.resolve(L10n.paywallSubscribeButton, fallback: "Subscribe")
    static let paywallRestoreButton = L10n.resolve(
        L10n.paywallRestoreButton,
        fallback: "Restore purchases"
    )
    static let paywallCloseButton = L10n.resolve(L10n.paywallCloseButton, fallback: "Not now")
    static let paywallToast = L10n.resolve(
        L10n.paywallToastPlaceholder,
        fallback: "Purchases are not connected in this shell build."
    )

    // MARK: Export

    static let exportTitle = L10n.resolve(L10n.exportTitle, fallback: "Export")
    static let exportSubtitle = L10n.resolve(
        L10n.exportSubtitle,
        fallback: "Full-resolution HEIC or JPEG, location removed by default."
    )
    static let exportNote = L10n.resolve(
        L10n.exportNote,
        fallback: "Export pipeline and photo-library permissions arrive with WP-19."
    )
    static let exportPreviewTitle = L10n.resolve(L10n.exportPreviewTitle, fallback: "Preview")
    static let exportButton = L10n.resolve(L10n.exportButton, fallback: "Export now")
    static let exportCloseButton = L10n.resolve(L10n.commonCloseButton, fallback: "Close")
    static let exportLoading = L10n.resolve(
        L10n.exportLoading,
        fallback: "Rendering at full resolution…"
    )
    static let exportLoadingToggle = L10n.resolve(
        L10n.exportLoadingToggle,
        fallback: "Preview loading state"
    )
    static let exportToast = L10n.resolve(
        L10n.exportToastPlaceholder,
        fallback: "Export is not connected in this shell build."
    )
}
