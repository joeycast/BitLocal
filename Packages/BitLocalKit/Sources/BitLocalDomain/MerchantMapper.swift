import Foundation

/// Maps BTC Map v4 records into domain merchants. The one place where
/// placeholder names, payment tags and addresses are interpreted.
public struct MerchantMapper: Sendable {
    /// Names a category for merchants without a usable name (e.g. "Coffee shop").
    public var categoryName: @Sendable (MerchantCategory) -> String

    public init(categoryName: @escaping @Sendable (MerchantCategory) -> String = { _ in "Place" }) {
        self.categoryName = categoryName
    }

    /// Snapshot names like "BTC Map Place #123" are stand-ins, not merchant names.
    public static func isPlaceholderName(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("BTC Map Place #")
    }

    /// The best real name from name, brand or operator, or nil.
    public static func realName(name: String?, brand: String?, operatorName: String?) -> String? {
        if let name = name.nonEmpty, !isPlaceholderName(name), name.lowercased() != "unnamed" {
            return name
        }
        return brand.nonEmpty ?? operatorName.nonEmpty
    }

    /// Full v4 place → merchant. Returns nil for deleted places and places without coordinates.
    public func merchant(from place: BTCMapPlace, now: Date = Date()) -> Merchant? {
        guard place.deletedAt.nonEmpty == nil,
              let lat = place.lat, let lon = place.lon else { return nil }
        let coordinate = Coordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else { return nil }

        let category = MerchantCategory(icon: place.icon)
        let realName = Self.realName(name: place.name, brand: place.osmBrand, operatorName: place.osmOperator)
        let updatedAt = BTCMapDate.parse(place.updatedAt) ?? BTCMapDate.parse(place.createdAt) ?? now

        let summary = MerchantSummary(
            id: MerchantID(place.id),
            coordinate: coordinate,
            name: realName ?? categoryName(category),
            hasRealName: realName != nil,
            category: category,
            paymentMethods: PaymentMethods(
                paymentBitcoin: place.osmPaymentBitcoin,
                currencyXBT: place.osmCurrencyXBT,
                paymentOnchain: place.osmPaymentOnchain,
                paymentLightning: place.osmPaymentLightning,
                paymentLightningContactless: place.osmPaymentLightningContactless,
                brand: place.osmBrand,
                brandWikidata: place.osmBrandWikidata
            ),
            boostedUntil: BTCMapDate.parse(place.boostedUntil),
            openingHours: place.openingHours.nonEmpty,
            updatedAt: updatedAt
        )

        let address = PostalAddress(
            houseNumber: place.osmAddrHouseNumber,
            street: place.osmAddrStreet,
            city: place.osmAddrCity,
            state: place.osmAddrState,
            postalCode: place.osmAddrPostcode,
            freeform: place.address
        )

        return Merchant(
            summary: summary,
            address: address.isEmpty ? nil : address,
            contact: Contact(
                phone: place.phone,
                website: Self.webURL(place.website),
                email: place.email
            ),
            socials: Self.socialLinks(from: place),
            about: place.description.nonEmpty,
            imageURL: Self.webURL(place.image),
            requiredAppURL: Self.webURL(place.requiredAppURL),
            verifiedAt: BTCMapDate.parse(place.verifiedAt),
            commentsCount: max(place.comments ?? 0, 0),
            osmURL: Self.webURL(place.osmURL),
            isHydrated: true
        )
    }

    /// Thin snapshot record → merchant with `isHydrated == false`.
    public func merchant(from snapshot: BTCMapSnapshotPlace, now: Date = Date()) -> Merchant? {
        guard let lat = snapshot.lat, let lon = snapshot.lon else { return nil }
        let coordinate = Coordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else { return nil }
        let category = MerchantCategory(icon: snapshot.icon)
        let realName = Self.realName(name: snapshot.name ?? snapshot.displayName, brand: nil, operatorName: nil)
        let summary = MerchantSummary(
            id: MerchantID(snapshot.id),
            coordinate: coordinate,
            name: realName ?? categoryName(category),
            hasRealName: realName != nil,
            category: category,
            paymentMethods: [],
            boostedUntil: BTCMapDate.parse(snapshot.boostedUntil),
            openingHours: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        return Merchant(summary: summary, commentsCount: max(snapshot.comments ?? 0, 0), isHydrated: false)
    }

    /// Accepts "example.com" as well as full URLs; only http(s) is allowed.
    public static func webURL(_ raw: String?) -> URL? {
        guard let raw = raw.nonEmpty else { return nil }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func socialLinks(from place: BTCMapPlace) -> [SocialLink] {
        let pairs: [(SocialLink.Network, String?, String)] = [
            (.twitter, place.twitter, "https://x.com/"),
            (.facebook, place.facebook, "https://facebook.com/"),
            (.instagram, place.instagram, "https://instagram.com/"),
            (.telegram, place.telegram, "https://t.me/"),
            (.line, place.line, "https://line.me/R/ti/p/"),
        ]
        return pairs.compactMap { network, raw, base in
            guard let value = raw.nonEmpty else { return nil }
            if value.contains("://") || (value.contains(".") && value.contains("/")) {
                return webURL(value).map { SocialLink(network: network, url: $0) }
            }
            let handle = value.hasPrefix("@") ? String(value.dropFirst()) : value
            return URL(string: base + handle).map { SocialLink(network: network, url: $0) }
        }
    }
}
