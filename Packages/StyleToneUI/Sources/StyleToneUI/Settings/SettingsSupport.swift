import Foundation

/// Contact and legal destinations shown by Settings.
///
/// WP-28 supplies the final support address and privacy-policy URL. Keeping
/// them as values means the screen never hardcodes a domain or opens a network
/// request by itself; a `mailto:` link is built only when the address is valid.
public struct SettingsSupportInfo: Sendable, Equatable {
    public let email: String
    public let privacyPolicyURL: URL?
    public let responseTime: String

    public init(
        email: String,
        privacyPolicyURL: URL? = nil,
        responseTime: String = SettingsCopy.supportResponse.text
    ) {
        self.email = email
        self.privacyPolicyURL = privacyPolicyURL
        self.responseTime = responseTime
    }

    /// Development contact address. WP-28 replaces it with the approved inbox.
    public static let placeholder = SettingsSupportInfo(email: "support@styletone.app")

    /// Whether the address is a single, plain email address.
    public var hasValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == email, !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !trimmed.contains("..")
    }

    /// A `mailto:` URL with a fixed subject, or `nil` for an invalid address.
    ///
    /// No scheme other than `mailto` is produced here, so the settings feature
    /// cannot silently open a web request.
    public var mailtoURL: URL? {
        guard hasValidEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "StyleTone support")]
        return components.url
    }

    /// The legal policy destination, when WP-28 has configured one.
    public var hasPrivacyPolicy: Bool {
        privacyPolicyURL != nil
    }
}
