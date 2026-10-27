import Foundation
import StyleToneCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Copies text to the system pasteboard.
///
/// Injected so copy actions are testable without touching the simulator
/// pasteboard, and so the settings screen has no platform-specific branches.
@MainActor
public protocol SettingsPasteboardWriting {
    /// Writes the text to the pasteboard. Returns `false` when the platform
    /// pasteboard is unavailable.
    func copy(_ text: String) -> Bool
}

/// Pasteboard implementation for the app.
@MainActor
public struct SystemSettingsPasteboard: SettingsPasteboardWriting {
    public init() {}

    public func copy(_ text: String) -> Bool {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        return true
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
        #else
        return false
        #endif
    }
}

/// Everything the settings screen needs from the host.
///
/// The screen itself never imports Persistence, StoreKit or any network API;
/// the composition root supplies protocol implementations. `live` wires the
/// production stores, while `placeholder` stays in memory for previews.
@MainActor
public struct SettingsDependencies {
    public var diagnostics: any SettingsDiagnosticsControlling
    public var dataDeleter: any SettingsLocalDataDeleting
    public var versionProvider: any SettingsVersionProviding
    public var licenseProvider: any SettingsLicenseProviding
    public var support: SettingsSupportInfo
    public var pasteboard: any SettingsPasteboardWriting
    public var dateProvider: any DateProviding

    public init(
        diagnostics: any SettingsDiagnosticsControlling,
        dataDeleter: any SettingsLocalDataDeleting,
        versionProvider: any SettingsVersionProviding,
        licenseProvider: any SettingsLicenseProviding,
        support: SettingsSupportInfo,
        pasteboard: any SettingsPasteboardWriting,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.diagnostics = diagnostics
        self.dataDeleter = dataDeleter
        self.versionProvider = versionProvider
        self.licenseProvider = licenseProvider
        self.support = support
        self.pasteboard = pasteboard
        self.dateProvider = dateProvider
    }

    /// In-memory container for previews and placeholder screens.
    public static let placeholder: SettingsDependencies = {
        let versionProvider = StaticSettingsVersionProvider(.preview)
        let diagnostics = SettingsDiagnosticsService(
            preferences: InMemorySettingsDiagnosticsPreferences(),
            store: InMemorySettingsDiagnosticsLogStore(),
            versionProvider: versionProvider
        )
        return SettingsDependencies(
            diagnostics: diagnostics,
            dataDeleter: InMemorySettingsLocalDataDeleter(),
            versionProvider: versionProvider,
            licenseProvider: StaticSettingsLicenseProvider(),
            support: .placeholder,
            pasteboard: SystemSettingsPasteboard(),
            dateProvider: SystemDateProvider()
        )
    }()

    /// Production wiring for the app composition root.
    ///
    /// `profileStore` must be the WP-08 store: its `deleteAll()` is the single
    /// contract for clearing profiles, edit records, pair sessions, quota,
    /// thumbnails and backups. The coordinator additionally empties
    /// Application Support/StyleTone and the temporary directory, then verifies
    /// the result.
    ///
    /// Returns `nil` when the sandbox locations cannot be resolved; the host
    /// should not offer deletion in that state.
    public static func live(
        profileStore: any StyleProfileStore,
        locations: SettingsDataDeletionLocations? = nil,
        support: SettingsSupportInfo = .placeholder,
        pasteboard: any SettingsPasteboardWriting = SystemSettingsPasteboard(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) -> SettingsDependencies? {
        guard let resolved = locations ?? SettingsDataDeletionLocations.standard() else {
            return nil
        }

        let versionProvider = BundleSettingsVersionProvider()
        let diagnosticsPreferences = UserDefaultsSettingsDiagnosticsPreferences()
        let diagnosticsDirectory = resolved.appSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
        let diagnostics = SettingsDiagnosticsService(
            preferences: diagnosticsPreferences,
            store: FileSettingsDiagnosticsLogStore(directory: diagnosticsDirectory),
            versionProvider: versionProvider,
            dateProvider: dateProvider
        )
        let deleter = SettingsDataDeletionCoordinator(
            profileStore: profileStore,
            diagnostics: diagnostics,
            preferences: UserDefaultsSettingsLocalPreferences(),
            locations: resolved,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: dateProvider
        )

        return SettingsDependencies(
            diagnostics: diagnostics,
            dataDeleter: deleter,
            versionProvider: versionProvider,
            licenseProvider: StaticSettingsLicenseProvider(),
            support: support,
            pasteboard: pasteboard,
            dateProvider: dateProvider
        )
    }
}
