import Foundation
import StyleToneCore

extension PurchaseProduct {
    /// The single monthly product the MVP sells (contracts §3.6).
    public static let mockMonthly = PurchaseProduct(
        id: "com.styletone.pro.monthly",
        displayPrice: "¥29.9",
        period: "month"
    )
}

/// A `PurchaseServicing` double with deterministic state transitions and call
/// counters. Use it to cover active/expired/restore and failure paths without
/// StoreKit.
public actor MockPurchaser: PurchaseServicing {
    public enum FailurePoint: String, Sendable, CaseIterable {
        case none
        case product
        case purchase
        case restore
    }

    private var currentState: PurchaseState
    private let productValue: PurchaseProduct
    private let failurePoint: FailurePoint

    public private(set) var productCallCount = 0
    public private(set) var purchaseCallCount = 0
    public private(set) var restoreCallCount = 0

    public init(
        state: PurchaseState = .unknown,
        product: PurchaseProduct = .mockMonthly,
        failurePoint: FailurePoint = .none
    ) {
        self.currentState = state
        self.productValue = product
        self.failurePoint = failurePoint
    }

    public var state: PurchaseState { currentState }

    public func product() async throws -> PurchaseProduct {
        productCallCount += 1
        if failurePoint == .product {
            throw StyleToneError.purchaseFailed
        }
        return productValue
    }

    public func purchase() async throws -> PurchaseState {
        purchaseCallCount += 1
        if failurePoint == .purchase {
            throw StyleToneError.purchaseFailed
        }
        currentState = .active
        return currentState
    }

    public func restore() async throws -> PurchaseState {
        restoreCallCount += 1
        if failurePoint == .restore {
            throw StyleToneError.purchaseFailed
        }
        return currentState
    }
}

/// An in-memory `StyleProfileStore` double.
public actor MockStyleProfileStore: StyleProfileStore {
    public private(set) var storedProfile: StyleProfile?
    public private(set) var loadCount = 0
    public private(set) var saveCount = 0
    public private(set) var deleteCount = 0

    private let loadError: StyleToneError?
    private let saveError: StyleToneError?
    private let deleteError: StyleToneError?

    public init(
        profile: StyleProfile? = nil,
        loadError: StyleToneError? = nil,
        saveError: StyleToneError? = nil,
        deleteError: StyleToneError? = nil
    ) {
        self.storedProfile = profile
        self.loadError = loadError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    public func loadActive() async throws -> StyleProfile? {
        loadCount += 1
        if let loadError {
            throw loadError
        }
        return storedProfile
    }

    public func save(_ profile: StyleProfile) async throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        storedProfile = profile
    }

    public func deleteAll() async throws {
        deleteCount += 1
        if let deleteError {
            throw deleteError
        }
        storedProfile = nil
    }
}
