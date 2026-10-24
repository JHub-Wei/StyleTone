import Foundation

/// Screens that own accessibility identifiers.
///
/// Identifier convention (frozen by WP-03): `screen.element`, for example
/// `onboarding.startButton`, `pairing.addPairButton`,
/// `editor.faceSlimSlider` or `paywall.subscribeButton`. Screens should expose
/// only elements that a UI test or VoiceOver user needs to address.
public enum AccessibilityScreen: String, CaseIterable, Sendable {
    case shell
    case onboarding
    case pairing
    case calibration
    case editor
    case styleProfile
    case settings
    case paywall
    case export
    case designSystem
}

/// A validated accessibility identifier.
public struct AccessibilityID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Builds an identifier from a screen and one or more element segments.
    public init(_ screen: AccessibilityScreen, _ element: String) {
        self.rawValue = "\(screen.rawValue).\(element)"
    }

    public var description: String {
        rawValue
    }

    /// The screen segment, when the identifier starts with a known screen.
    public var screen: AccessibilityScreen? {
        guard let first = rawValue.split(separator: ".", maxSplits: 1).first else {
            return nil
        }
        return AccessibilityScreen(rawValue: String(first))
    }

    /// Whether the identifier follows the frozen `screen.element` convention.
    public var isValid: Bool {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let first = parts.first,
              AccessibilityScreen(rawValue: String(first)) != nil
        else {
            return false
        }
        return parts.dropFirst().allSatisfy(DesignIdentifierValidation.isValidElementSegment)
    }
}

// MARK: - Frozen identifiers

public extension AccessibilityID {
    // Shell
    static let shellRoot = AccessibilityID(.shell, "root")
    static let shellTabEditor = AccessibilityID(.shell, "tab.editor")
    static let shellTabStyle = AccessibilityID(.shell, "tab.style")
    static let shellTabSettings = AccessibilityID(.shell, "tab.settings")

    // Onboarding
    static let onboardingStartButton = AccessibilityID(.onboarding, "startButton")
    static let onboardingNaturalDefaultButton = AccessibilityID(.onboarding, "naturalDefaultButton")

    // Pairing
    static let pairingAddPairButton = AccessibilityID(.pairing, "addPairButton")
    static let pairingContinueButton = AccessibilityID(.pairing, "continueButton")

    // Calibration
    static let calibrationStartButton = AccessibilityID(.calibration, "startButton")
    static let calibrationAddPairsButton = AccessibilityID(.calibration, "addPairsButton")
    static let calibrationStyleCardButton = AccessibilityID(.calibration, "styleCardButton")
    static let calibrationRecalibrateButton = AccessibilityID(.calibration, "recalibrateButton")

    // Editor
    static let editorCanvas = AccessibilityID(.editor, "canvas")
    static let editorFaceSlimSlider = AccessibilityID(.editor, "faceSlimSlider")
    static let editorJawSlider = AccessibilityID(.editor, "jawSlider")
    static let editorSmoothingSlider = AccessibilityID(.editor, "smoothingSlider")
    static let editorAddPhotoButton = AccessibilityID(.editor, "addPhotoButton")
    static let editorExportButton = AccessibilityID(.editor, "exportButton")
    static let editorStyleButton = AccessibilityID(.editor, "styleButton")

    // Style profile
    static let styleProfileRecalibrateButton = AccessibilityID(.styleProfile, "recalibrateButton")

    // Settings
    static let settingsStyleCardButton = AccessibilityID(.settings, "styleCardButton")
    static let settingsPaywallButton = AccessibilityID(.settings, "paywallButton")
    static let settingsOnboardingButton = AccessibilityID(.settings, "onboardingButton")
    static let settingsDeleteDataButton = AccessibilityID(.settings, "deleteDataButton")

    // Paywall
    static let paywallSubscribeButton = AccessibilityID(.paywall, "subscribeButton")
    static let paywallRestoreButton = AccessibilityID(.paywall, "restoreButton")
    static let paywallCloseButton = AccessibilityID(.paywall, "closeButton")

    // Export
    static let exportExportButton = AccessibilityID(.export, "exportButton")
    static let exportCloseButton = AccessibilityID(.export, "closeButton")
    static let exportLoadingToggle = AccessibilityID(.export, "loadingToggle")
    static let exportLoading = AccessibilityID(.export, "loading")

    // Design system components
    static let designSystemLoading = AccessibilityID(.designSystem, "loading")
    static let designSystemToast = AccessibilityID(.designSystem, "toast")
    static let designSystemPhotoCanvas = AccessibilityID(.designSystem, "photoCanvas")

    /// Every predefined identifier, used by tests to keep the convention frozen.
    static let all: [AccessibilityID] = [
        shellRoot,
        shellTabEditor,
        shellTabStyle,
        shellTabSettings,
        onboardingStartButton,
        onboardingNaturalDefaultButton,
        pairingAddPairButton,
        pairingContinueButton,
        calibrationStartButton,
        calibrationAddPairsButton,
        calibrationStyleCardButton,
        calibrationRecalibrateButton,
        editorCanvas,
        editorFaceSlimSlider,
        editorJawSlider,
        editorSmoothingSlider,
        editorAddPhotoButton,
        editorExportButton,
        editorStyleButton,
        styleProfileRecalibrateButton,
        settingsStyleCardButton,
        settingsPaywallButton,
        settingsOnboardingButton,
        settingsDeleteDataButton,
        paywallSubscribeButton,
        paywallRestoreButton,
        paywallCloseButton,
        exportExportButton,
        exportCloseButton,
        exportLoadingToggle,
        exportLoading,
        designSystemLoading,
        designSystemToast,
        designSystemPhotoCanvas,
    ]
}

/// Shared validation for design-system identifiers and localization keys.
enum DesignIdentifierValidation {
    /// A segment starts with a lowercase ASCII letter and continues with ASCII
    /// letters or digits. Nested segments are allowed (`tab.editor`).
    static func isValidElementSegment(_ segment: Substring) -> Bool {
        guard let first = segment.unicodeScalars.first,
              (97...122).contains(first.value)
        else {
            return false
        }
        return segment.unicodeScalars.allSatisfy { scalar in
            (97...122).contains(scalar.value)
                || (65...90).contains(scalar.value)
                || (48...57).contains(scalar.value)
        }
    }
}
