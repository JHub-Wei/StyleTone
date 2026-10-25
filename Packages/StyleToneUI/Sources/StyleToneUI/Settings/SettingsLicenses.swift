import Foundation

/// One license entry shown on the Licenses page.
public struct SettingsLicense: Identifiable, Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable, Equatable {
        case application
        case systemFramework
    }

    public let id: String
    public let kind: Kind
    /// Product or framework name; not localized.
    public let name: String
    /// Optional version, when the component has one.
    public let version: String?
    /// Localized license summary.
    public let body: SettingsText

    public init(
        id: String,
        kind: Kind,
        name: String,
        version: String? = nil,
        body: SettingsText
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.version = version
        self.body = body
    }
}

/// The components bundled in this build.
///
/// The MVP has no third-party runtime dependencies (contracts section 1). If
/// that ever changes, the provider appends entries here and the page lists
/// them; the settings feature does not need a new screen.
public struct SettingsLicenseCatalog: Sendable, Equatable {
    public let application: [SettingsLicense]
    public let systemFrameworks: [SettingsLicense]
    public let thirdParty: [SettingsLicense]

    public init(
        application: [SettingsLicense],
        systemFrameworks: [SettingsLicense],
        thirdParty: [SettingsLicense] = []
    ) {
        self.application = application
        self.systemFrameworks = systemFrameworks
        self.thirdParty = thirdParty
    }

    public var hasThirdPartyComponents: Bool {
        !thirdParty.isEmpty
    }

    /// The shipped catalog: the app itself plus Apple system frameworks.
    public static let standard = SettingsLicenseCatalog(
        application: [
            SettingsLicense(
                id: "application.styletone",
                kind: .application,
                name: "StyleTone",
                body: SettingsCopy.licensesAppBody
            ),
        ],
        systemFrameworks: [
            SettingsLicense(
                id: "system.apple-sdk",
                kind: .systemFramework,
                name: "Apple system frameworks",
                body: SettingsCopy.licensesSystemBody
            ),
        ],
        thirdParty: []
    )
}

/// Supplies the license catalog to the settings screen.
public protocol SettingsLicenseProviding: Sendable {
    func catalog() -> SettingsLicenseCatalog
}

/// A provider with a fixed catalog, for the app and for previews/tests.
public struct StaticSettingsLicenseProvider: SettingsLicenseProviding {
    public let value: SettingsLicenseCatalog

    public init(_ value: SettingsLicenseCatalog = .standard) {
        self.value = value
    }

    public func catalog() -> SettingsLicenseCatalog {
        value
    }
}
