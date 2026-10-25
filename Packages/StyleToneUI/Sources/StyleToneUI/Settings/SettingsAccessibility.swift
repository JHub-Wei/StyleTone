import Foundation

/// Accessibility identifiers owned by the settings screen.
///
/// Identifiers follow the frozen `screen.element` convention (contracts
/// section 8) and reuse the four settings identifiers reserved by the design
/// system. Feature code only adds identifiers under `settings.`.
public enum SettingsAccessibilityID {
    /// Root of the settings screen; equals `AppRoute.settings.accessibilityID`.
    public static let screen = AccessibilityID(.settings, "root")

    // Privacy
    public static let privacyButton = AccessibilityID(.settings, "privacyButton")
    public static let privacyScreen = AccessibilityID(.settings, "privacy.root")
    public static let privacyPolicyLink = AccessibilityID(.settings, "privacy.policyLink")
    public static let privacyNote = AccessibilityID(.settings, "privacy.note")

    // Diagnostics
    public static let diagnosticsSection = AccessibilityID(.settings, "diagnosticsSection")
    public static let diagnosticsToggle = AccessibilityID(.settings, "diagnosticsToggle")
    public static let diagnosticsStatus = AccessibilityID(.settings, "diagnostics.status")
    public static let diagnosticsData = AccessibilityID(.settings, "diagnostics.data")
    public static let diagnosticsNeverData = AccessibilityID(.settings, "diagnostics.neverData")
    public static let diagnosticsCode = AccessibilityID(.settings, "diagnostics.code")
    public static let diagnosticsCodeHint = AccessibilityID(.settings, "diagnostics.codeHint")
    public static let diagnosticsCopyButton = AccessibilityID(.settings, "diagnostics.copyButton")
    public static let diagnosticsClearButton = AccessibilityID(.settings, "diagnostics.clearButton")
    public static let diagnosticsEntries = AccessibilityID(.settings, "diagnostics.entries")

    // Subscription and deletion
    public static let subscriptionNote = AccessibilityID(.settings, "subscription.note")
    public static let deleteDataButton = AccessibilityID.settingsDeleteDataButton
    public static let deleteDataHint = AccessibilityID(.settings, "deleteData.hint")
    public static let deleteSheet = AccessibilityID(.settings, "deleteData.sheet")
    public static let deleteCancelButton = AccessibilityID(.settings, "deleteData.cancelButton")
    public static let deleteContinueButton = AccessibilityID(.settings, "deleteData.continueButton")
    public static let deleteBackButton = AccessibilityID(.settings, "deleteData.backButton")
    public static let deleteFinalButton = AccessibilityID(.settings, "deleteData.finalButton")
    public static let deleteProgress = AccessibilityID(.settings, "deleteData.progress")
    public static let deleteSuccess = AccessibilityID(.settings, "deleteData.success")
    public static let deleteStartOverButton = AccessibilityID(.settings, "deleteData.startOverButton")
    public static let deleteRetryButton = AccessibilityID(.settings, "deleteData.retryButton")
    public static let deleteFailure = AccessibilityID(.settings, "deleteData.failure")

    // About and support
    public static let licensesButton = AccessibilityID(.settings, "licensesButton")
    public static let licensesScreen = AccessibilityID(.settings, "licenses.root")
    public static let versionRow = AccessibilityID(.settings, "versionRow")
    public static let buildRow = AccessibilityID(.settings, "buildRow")
    public static let systemRow = AccessibilityID(.settings, "systemRow")
    public static let supportSection = AccessibilityID(.settings, "supportSection")
    public static let supportEmailLink = AccessibilityID(.settings, "support.emailLink")
    public static let supportCopyButton = AccessibilityID(.settings, "support.copyButton")
    public static let supportResponse = AccessibilityID(.settings, "support.response")
    public static let supportPrivacyLink = AccessibilityID(.settings, "support.privacyLink")

    // Shared notes
    public static let noAccountNote = AccessibilityID(.settings, "noAccountNote")
    public static let notice = AccessibilityID(.settings, "notice")

    /// Every settings identifier, including the frozen design-system entries
    /// this screen uses. Tests keep the list valid, unique and screen-scoped.
    public static let all: [AccessibilityID] = [
        screen,
        deleteDataButton,
        privacyButton,
        privacyScreen,
        privacyPolicyLink,
        privacyNote,
        diagnosticsSection,
        diagnosticsToggle,
        diagnosticsStatus,
        diagnosticsData,
        diagnosticsNeverData,
        diagnosticsCode,
        diagnosticsCodeHint,
        diagnosticsCopyButton,
        diagnosticsClearButton,
        diagnosticsEntries,
        subscriptionNote,
        deleteDataHint,
        deleteSheet,
        deleteCancelButton,
        deleteContinueButton,
        deleteBackButton,
        deleteFinalButton,
        deleteProgress,
        deleteSuccess,
        deleteStartOverButton,
        deleteRetryButton,
        deleteFailure,
        licensesButton,
        licensesScreen,
        versionRow,
        buildRow,
        systemRow,
        supportSection,
        supportEmailLink,
        supportCopyButton,
        supportResponse,
        supportPrivacyLink,
        noAccountNote,
        notice,
    ]
}
