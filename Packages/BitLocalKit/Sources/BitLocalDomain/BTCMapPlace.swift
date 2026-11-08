import Foundation

/// A place from the BTC Map v4 API (`GET /v4/places`, `/v4/places/{id}`).
/// Mirrors the app's `V4PlaceRecord` field for field so either can feed `MerchantMapper`.
public struct BTCMapPlace: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var lat: Double?
    public var lon: Double?
    public var icon: String?
    public var name: String?
    public var address: String?
    public var openingHours: String?
    public var comments: Int?
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?
    public var verifiedAt: String?
    public var osmID: String?
    public var osmURL: String?
    public var phone: String?
    public var website: String?
    public var twitter: String?
    public var facebook: String?
    public var instagram: String?
    public var line: String?
    public var telegram: String?
    public var email: String?
    public var boostedUntil: String?
    public var requiredAppURL: String?
    public var description: String?
    public var image: String?
    public var paymentProvider: String?
    public var osmPaymentBitcoin: String?
    public var osmCurrencyXBT: String?
    public var osmPaymentOnchain: String?
    public var osmPaymentLightning: String?
    public var osmPaymentLightningContactless: String?
    public var osmAddrHouseNumber: String?
    public var osmAddrStreet: String?
    public var osmAddrCity: String?
    public var osmAddrState: String?
    public var osmAddrPostcode: String?
    public var osmOperator: String?
    public var osmBrand: String?
    public var osmBrandWikidata: String?

    public init(id: Int) { self.id = id }

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, icon, name, address
        case openingHours = "opening_hours"
        case comments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case verifiedAt = "verified_at"
        case osmID = "osm_id"
        case osmURL = "osm_url"
        case phone, website, twitter, facebook, instagram, line, telegram, email
        case boostedUntil = "boosted_until"
        case requiredAppURL = "required_app_url"
        case description, image
        case paymentProvider = "payment_provider"
        case osmPaymentBitcoin = "osm:payment:bitcoin"
        case osmCurrencyXBT = "osm:currency:XBT"
        case osmPaymentOnchain = "osm:payment:onchain"
        case osmPaymentLightning = "osm:payment:lightning"
        case osmPaymentLightningContactless = "osm:payment:lightning_contactless"
        case osmAddrHouseNumber = "osm:addr:housenumber"
        case osmAddrStreet = "osm:addr:street"
        case osmAddrCity = "osm:addr:city"
        case osmAddrState = "osm:addr:state"
        case osmAddrPostcode = "osm:addr:postcode"
        case osmOperator = "osm:operator"
        case osmBrand = "osm:brand"
        case osmBrandWikidata = "osm:brand:wikidata"
    }
}

/// A thin record from the CDN snapshot (`cdn.static.btcmap.org/api/v4/places.json`).
public struct BTCMapSnapshotPlace: Codable, Hashable, Sendable {
    public var id: Int
    public var lat: Double?
    public var lon: Double?
    public var icon: String?
    public var comments: Int?
    public var boostedUntil: String?
    public var name: String?
    public var displayName: String?

    public init(id: Int, lat: Double?, lon: Double?, icon: String? = nil, comments: Int? = nil,
                boostedUntil: String? = nil, name: String? = nil, displayName: String? = nil) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.icon = icon
        self.comments = comments
        self.boostedUntil = boostedUntil
        self.name = name
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, icon, comments
        case boostedUntil = "boosted_until"
        case name
        case displayName = "display_name"
    }
}

/// Parses the date formats BTC Map uses: ISO 8601 with or without fractional
/// seconds, and plain `yyyy-MM-dd`.
public enum BTCMapDate {
    public static func parse(_ raw: String?) -> Date? {
        guard let raw = raw.nonEmpty else { return nil }
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        if let date = try? Date(raw, strategy: Date.ISO8601FormatStyle().year().month().day()) {
            return date
        }
        return nil
    }
}
