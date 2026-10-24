import Foundation

/// Allowed localization key prefixes.
///
/// The first seven prefixes are fixed by the UI contract
/// (`docs/10-task-decomposition/contracts.md` §8). `shell` and `common` are
/// reserved by WP-03 for app-shell copy and shared actions; feature work
/// packages must keep their copy under their own domain prefix.
public enum LocalizationPrefix: String, CaseIterable, Sendable {
    case onboarding
    case pairing
    case calibration
    case editor
    case paywall
    case settings
    case error
    case shell
    case common

    /// Prefix including the trailing dot, e.g. `editor.`.
    public var prefix: String {
        "\(rawValue)."
    }

    /// The prefix of a key, when it is one of the allowed prefixes.
    public static func of(_ key: String) -> LocalizationPrefix? {
        guard let first = key.split(separator: ".", maxSplits: 1).first else {
            return nil
        }
        return LocalizationPrefix(rawValue: String(first))
    }
}

/// A localization key such as `editor.faceSlim`.
///
/// Keys are not user-facing text. Resolve them through `String(localized:)`
/// (see `L10n.resolve`) and never hardcode Chinese in Swift sources.
public struct LocalizationKey: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var prefix: LocalizationPrefix? {
        LocalizationPrefix.of(rawValue)
    }

    /// Whether the key uses an allowed prefix and valid segments.
    public var isValid: Bool {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let first = parts.first,
              LocalizationPrefix(rawValue: String(first)) != nil
        else {
            return false
        }
        return parts.dropFirst().allSatisfy(DesignIdentifierValidation.isValidElementSegment)
    }
}

/// The frozen localization keys used by the app shell and design system.
///
/// A string catalog is owned by WP-26 (`Localizable.xcstrings`). Until it
/// exists, `L10n.resolve` returns the English development fallback supplied by
/// the call site, so placeholder screens stay readable without putting Chinese
/// literals into code.
public enum L10n {
    // MARK: Shell

    public static let shellTabEditor = LocalizationKey("shell.tab.editor")
    public static let shellTabStyle = LocalizationKey("shell.tab.style")
    public static let shellTabSettings = LocalizationKey("shell.tab.settings")
    public static let shellPlaceholderBadge = LocalizationKey("shell.placeholder.badge")
    public static let shellToastPlaceholder = LocalizationKey("shell.toast.placeholder")

    // MARK: Common

    public static let commonCloseButton = LocalizationKey("common.closeButton")
    public static let commonDismissButton = LocalizationKey("common.dismissButton")

    // MARK: Onboarding

    public static let onboardingTitle = LocalizationKey("onboarding.title")
    public static let onboardingSubtitle = LocalizationKey("onboarding.subtitle")
    public static let onboardingNote = LocalizationKey("onboarding.note")
    public static let onboardingStartButton = LocalizationKey("onboarding.startButton")
    public static let onboardingNaturalDefaultButton = LocalizationKey("onboarding.naturalDefaultButton")

    // MARK: Pairing

    public static let pairingTitle = LocalizationKey("pairing.title")
    public static let pairingSubtitle = LocalizationKey("pairing.subtitle")
    public static let pairingNote = LocalizationKey("pairing.note")
    public static let pairingAddPairButton = LocalizationKey("pairing.addPairButton")
    public static let pairingContinueButton = LocalizationKey("pairing.continueButton")
    public static let pairingChecklistTitle = LocalizationKey("pairing.checklistTitle")
    public static let pairingToastPlaceholder = LocalizationKey("pairing.toast.placeholder")

    // MARK: Calibration

    public static let calibrationTitle = LocalizationKey("calibration.title")
    public static let calibrationSubtitle = LocalizationKey("calibration.subtitle")
    public static let calibrationNote = LocalizationKey("calibration.note")
    public static let calibrationPath = LocalizationKey("calibration.path")
    public static let calibrationStartButton = LocalizationKey("calibration.startButton")
    public static let calibrationAddPairsButton = LocalizationKey("calibration.addPairsButton")
    public static let calibrationStyleCardButton = LocalizationKey("calibration.styleCardButton")
    public static let calibrationStyleCardTitle = LocalizationKey("calibration.styleCard.title")
    public static let calibrationStyleCardNote = LocalizationKey("calibration.styleCard.note")
    public static let calibrationRecalibrateButton = LocalizationKey("calibration.recalibrateButton")
    public static let calibrationToastPlaceholder = LocalizationKey("calibration.toast.placeholder")

    // MARK: Editor

    public static let editorTitle = LocalizationKey("editor.title")
    public static let editorSubtitle = LocalizationKey("editor.subtitle")
    public static let editorNote = LocalizationKey("editor.note")
    public static let editorCanvasEmptyTitle = LocalizationKey("editor.canvas.emptyTitle")
    public static let editorCanvasEmptyMessage = LocalizationKey("editor.canvas.emptyMessage")
    public static let editorSectionFace = LocalizationKey("editor.section.face")
    public static let editorSectionFaceNote = LocalizationKey("editor.section.faceNote")
    public static let editorSectionSkin = LocalizationKey("editor.section.skin")
    public static let editorSectionSkinNote = LocalizationKey("editor.section.skinNote")
    public static let editorFaceSlim = LocalizationKey("editor.faceSlim")
    public static let editorJaw = LocalizationKey("editor.jaw")
    public static let editorSmoothing = LocalizationKey("editor.smoothing")
    public static let editorAddPhotoButton = LocalizationKey("editor.addPhotoButton")
    public static let editorExportButton = LocalizationKey("editor.exportButton")
    public static let editorStyleButton = LocalizationKey("editor.styleButton")
    public static let editorToastPlaceholder = LocalizationKey("editor.toast.placeholder")

    // MARK: Settings

    public static let settingsTitle = LocalizationKey("settings.title")
    public static let settingsSubtitle = LocalizationKey("settings.subtitle")
    public static let settingsNote = LocalizationKey("settings.note")
    public static let settingsLocalDataTitle = LocalizationKey("settings.localDataTitle")
    public static let settingsStyleCardButton = LocalizationKey("settings.styleCardButton")
    public static let settingsPaywallButton = LocalizationKey("settings.paywallButton")
    public static let settingsOnboardingButton = LocalizationKey("settings.onboardingButton")
    public static let settingsDeleteDataButton = LocalizationKey("settings.deleteDataButton")
    public static let settingsDeleteDataToast = LocalizationKey("settings.deleteData.toast")
    public static let settingsPrivacyNote = LocalizationKey("settings.privacyNote")

    // MARK: Paywall

    public static let paywallTitle = LocalizationKey("paywall.title")
    public static let paywallSubtitle = LocalizationKey("paywall.subtitle")
    public static let paywallNote = LocalizationKey("paywall.note")
    public static let paywallSubscribeButton = LocalizationKey("paywall.subscribeButton")
    public static let paywallRestoreButton = LocalizationKey("paywall.restoreButton")
    public static let paywallCloseButton = LocalizationKey("paywall.closeButton")
    public static let paywallToastPlaceholder = LocalizationKey("paywall.toast.placeholder")

    // MARK: Export

    public static let exportTitle = LocalizationKey("export.title")
    public static let exportSubtitle = LocalizationKey("export.subtitle")
    public static let exportNote = LocalizationKey("export.note")
    public static let exportPreviewTitle = LocalizationKey("export.previewTitle")
    public static let exportButton = LocalizationKey("export.exportButton")
    public static let exportCloseButton = LocalizationKey("export.closeButton")
    public static let exportLoading = LocalizationKey("export.loading")
    public static let exportLoadingToggle = LocalizationKey("export.loadingToggle")
    public static let exportToastPlaceholder = LocalizationKey("export.toast.placeholder")

    /// Every key defined above.
    public static let allKeys: [LocalizationKey] = [
        shellTabEditor,
        shellTabStyle,
        shellTabSettings,
        shellPlaceholderBadge,
        shellToastPlaceholder,
        commonCloseButton,
        commonDismissButton,
        onboardingTitle,
        onboardingSubtitle,
        onboardingNote,
        onboardingStartButton,
        onboardingNaturalDefaultButton,
        pairingTitle,
        pairingSubtitle,
        pairingNote,
        pairingAddPairButton,
        pairingContinueButton,
        pairingChecklistTitle,
        pairingToastPlaceholder,
        calibrationTitle,
        calibrationSubtitle,
        calibrationNote,
        calibrationPath,
        calibrationStartButton,
        calibrationAddPairsButton,
        calibrationStyleCardButton,
        calibrationStyleCardTitle,
        calibrationStyleCardNote,
        calibrationRecalibrateButton,
        calibrationToastPlaceholder,
        editorTitle,
        editorSubtitle,
        editorNote,
        editorCanvasEmptyTitle,
        editorCanvasEmptyMessage,
        editorSectionFace,
        editorSectionFaceNote,
        editorSectionSkin,
        editorSectionSkinNote,
        editorFaceSlim,
        editorJaw,
        editorSmoothing,
        editorAddPhotoButton,
        editorExportButton,
        editorStyleButton,
        editorToastPlaceholder,
        settingsTitle,
        settingsSubtitle,
        settingsNote,
        settingsLocalDataTitle,
        settingsStyleCardButton,
        settingsPaywallButton,
        settingsOnboardingButton,
        settingsDeleteDataButton,
        settingsDeleteDataToast,
        settingsPrivacyNote,
        paywallTitle,
        paywallSubtitle,
        paywallNote,
        paywallSubscribeButton,
        paywallRestoreButton,
        paywallCloseButton,
        paywallToastPlaceholder,
        exportTitle,
        exportSubtitle,
        exportNote,
        exportPreviewTitle,
        exportButton,
        exportCloseButton,
        exportLoading,
        exportLoadingToggle,
        exportToastPlaceholder,
    ]

    /// Resolves a key, returning `fallback` while no string catalog is present.
    ///
    /// This is the only place in the design system that calls
    /// `String(localized:)`. Callers pass an English development fallback so
    /// placeholder screens remain readable; zh-Hans copy arrives with the
    /// string catalog (WP-26).
    public static func resolve(_ key: LocalizationKey, fallback: String) -> String {
        let localized = String(localized: String.LocalizationValue(key.rawValue))
        return localized == key.rawValue ? fallback : localized
    }
}
