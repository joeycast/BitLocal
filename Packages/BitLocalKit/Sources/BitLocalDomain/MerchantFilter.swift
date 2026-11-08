import Foundation

/// What the map and list show. Pins and list always use the same filter, so they agree.
public struct MerchantFilter: Hashable, Sendable {
    /// Only these categories (empty = all).
    public var categories: Set<MerchantCategory>
    /// Only merchants accepting at least one of these (empty = all).
    public var paymentMethods: PaymentMethods
    public var hideATMs: Bool

    public init(categories: Set<MerchantCategory> = [], paymentMethods: PaymentMethods = [], hideATMs: Bool = false) {
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.hideATMs = hideATMs
    }

    public static let all = MerchantFilter()

    public func matches(_ summary: MerchantSummary) -> Bool {
        if hideATMs && summary.category.isATM { return false }
        if !categories.isEmpty && !categories.contains(summary.category) { return false }
        if !paymentMethods.isEmpty && summary.paymentMethods.isDisjoint(with: paymentMethods) { return false }
        return true
    }
}
