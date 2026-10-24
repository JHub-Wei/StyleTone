import Foundation

public enum PurchaseState: String, Sendable, Codable, CaseIterable {
    case unknown
    case active
    case expired
}

public struct PurchaseProduct: Sendable, Equatable {
    public let id: String
    public let displayPrice: String
    public let period: String

    public init(id: String, displayPrice: String, period: String) {
        self.id = id
        self.displayPrice = displayPrice
        self.period = period
    }
}
