import StyleToneUI

/// Development copy for the app shell.
///
/// Every visible string is resolved from a frozen `L10n` key. Until the zh-Hans
/// string catalog lands (WP-26), `L10n.resolve` returns these English
/// development fallbacks; no Chinese literal is hardcoded in Swift sources.
enum ShellCopy {
    // MARK: Shell

    static let tabEditor = L10n.resolve(.shellTabEditor, fallback: "Editor")
    static let tabStyle = L10n.resolve(.shellTabStyle, fallback: "Style")
    static let tabSettings = L10n.resolve(.shellTabSettings, fallback: "Settings")
    static let placeholderBadge = L10n.resolve(
        .shellPlaceholderBadge,
        fallback: "Placeholder screen · feature lands in a later work package"
    )
    static let dismissButton = L10n.resolve(.commonDismissButton, fallback: "Dismiss")
    static let closeButton = L10n.resolve(.commonCloseButton, fallback: "Close")
    static let toastPlaceholder = L10n.resolve(
        .shellToastPlaceholder,
        fallback: "This action is a placeholder in the shell build."
    )

    // MARK: Onboarding

    static let onboardingTitle = L10n.resolve(.onboardingTitle, fallback: "Welcome to StyleTone")
    static let onboardingSubtitle = L10n.resolve(
        .onboardingSubtitle,
        fallback: "A personal photo style, learned and applied on this iPhone."
    )
    static let onboardingNote = L10n.resolve(
        .onboardingNote,
        fallback: "No account, no upload. Calibrate with a few before/after pairs, or start with the natural default."
    )
    static let onboardingStartButton = L10n.resolve(.onboardingStartButton, fallback: "Start calibration")
    static let onboardingNaturalDefaultButton = L10n.resolve(
        .onboardingNaturalDefaultButton,
        fallback: "Use natural default"
    )

    // MARK: Pairing

    static let pairingTitle = L10n.resolve(.pairingTitle, fallback: "Add photo pairs")
    static let pairingSubtitle = L10n.resolve(
        .pairingSubtitle,
        fallback: "Choose a finished photo you like, then the original from the same scene."
    )
    static let pairingNote = L10n.resolve(
        .pairingNote,
        fallback: "Pair import, quality checks and session persistence arrive with WP-09."
    )
    static let pairingChecklistTitle = L10n.resolve(.pairingChecklistTitle, fallback: "What to choose")
    static let pairingAddPairButton = L10n.resolve(.pairingAddPairButton, fallback: "Add a pair")
    static let pairingContinueButton = L10n.resolve(
        .pairingContinueButton,
        fallback: "Continue to calibration"
    )
    static let pairingToast = L10n.resolve(
        .pairingToastPlaceholder,
        fallback: "Pair import is not connected in this shell build."
    )

    // MARK: Calibration

    static let calibrationTitle = L10n.resolve(.calibrationTitle, fallback: "Calibrate your style")
    static let calibrationSubtitle = L10n.resolve(
        .calibrationSubtitle,
        fallback: "Three pairs unlock a trial style; five to eight make it stable."
    )
    static let calibrationNote = L10n.resolve(
        .calibrationNote,
        fallback: "The A/B flow is a placeholder until WP-10. Your calibration will stay local."
    )
    static let calibrationPathTitle = L10n.resolve(.calibrationPath, fallback: "Calibration path")
    static let calibrationStartButton = L10n.resolve(
        .calibrationStartButton,
        fallback: "Start A/B calibration"
    )
    static let calibrationAddPairsButton = L10n.resolve(.calibrationAddPairsButton, fallback: "Add photo pairs")
    static let calibrationStyleCardButton = L10n.resolve(
        .calibrationStyleCardButton,
        fallback: "View style card"
    )
    static let calibrationStyleCardTitle = L10n.resolve(
        .calibrationStyleCardTitle,
        fallback: "Your style card"
    )
    static let calibrationStyleCardNote = L10n.resolve(
        .calibrationStyleCardNote,
        fallback: "No profile yet. Calibrate when you are ready, or keep the natural default."
    )
    static let calibrationRecalibrateButton = L10n.resolve(
        .calibrationRecalibrateButton,
        fallback: "Recalibrate"
    )
    static let calibrationToast = L10n.resolve(
        .calibrationToastPlaceholder,
        fallback: "Calibration is not connected in this shell build."
    )

    // MARK: Editor

    static let editorTitle = L10n.resolve(.editorTitle, fallback: "Editor")
    static let editorSubtitle = L10n.resolve(
        .editorSubtitle,
        fallback: "Four tool areas; at most five sliders each. Keep the photo in charge."
    )
    static let editorNote = L10n.resolve(
        .editorNote,
        fallback: "Preview only. Rendering, proxy previews and undo arrive with WP-17."
    )
    static let editorCanvasEmptyTitle = L10n.resolve(
        .editorCanvasEmptyTitle,
        fallback: "Open a portrait to begin"
    )
    static let editorCanvasEmptyMessage = L10n.resolve(
        .editorCanvasEmptyMessage,
        fallback: "The photo picker is not connected in this shell build."
    )
    static let editorSectionFace = L10n.resolve(.editorSectionFace, fallback: "Face")
    static let editorSectionFaceNote = L10n.resolve(
        .editorSectionFaceNote,
        fallback: "Slimming and jawline, kept subtle by default."
    )
    static let editorSectionSkin = L10n.resolve(.editorSectionSkin, fallback: "Skin")
    static let editorSectionSkinNote = L10n.resolve(
        .editorSectionSkinNote,
        fallback: "Texture-preserving smoothing; no whitening."
    )
    static let editorFaceSlim = L10n.resolve(.editorFaceSlim, fallback: "Face slim")
    static let editorJaw = L10n.resolve(.editorJaw, fallback: "Jawline")
    static let editorSmoothing = L10n.resolve(.editorSmoothing, fallback: "Smoothing")
    static let editorAddPhotoButton = L10n.resolve(.editorAddPhotoButton, fallback: "Choose a photo")
    static let editorExportButton = L10n.resolve(.editorExportButton, fallback: "Export")
    static let editorStyleButton = L10n.resolve(.editorStyleButton, fallback: "Style card")
    static let editorToast = L10n.resolve(
        .editorToastPlaceholder,
        fallback: "Photo import is not connected in this shell build."
    )

    // MARK: Settings

    static let settingsTitle = L10n.resolve(.settingsTitle, fallback: "Settings")
    static let settingsSubtitle = L10n.resolve(
        .settingsSubtitle,
        fallback: "Local-first privacy, diagnostics and purchase information."
    )
    static let settingsNote = L10n.resolve(
        .settingsNote,
        fallback: "Data deletion, diagnostics and legal copy arrive with WP-21."
    )
    static let settingsLocalDataTitle = L10n.resolve(.settingsLocalDataTitle, fallback: "Local data")
    static let settingsPrivacyNote = L10n.resolve(
        .settingsPrivacyNote,
        fallback: "Photos, edits and styles stay on this device. No account is required."
    )
    static let settingsStyleCardButton = L10n.resolve(
        .settingsStyleCardButton,
        fallback: "Style card"
    )
    static let settingsPaywallButton = L10n.resolve(.settingsPaywallButton, fallback: "Subscription")
    static let settingsOnboardingButton = L10n.resolve(
        .settingsOnboardingButton,
        fallback: "Replay onboarding"
    )
    static let settingsDeleteDataButton = L10n.resolve(
        .settingsDeleteDataButton,
        fallback: "Delete local data"
    )
    static let settingsDeleteDataToast = L10n.resolve(
        .settingsDeleteDataToast,
        fallback: "Deletion is not connected in this shell build."
    )

    // MARK: Paywall

    static let paywallTitle = L10n.resolve(.paywallTitle, fallback: "StyleTone Pro")
    static let paywallSubtitle = L10n.resolve(
        .paywallSubtitle,
        fallback: "Unlimited exports after three free ones."
    )
    static let paywallNote = L10n.resolve(
        .paywallNote,
        fallback: "Monthly plan, price and restore flow arrive with WP-20. Nothing is charged in this build."
    )
    static let paywallSubscribeButton = L10n.resolve(.paywallSubscribeButton, fallback: "Subscribe")
    static let paywallRestoreButton = L10n.resolve(
        .paywallRestoreButton,
        fallback: "Restore purchases"
    )
    static let paywallCloseButton = L10n.resolve(.paywallCloseButton, fallback: "Not now")
    static let paywallToast = L10n.resolve(
        .paywallToastPlaceholder,
        fallback: "Purchases are not connected in this shell build."
    )

    // MARK: Export

    static let exportTitle = L10n.resolve(.exportTitle, fallback: "Export")
    static let exportSubtitle = L10n.resolve(
        .exportSubtitle,
        fallback: "Full-resolution HEIC or JPEG, location removed by default."
    )
    static let exportNote = L10n.resolve(
        .exportNote,
        fallback: "Export pipeline and photo-library permissions arrive with WP-19."
    )
    static let exportPreviewTitle = L10n.resolve(.exportPreviewTitle, fallback: "Preview")
    static let exportButton = L10n.resolve(.exportButton, fallback: "Export now")
    static let exportCloseButton = L10n.resolve(.exportCloseButton, fallback: "Close")
    static let exportLoading = L10n.resolve(
        .exportLoading,
        fallback: "Rendering at full resolution…"
    )
    static let exportLoadingToggle = L10n.resolve(
        .exportLoadingToggle,
        fallback: "Preview loading state"
    )
    static let exportToast = L10n.resolve(
        .exportToastPlaceholder,
        fallback: "Export is not connected in this shell build."
    )
}
