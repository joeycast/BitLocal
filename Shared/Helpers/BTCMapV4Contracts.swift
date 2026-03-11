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

enum BTCMapDateParser {
    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let fullISO = ISO8601DateFormatter.fullPrecision.date(from: raw) {
            return fullISO
        }
        if let basicISO = ISO8601DateFormatter.basic.date(from: raw) {
            return basicISO
        }
        return BTCMapDateParsers.dateOnly.date(from: raw)
    }
}

private extension ISO8601DateFormatter {
    static let fullPrecision: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum BTCMapDateParsers {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
    let osmAddrCountry: String?
    let osmAddrState: String?
    let osmAddrPostcode: String?
    let osmOperator: String?
    let osmBrand: String?
    let osmBrandWikidata: String?

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
        case osmAddrCountry = "osm:addr:country"
        case osmAddrState = "osm:addr:state"
        case osmAddrPostcode = "osm:addr:postcode"
        case osmOperator = "osm:operator"
        case osmBrand = "osm:brand"
        case osmBrandWikidata = "osm:brand:wikidata"
    }

    var idString: String { String(id) }
    var hasCoordinates: Bool { lat != nil && lon != nil }
    var preferredName: String? {
        let canonical = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return canonical.isEmpty ? nil : canonical
    }

    var displayName: String { preferredName ?? "BTC Map Place #\(id)" }
    var boostExpirationDate: Date? { BTCMapDateParser.parse(boostedUntil) }

    func isCurrentlyBoosted(referenceDate: Date = Date()) -> Bool {
        guard let boostExpirationDate else { return false }
        return boostExpirationDate > referenceDate
    }
}

struct V4SyncState: Codable, Hashable {
    var snapshotLastModifiedRFC1123: String?
    var incrementalAnchorUpdatedSince: String?
    var lastSuccessfulSyncAt: String?
    var bundledGeneratedAt: String?
    var bundledSourceAnchor: String?
    var schemaVersion: Int

    static let currentSchemaVersion = 5

    enum CodingKeys: String, CodingKey {
        case snapshotLastModifiedRFC1123
        case incrementalAnchorUpdatedSince
        case lastSuccessfulSyncAt
        case bundledGeneratedAt
        case bundledSourceAnchor
        case schemaVersion
    }

    init(
        snapshotLastModifiedRFC1123: String?,
        incrementalAnchorUpdatedSince: String?,
        lastSuccessfulSyncAt: String?,
        bundledGeneratedAt: String? = nil,
        bundledSourceAnchor: String? = nil,
        schemaVersion: Int
    ) {
        self.snapshotLastModifiedRFC1123 = snapshotLastModifiedRFC1123
        self.incrementalAnchorUpdatedSince = incrementalAnchorUpdatedSince
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.bundledGeneratedAt = bundledGeneratedAt
        self.bundledSourceAnchor = bundledSourceAnchor
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshotLastModifiedRFC1123 = try container.decodeIfPresent(String.self, forKey: .snapshotLastModifiedRFC1123)
        incrementalAnchorUpdatedSince = try container.decodeIfPresent(String.self, forKey: .incrementalAnchorUpdatedSince)
        lastSuccessfulSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSuccessfulSyncAt)
        bundledGeneratedAt = try container.decodeIfPresent(String.self, forKey: .bundledGeneratedAt)
        bundledSourceAnchor = try container.decodeIfPresent(String.self, forKey: .bundledSourceAnchor)
        // Older persisted sync-state files did not include schemaVersion.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    }

    static let empty = V4SyncState(
        snapshotLastModifiedRFC1123: nil,
        incrementalAnchorUpdatedSince: nil,
        lastSuccessfulSyncAt: nil,
        bundledGeneratedAt: nil,
        bundledSourceAnchor: nil,
        schemaVersion: 0
    )
}

struct V4PlaceCommentRecord: Codable, Hashable, Identifiable {
    let id: Int
    let placeID: Int?
    let createdAt: String?
    let updatedAt: String?
    let comment: String?
    let text: String?
    let message: String?
    let content: String?
    let name: String?
    let nickname: String?
    let displayName: String?
    let authorName: String?
    let senderName: String?
    let amountSats: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case comment
        case text
        case message
        case content
        case name
        case nickname
        case displayName = "display_name"
        case authorName = "author_name"
        case senderName = "sender_name"
        case amountSats = "amount_sats"
    }

    var bodyText: String {
        for value in [comment, text, message, content] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    var authorDisplayName: String? {
        for value in [displayName, authorName, senderName, nickname, name] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
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
        let hasName = !trimmedName.isEmpty
        let hasRadius = lat != nil && lon != nil && (radiusKM ?? 0) > 0
        let hasTag = !(tagName?.isEmpty ?? true) && !(tagValue?.isEmpty ?? true)
        return !(hasName || hasRadius || hasTag)
    }

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
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

struct V4EventsQuery: Hashable {
    var updatedSince: String?
    var includePast: Bool = false
    var limit: Int = 100

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "include_past", value: includePast ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let updatedSince, !updatedSince.isEmpty {
            items.append(URLQueryItem(name: "updated_since", value: updatedSince))
        }
        return items
    }
}

struct V4EventRecord: Codable, Hashable, Identifiable {
    let id: Int
    let lat: Double?
    let lon: Double?
    let name: String?
    let website: String?
    let startsAt: String?
    let endsAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case lat
        case lon
        case name
        case website
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "BTCMap Event #\(id)" : trimmed
    }
}

protocol BTCMapV4ClientProtocol {
    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void)
    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void)
    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void)
    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void)
}

protocol BTCMapSearchServiceProtocol {
    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void)
    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void)
    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void)
    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void)
}

protocol BTCMapRepositoryProtocol: BTCMapSearchServiceProtocol {
    func loadCachedElements() -> [Element]?
    func loadCachedElements(ids: [String]) -> [Element]
    func hasCachedData() -> Bool
    func refreshElements(completion: @escaping ([Element]?) -> Void)
    @discardableResult
    func upsertFetchedPlace(_ record: V4PlaceRecord) -> Element
    @discardableResult
    func persistMergedAddress(_ address: Address?, forMerchantID merchantID: String) -> Element?
    func processAddressEnrichmentJobs(limit: Int)
    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void)
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void)
    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void)
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void)
}
struct V3AreaBounds: Codable, Hashable {
    let minLon: Double?
    let minLat: Double?
    let maxLon: Double?
    let maxLat: Double?

    enum CodingKeys: String, CodingKey {
        case minLon = "min_lon"
        case minLat = "min_lat"
        case maxLon = "max_lon"
        case maxLat = "max_lat"
    }
}
// MARK: - GeoJSON Models

struct GeoJSONFeatureCollection: Codable, Hashable {
    let type: String
    let features: [GeoJSONFeature]

    private enum CodingKeys: String, CodingKey {
        case type
        case features
        case geometry
        case coordinates
    }

    init(type: String = "FeatureCollection", features: [GeoJSONFeature]) {
        self.type = type
        self.features = features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rootType = try container.decode(String.self, forKey: .type)

        switch rootType.lowercased() {
        case "featurecollection":
            let features = try container.decode([GeoJSONFeature].self, forKey: .features)
            self.init(type: "FeatureCollection", features: features)

        case "feature":
            let feature = try GeoJSONFeature(from: decoder)
            self.init(features: [feature])

        case "polygon", "multipolygon":
            let geometry = try GeoJSONGeometry(from: decoder)
            let feature = GeoJSONFeature(type: "Feature", geometry: geometry)
            self.init(features: [feature])

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported GeoJSON root type: \(rootType)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("FeatureCollection", forKey: .type)
        try container.encode(features, forKey: .features)
    }
}

struct GeoJSONFeature: Codable, Hashable {
    let type: String
    let geometry: GeoJSONGeometry
}

struct GeoJSONGeometry: Codable, Hashable {
    let type: String
    let coordinates: GeoJSONCoordinates
}

enum GeoJSONCoordinates: Codable, Hashable {
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let multi = try? container.decode([[[[Double]]]].self) {
            self = .multiPolygon(multi)
        } else if let poly = try? container.decode([[[Double]]].self) {
            self = .polygon(poly)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized GeoJSON coordinates format")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .polygon(let coords):
            try container.encode(coords)
        case .multiPolygon(let coords):
            try container.encode(coords)
        }
    }
}

// MARK: - V3AreaRecord

struct V3AreaRecord: Codable, Hashable, Identifiable {
    let id: Int
    let name: String?
    let urlAlias: String?
    let osmID: Int?
    let osmType: String?
    let tags: [String: String]?
    let bounds: V3AreaBounds?
    let updatedAt: String?
    let geoJSON: GeoJSONFeatureCollection?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlAlias = "url_alias"
        case osmID = "osm_id"
        case osmType = "osm_type"
        case tags
        case bounds
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        urlAlias = try container.decodeIfPresent(String.self, forKey: .urlAlias)
        osmID = try container.decodeIfPresent(Int.self, forKey: .osmID)
        osmType = try container.decodeIfPresent(String.self, forKey: .osmType)
        bounds = try container.decodeIfPresent(V3AreaBounds.self, forKey: .bounds)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        // Decode tags as mixed-type dictionary to extract geo_json
        if let rawTags = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .tags) {
            var stringTags: [String: String] = [:]
            var parsedGeoJSON: GeoJSONFeatureCollection?

            for (key, value) in rawTags {
                if key == "geo_json" {
                    // Re-encode the nested value and decode as GeoJSONFeatureCollection
                    if let data = try? JSONEncoder().encode(value),
                       let fc = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data) {
                        parsedGeoJSON = fc
                    }
                } else if case .string(let s) = value {
                    stringTags[key] = s
                }
            }

            tags = stringTags.isEmpty ? nil : stringTags
            geoJSON = parsedGeoJSON
        } else {
            tags = nil
            geoJSON = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(urlAlias, forKey: .urlAlias)
        try container.encodeIfPresent(osmID, forKey: .osmID)
        try container.encodeIfPresent(osmType, forKey: .osmType)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(bounds, forKey: .bounds)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let tagName = tags?["name"], !tagName.isEmpty { return tagName }
        return "Area #\(id)"
    }
}

// MARK: - AnyCodableValue (thin wrapper for mixed-type JSON)

enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let obj = try? container.decode([String: AnyCodableValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .object(let obj): try container.encode(obj)
        case .array(let arr): try container.encode(arr)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - V2AreaRecord (community map polygons)

struct V2AreaRecord: Codable, Hashable, Identifiable {
    let id: String
    let tags: [String: String]?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let geoJSON: GeoJSONFeatureCollection?

    enum CodingKeys: String, CodingKey {
        case id
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: String,
        tags: [String: String]?,
        createdAt: String?,
        updatedAt: String?,
        deletedAt: String?,
        geoJSON: GeoJSONFeatureCollection?
    ) {
        self.id = id
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.geoJSON = geoJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Unsupported v2 area id type")
        }

        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)

        if let rawTags = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .tags) {
            var stringTags: [String: String] = [:]
            var parsedGeoJSON: GeoJSONFeatureCollection?

            for (key, value) in rawTags {
                if key == "geo_json" {
                    if let data = try? JSONEncoder().encode(value),
                       let fc = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data) {
                        parsedGeoJSON = fc
                    }
                    continue
                }

                switch value {
                case .string(let s):
                    stringTags[key] = s
                case .bool(let b):
                    stringTags[key] = b ? "true" : "false"
                case .int(let i):
                    stringTags[key] = String(i)
                case .double(let d):
                    stringTags[key] = String(d)
                default:
                    continue
                }
            }

            tags = stringTags.isEmpty ? nil : stringTags
            geoJSON = parsedGeoJSON
        } else {
            tags = nil
            geoJSON = nil
        }
    }

    var displayName: String {
        if let name = tags?["name"], !name.isEmpty { return name }
        return "Area \(id)"
    }

    var isDeleted: Bool {
        !(deletedAt?.isEmpty ?? true)
    }

    var isCommunity: Bool {
        tags?["type"] == "community"
    }
}

struct V3AreaElementRecord: Codable, Hashable, Identifiable {
    let id: String
    let areaID: Int
    let elementID: String
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case areaID = "area_id"
        case elementID = "element_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeStringOrInt(forKey: .id, in: container, defaultValue: "")
        areaID = try Self.decodeIntOrString(forKey: .areaID, in: container, defaultValue: -1)
        elementID = try Self.decodeStringOrInt(forKey: .elementID, in: container, defaultValue: "")
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    private static func decodeStringOrInt(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        defaultValue: String
    ) throws -> String {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }
        if (try? container.decodeNil(forKey: key)) == true {
            return defaultValue
        }
        return defaultValue
    }

    private static func decodeIntOrString(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        defaultValue: Int
    ) throws -> Int {
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key),
           let intValue = Int(stringValue) {
            return intValue
        }
        if (try? container.decodeNil(forKey: key)) == true {
            return defaultValue
        }
        return defaultValue
    }
}
