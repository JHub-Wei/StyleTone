import Foundation
import StyleToneCore

/// The user's export entitlement.
///
/// WP-20 owns the persistent free-export count and the subscription state. The
/// export flow reads entitlement before starting and records a successful
/// save/share after the system confirms delivery. Failures and cancellations
/// never call `recordSuccessfulExport`.
public enum ExportEntitlement: Sendable, Equatable {
    case free(remaining: Int)
    case unlimited
    case exhausted

    public var canExport: Bool {
        switch self {
        case let .free(remaining): return remaining > 0
        case .unlimited: return true
        case .exhausted: return false
        }
    }

    public var isUnlimited: Bool {
        if case .unlimited = self { return true }
        return false
    }

    public var isExhausted: Bool {
        !canExport
    }

    /// Remaining free exports, or `nil` when unlimited.
    public var remainingFreeExports: Int? {
        if case let .free(remaining) = self {
            return max(0, remaining)
        }
        return nil
    }

    /// Normalizes non-positive free counts to `.exhausted`.
    public static func freeExports(_ remaining: Int) -> ExportEntitlement {
        remaining > 0 ? .free(remaining: remaining) : .exhausted
    }
}

/// Entitlement and success hook owned by WP-20.
///
/// Implementations live in the composition root (App target) or in
/// `StyleToneCommerce`; `StyleToneUI` must not import StoreKit. The default
/// implementation fails closed (`UnavailableExportQuota`) so a build without
/// the paywall cannot silently grant unlimited exports.
public protocol ExportQuotaServicing: Sendable {
    /// Current entitlement.
    ///
    /// Read on `start()`, when the app returns to the foreground, on the quota
    /// retry action, and after a purchase when the host calls
    /// `ExportViewModel.refreshEntitlement()`. Each export attempt uses the
    /// cached value; it does not round-trip on every button tap.
    func entitlement() async throws -> ExportEntitlement

    /// Records one successfully delivered export.
    ///
    /// Called after a photo-library save succeeds or after the share sheet
    /// reports completion. It must not be called on failure or cancellation.
    func recordSuccessfulExport() async throws
}

/// Grants unlimited exports; use only for previews/tests or an intentional
/// ungated build. The production composition root must inject WP-20.
public struct UnlimitedExportQuota: ExportQuotaServicing, Sendable {
    public init() {}

    public func entitlement() async throws -> ExportEntitlement {
        .unlimited
    }

    public func recordSuccessfulExport() async throws {}
}

/// Fail-closed placeholder used until WP-20 is wired.
///
/// `entitlement()` throws, so the export screen shows "Couldn't check your
/// exports" and keeps Save/Share disabled. This is deliberately not
/// `UnlimitedExportQuota`: shipping the placeholder must not bypass the
/// paywall by accident.
public struct UnavailableExportQuota: ExportQuotaServicing, Sendable {
    public init() {}

    public func entitlement() async throws -> ExportEntitlement {
        throw StyleToneError.persistenceFailed
    }

    public func recordSuccessfulExport() async throws {
        throw StyleToneError.persistenceFailed
    }
}
