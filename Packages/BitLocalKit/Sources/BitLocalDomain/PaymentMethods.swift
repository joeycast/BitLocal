import Foundation

/// How a merchant accepts bitcoin. Parsed once at ingest from OSM payment tags.
public struct PaymentMethods: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `payment:onchain=yes`.
    public static let onchain = PaymentMethods(rawValue: 1 << 0)
    /// `payment:lightning=yes`.
    public static let lightning = PaymentMethods(rawValue: 1 << 1)
    /// `payment:lightning_contactless=yes` (tap to pay).
    public static let lightningContactless = PaymentMethods(rawValue: 1 << 2)
    /// `payment:bitcoin=yes` / `currency:XBT=yes` with no specific method tagged.
    public static let bitcoinUnspecified = PaymentMethods(rawValue: 1 << 3)

    /// Brands known to accept Lightning only, used when no payment tags are present.
    static let lightningOnlyBrandWikidataIDs: Set<String> = ["q7605233"] // Steak 'n Shake
    static let lightningOnlyBrandNames: Set<String> = ["steak 'n shake", "steak n shake"]

    /// Parses OSM-style payment tags. Values are compared case-insensitively to "yes".
    public init(
        paymentBitcoin: String? = nil,
        currencyXBT: String? = nil,
        paymentOnchain: String? = nil,
        paymentLightning: String? = nil,
        paymentLightningContactless: String? = nil,
        brand: String? = nil,
        brandWikidata: String? = nil
    ) {
        func yes(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yes"
        }
        func present(_ value: String?) -> Bool {
            !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        var methods: PaymentMethods = []
        if yes(paymentOnchain) { methods.insert(.onchain) }
        if yes(paymentLightning) { methods.insert(.lightning) }
        if yes(paymentLightningContactless) { methods.insert(.lightningContactless) }

        let hasSpecificTags = present(paymentOnchain) || present(paymentLightning) || present(paymentLightningContactless)
        if !hasSpecificTags && (yes(paymentBitcoin) || yes(currencyXBT)) {
            methods.insert(.bitcoinUnspecified)
        }

        let hasAnyPaymentTag = hasSpecificTags || present(paymentBitcoin) || present(currencyXBT)
        if !hasAnyPaymentTag {
            let wikidata = brandWikidata?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let brandName = brand?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if Self.lightningOnlyBrandWikidataIDs.contains(wikidata) || Self.lightningOnlyBrandNames.contains(brandName) {
                methods.insert(.lightning)
            }
        }
        self = methods
    }
}
