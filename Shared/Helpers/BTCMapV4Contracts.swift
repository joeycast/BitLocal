import Foundation

enum BTCMapDataSourceMode: String, Codable {
    case auto
    case v2Legacy = "v2_legacy"
    case v4Preferred = "v4_preferred"
}

struct ElementV4Metadata: Codable, Hashable {
    let icon: String?
    let commentsCount: Int?
    let verifiedAt: String?
    let boostedUntil: String?
    let osmID: String?
    let osmURL: String?
    let email: String?
    let twitter: String?
    let facebook: String?
    let instagram: String?
    let telegram: String?
    let line: String?
    let requiredAppURL: String?
    let imageURL: String?
    let paymentProvider: String?
    let rawAddress: String?
}

struct V4PlaceSnapshotRecord: Codable, Hashable {
    let id: Int
    let lat: Double?
    let lon: Double?
    let icon: String?
    let comments: Int?
    let boostedUntil: String?

    enum CodingKeys: String, CodingKey {
        case id
        case lat
        case lon
        case icon
        case comments
        case boostedUntil = "boosted_until"
    }
}

struct V4PlaceRecord: Codable, Hashable, Identifiable {
    let id: Int
    let lat: Double?
    let lon: Double?
    let icon: String?
    let name: String?
    let address: String?
    let openingHours: String?
    let comments: Int?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let verifiedAt: String?
    let osmID: String?
    let osmURL: String?
    let phone: String?
    let website: String?
    let twitter: String?
    let facebook: String?
    let instagram: String?
    let line: String?
    let telegram: String?
    let email: String?
    let boostedUntil: String?
    let requiredAppURL: String?
    let description: String?
    let image: String?
    let paymentProvider: String?

    // Optional explicit OSM tag passthroughs requested via `fields=osm:<tag>`
    let osmPaymentBitcoin: String?
    let osmCurrencyXBT: String?
    let osmPaymentOnchain: String?
    let osmPaymentLightning: String?
    let osmPaymentLightningContactless: String?
    let osmAddrHouseNumber: String?
    let osmAddrStreet: String?
    let osmAddrCity: String?
    let osmAddrState: String?
    let osmAddrPostcode: String?
    let osmOperator: String?

    enum CodingKeys: String, CodingKey {
        case id
        case lat
        case lon
        case icon
        case name
        case address
        case openingHours = "opening_hours"
        case comments
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case verifiedAt = "verified_at"
        case osmID = "osm_id"
        case osmURL = "osm_url"
        case phone
        case website
        case twitter
        case facebook
        case instagram
        case line
        case telegram
        case email
        case boostedUntil = "boosted_until"
        case requiredAppURL = "required_app_url"
        case description
        case image
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
    }

    var idString: String { String(id) }
    var hasCoordinates: Bool { lat != nil && lon != nil }
    var displayName: String { name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : "BTC Map Place #\(id)" }
}

struct V4SyncState: Codable, Hashable {
    var snapshotLastModifiedRFC1123: String?
    var incrementalAnchorUpdatedSince: String?
    var lastSuccessfulSyncAt: String?
    var schemaVersion: Int

    static let currentSchemaVersion = 1

    static let empty = V4SyncState(
        snapshotLastModifiedRFC1123: nil,
        incrementalAnchorUpdatedSince: nil,
        lastSuccessfulSyncAt: nil,
        schemaVersion: currentSchemaVersion
    )
}

struct V4SearchQuery: Hashable {
    var name: String?
    var lat: Double?
    var lon: Double?
    var radiusKM: Double?
    var tagName: String?
    var tagValue: String?

    var isEmpty: Bool {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasName = trimmedName.count >= 3
        let hasRadius = lat != nil && lon != nil && (radiusKM ?? 0) > 0
        let hasTag = !(tagName?.isEmpty ?? true) && !(tagValue?.isEmpty ?? true)
        return !(hasName || hasRadius || hasTag)
    }

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.count >= 3 {
            items.append(URLQueryItem(name: "name", value: trimmedName))
        }

        if let lat, let lon, let radiusKM, radiusKM > 0 {
            items.append(URLQueryItem(name: "lat", value: String(lat)))
            items.append(URLQueryItem(name: "lon", value: String(lon)))
            items.append(URLQueryItem(name: "radius_km", value: String(radiusKM)))
        }

        if let tagName, !tagName.isEmpty, let tagValue, !tagValue.isEmpty {
            items.append(URLQueryItem(name: "tag_name", value: tagName))
            items.append(URLQueryItem(name: "tag_value", value: tagValue))
        }

        return items
    }
}

protocol BTCMapV4ClientProtocol {
    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void)
    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void)
}

protocol BTCMapSearchServiceProtocol {
    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void)
}

protocol BTCMapRepositoryProtocol: BTCMapSearchServiceProtocol {
    func loadCachedElements() -> [Element]?
    func hasCachedData() -> Bool
    func refreshElements(completion: @escaping ([Element]?) -> Void)
}

