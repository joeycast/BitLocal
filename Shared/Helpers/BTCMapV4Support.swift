import Foundation

enum BTCMapV4Error: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid BTCMap v4 URL"
        case .invalidResponse: return "Invalid BTCMap v4 response"
        case .httpStatus(let code, let message): return "BTCMap v4 HTTP \(code): \(message ?? "Unknown error")"
        case .emptyQuery: return "Search query is empty"
        }
    }
}

final class BTCMapV4Client: BTCMapV4ClientProtocol {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v4")!
    private let snapshotURL = URL(string: "https://cdn.static.btcmap.org/api/v4/places.json")!
    private let decoder = JSONDecoder()
    private let pageLimit = 5000

    // Includes a subset of v4 + explicit OSM tags needed for current UI parity
    private let syncFields = [
        "id", "lat", "lon", "icon", "name", "address",
        "opening_hours", "comments", "created_at", "updated_at", "deleted_at",
        "verified_at", "osm_id", "osm_url", "phone", "website", "email",
        "twitter", "facebook", "instagram", "telegram", "line",
        "boosted_until", "required_app_url", "description", "image", "payment_provider",
        "osm:payment:bitcoin", "osm:currency:XBT", "osm:payment:onchain",
        "osm:payment:lightning", "osm:payment:lightning_contactless",
        "osm:addr:housenumber", "osm:addr:street", "osm:addr:city",
        "osm:addr:state", "osm:addr:postcode", "osm:operator"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        let request = URLRequest(url: snapshotURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV4Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV4Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let records = try self.decoder.decode([V4PlaceSnapshotRecord].self, from: data)
                let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                completion(.success((records, lastModified)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("places"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: syncFields.joined(separator: ",")),
            URLQueryItem(name: "updated_since", value: updatedSince),
            URLQueryItem(name: "include_deleted", value: includeDeleted ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(pageLimit))
        ]
        performRequest(url: components.url, completion: completion)
    }

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        guard !query.isEmpty else {
            completion(.failure(BTCMapV4Error.emptyQuery))
            return
        }
        guard var components = URLComponents(url: baseURL.appendingPathComponent("places/search/"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        var items = query.queryItems()
        items.append(URLQueryItem(name: "fields", value: syncFields.joined(separator: ",")))
        components.queryItems = items
        performRequest(url: components.url, completion: completion)
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(url: baseURL.appendingPathComponent("places/\(encodedID)"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: syncFields.joined(separator: ","))
        ]
        let url = components.url
        session.dataTask(with: url!) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV4Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV4Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let record = try self.decoder.decode(V4PlaceRecord.self, from: data)
                completion(.success(record))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        guard let encodedID = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.btcmap.org/v4/places/\(encodedID)/comments") else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV4Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV4Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let records = try self.decoder.decode([V4PlaceCommentRecord].self, from: data)
                completion(.success(records))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func performRequest(url: URL?, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        guard let url else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV4Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV4Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let records = try self.decoder.decode([V4PlaceRecord].self, from: data)
                completion(.success(records))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

struct BTCMapV2Client {
    private let apiManager = APIManager.shared

    func loadCachedElements() -> [Element]? {
        apiManager.loadElementsFromFile()
    }

    func refreshElements(completion: @escaping ([Element]?) -> Void) {
        let existing = apiManager.loadElementsFromFile() ?? []
        apiManager.getElements { updates in
            let merged = BTCMapRepository.mergeElements(existing: existing, incoming: updates ?? [])
            completion(merged.isEmpty ? (updates ?? existing) : merged)
        }
    }

    func hasCachedData() -> Bool {
        apiManager.hasCachedData()
    }
}

struct V4PlaceToElementMapper {
    static func snapshotRecordToElement(_ record: V4PlaceSnapshotRecord, fallbackTimestamp: String) -> Element {
        let placeholderName = "BTC Map Place #\(record.id)"
        let osmTags = makeOsmTags(
            name: placeholderName,
            operatorName: nil,
            description: nil,
            website: nil,
            phone: nil,
            openingHours: nil,
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            addrHousenumber: nil,
            addrStreet: nil,
            addrCity: nil,
            addrState: nil,
            addrPostcode: nil
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: record.lat,
            lon: record.lon,
            tags: osmTags,
            timestamp: fallbackTimestamp,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )
        return Element(
            id: String(record.id),
            osmJSON: osmJSON,
            tags: Tags(
                category: nil,
                iconAndroid: record.icon,
                paymentCoinos: nil,
                paymentPouch: nil,
                boostExpires: record.boostedUntil,
                categoryPlural: nil,
                paymentProvider: nil,
                paymentURI: nil
            ),
            createdAt: fallbackTimestamp,
            updatedAt: fallbackTimestamp,
            deletedAt: nil,
            address: nil,
            v4Metadata: ElementV4Metadata(
                icon: record.icon,
                commentsCount: record.comments,
                verifiedAt: nil,
                boostedUntil: record.boostedUntil,
                osmID: nil,
                osmURL: nil,
                email: nil,
                twitter: nil,
                facebook: nil,
                instagram: nil,
                telegram: nil,
                line: nil,
                requiredAppURL: nil,
                imageURL: nil,
                paymentProvider: nil,
                rawAddress: nil
            )
        )
    }

    static func placeRecordToElement(_ record: V4PlaceRecord) -> Element {
        let createdAt = record.createdAt ?? record.updatedAt ?? BTCMapRepository.epochISO8601
        let updatedAt = record.updatedAt ?? createdAt
        let osmTags = makeOsmTags(
            name: record.name ?? "BTC Map Place #\(record.id)",
            operatorName: record.osmOperator,
            description: record.description,
            website: record.website,
            phone: record.phone,
            openingHours: record.openingHours,
            paymentBitcoin: record.osmPaymentBitcoin,
            currencyXBT: record.osmCurrencyXBT,
            paymentOnchain: record.osmPaymentOnchain,
            paymentLightning: record.osmPaymentLightning,
            paymentLightningContactless: record.osmPaymentLightningContactless,
            addrHousenumber: record.osmAddrHouseNumber,
            addrStreet: record.osmAddrStreet ?? record.address,
            addrCity: record.osmAddrCity,
            addrState: record.osmAddrState,
            addrPostcode: record.osmAddrPostcode
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: record.lat,
            lon: record.lon,
            tags: osmTags,
            timestamp: updatedAt,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )

        let address: Address?
        if record.osmAddrStreet != nil || record.osmAddrCity != nil || record.osmAddrState != nil || record.osmAddrPostcode != nil {
            address = Address(
                streetNumber: record.osmAddrHouseNumber,
                streetName: record.osmAddrStreet,
                cityOrTownName: record.osmAddrCity,
                postalCode: Address.normalizedPostalCode(record.osmAddrPostcode, countryName: nil),
                regionOrStateName: record.osmAddrState,
                countryName: nil
            )
        } else if let raw = record.address, !raw.isEmpty {
            address = Address(
                streetNumber: nil,
                streetName: raw,
                cityOrTownName: nil,
                postalCode: nil,
                regionOrStateName: nil,
                countryName: nil
            )
        } else {
            address = nil
        }

        let tags = Tags(
            category: nil,
            iconAndroid: record.icon,
            paymentCoinos: nil,
            paymentPouch: nil,
            boostExpires: record.boostedUntil,
            categoryPlural: nil,
            paymentProvider: record.paymentProvider,
            paymentURI: nil
        )

        let metadata = ElementV4Metadata(
            icon: record.icon,
            commentsCount: record.comments,
            verifiedAt: record.verifiedAt,
            boostedUntil: record.boostedUntil,
            osmID: record.osmID,
            osmURL: record.osmURL,
            email: record.email,
            twitter: record.twitter,
            facebook: record.facebook,
            instagram: record.instagram,
            telegram: record.telegram,
            line: record.line,
            requiredAppURL: record.requiredAppURL,
            imageURL: record.image,
            paymentProvider: record.paymentProvider,
            rawAddress: record.address
        )

        return Element(
            id: String(record.id),
            osmJSON: osmJSON,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: record.deletedAt,
            address: address,
            v4Metadata: metadata
        )
    }

    private static func makeOsmTags(
        name: String?,
        operatorName: String?,
        description: String?,
        website: String?,
        phone: String?,
        openingHours: String?,
        paymentBitcoin: String?,
        currencyXBT: String?,
        paymentOnchain: String?,
        paymentLightning: String?,
        paymentLightningContactless: String?,
        addrHousenumber: String?,
        addrStreet: String?,
        addrCity: String?,
        addrState: String?,
        addrPostcode: String?
    ) -> OsmTags {
        OsmTags(
            addrCity: addrCity,
            addrHousenumber: addrHousenumber,
            addrPostcode: addrPostcode,
            addrState: addrState,
            addrStreet: addrStreet,
            paymentBitcoin: paymentBitcoin,
            currencyXBT: currencyXBT,
            paymentOnchain: paymentOnchain,
            paymentLightning: paymentLightning,
            paymentLightningContactless: paymentLightningContactless,
            name: name,
            operator: operatorName,
            description: description,
            descriptionEn: nil,
            website: website,
            contactWebsite: nil,
            phone: phone,
            contactPhone: nil,
            openingHours: openingHours,
            cuisine: nil,
            shop: nil,
            sport: nil,
            tourism: nil,
            healthcare: nil,
            craft: nil,
            amenity: nil,
            place: nil,
            leisure: nil,
            office: nil,
            building: nil,
            company: nil
        )
    }
}

final class BTCMapRepository: BTCMapRepositoryProtocol {
    static let shared = BTCMapRepository()
    static let epochISO8601 = "1970-01-01T00:00:00Z"

    private let v2Client = BTCMapV2Client()
    private let v4Client: BTCMapV4ClientProtocol
    private let userDefaults: UserDefaults
    private let modeKey = "btcmap_data_source_mode"

    init(v4Client: BTCMapV4ClientProtocol = BTCMapV4Client(), userDefaults: UserDefaults = .standard) {
        self.v4Client = v4Client
        self.userDefaults = userDefaults
    }

    private var v4ElementsFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("btcmap_elements_v4.json")
    }

    private var v4SyncStateFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("btcmap_v4_sync_state.json")
    }

    func loadCachedElements() -> [Element]? {
        switch dataSourceMode {
        case .v2Legacy:
            return v2Client.loadCachedElements()
        case .v4Preferred:
            return loadV4Elements()
        case .auto:
            return loadV4Elements() ?? v2Client.loadCachedElements()
        }
    }

    func hasCachedData() -> Bool {
        switch dataSourceMode {
        case .v2Legacy:
            return v2Client.hasCachedData()
        case .v4Preferred:
            return hasV4CachedData()
        case .auto:
            return hasV4CachedData() || v2Client.hasCachedData()
        }
    }

    func refreshElements(completion: @escaping ([Element]?) -> Void) {
        switch dataSourceMode {
        case .v2Legacy:
            Debug.logAPI("BTCMapRepository: using v2 legacy mode")
            v2Client.refreshElements(completion: completion)
        case .v4Preferred:
            Debug.logAPI("BTCMapRepository: using v4 preferred mode")
            refreshV4(allowV2Fallback: false, completion: completion)
        case .auto:
            Debug.logAPI("BTCMapRepository: using auto mode (v4 preferred, v2 fallback)")
            refreshV4(allowV2Fallback: true, completion: completion)
        }
    }

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        v4Client.searchPlaces(query: query, completion: completion)
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        v4Client.fetchPlace(id: id, completion: completion)
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        v4Client.fetchPlaceComments(placeID: placeID, completion: completion)
    }

    private var dataSourceMode: BTCMapDataSourceMode {
        guard let raw = userDefaults.string(forKey: modeKey),
              let mode = BTCMapDataSourceMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    private func refreshV4(allowV2Fallback: Bool, completion: @escaping ([Element]?) -> Void) {
        let hadV4Cache = hasV4CachedData()
        let startIncremental: () -> Void = { [weak self] in
            self?.performV4IncrementalSync(completion: { result in
                switch result {
                case .success(let elements):
                    completion(elements)
                case .failure(let error):
                    Debug.logAPI("BTCMap v4 incremental sync failed: \(error.localizedDescription)")
                    if allowV2Fallback && !hadV4Cache {
                        self?.v2Client.refreshElements(completion: completion)
                    } else {
                        completion(self?.loadV4Elements() ?? self?.v2Client.loadCachedElements())
                    }
                }
            })
        }

        if !hadV4Cache {
            Debug.logAPI("BTCMapRepository: no v4 cache, bootstrapping snapshot")
            v4Client.fetchSnapshot { [weak self] result in
                guard let self else {
                    completion(nil)
                    return
                }
                switch result {
                case .success(let payload):
                    let fallbackTimestamp = Self.rfc1123ToISO8601(payload.lastModified) ?? Self.currentISO8601()
                    let mapped = payload.records.map { V4PlaceToElementMapper.snapshotRecordToElement($0, fallbackTimestamp: fallbackTimestamp) }
                    self.saveV4Elements(mapped)
                    var syncState = self.loadV4SyncState()
                    syncState.snapshotLastModifiedRFC1123 = payload.lastModified
                    syncState.incrementalAnchorUpdatedSince = syncState.incrementalAnchorUpdatedSince ?? fallbackTimestamp
                    self.saveV4SyncState(syncState)
                    startIncremental()
                case .failure(let error):
                    Debug.logAPI("BTCMap v4 snapshot bootstrap failed: \(error.localizedDescription)")
                    if allowV2Fallback {
                        self.v2Client.refreshElements(completion: completion)
                    } else {
                        completion(nil)
                    }
                }
            }
            return
        }

        startIncremental()
    }

    private func performV4IncrementalSync(completion: @escaping (Result<[Element], Error>) -> Void) {
        let existing = loadV4Elements() ?? []
        var syncState = loadV4SyncState()
        var anchor = syncState.incrementalAnchorUpdatedSince ?? Self.epochISO8601
        var merged = existing
        var pageCount = 0
        let maxPages = 20

        func step() {
            pageCount += 1
            v4Client.fetchPlaces(updatedSince: anchor, includeDeleted: true) { [weak self] result in
                guard let self else {
                    completion(.success(merged))
                    return
                }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let records):
                    if records.isEmpty {
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4Elements(merged)
                        self.saveV4SyncState(syncState)
                        completion(.success(merged))
                        return
                    }

                    let incoming = records.map(V4PlaceToElementMapper.placeRecordToElement)
                    merged = Self.mergeElements(existing: merged, incoming: incoming)

                    if let maxUpdated = records.compactMap({ $0.updatedAt }).max(),
                       self.parseFlexibleDate(maxUpdated) != nil {
                        anchor = maxUpdated
                        syncState.incrementalAnchorUpdatedSince = maxUpdated
                    }

                    self.saveV4Elements(merged)
                    self.saveV4SyncState(syncState)

                    if records.count >= 5000 && pageCount < maxPages {
                        step()
                    } else {
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4SyncState(syncState)
                        completion(.success(merged))
                    }
                }
            }
        }

        step()
    }

    private func loadV4Elements() -> [Element]? {
        do {
            let data = try Data(contentsOf: v4ElementsFileURL)
            let elements = try JSONDecoder().decode([Element].self, from: data)
            return elements.isEmpty ? nil : elements
        } catch {
            return nil
        }
    }

    private func saveV4Elements(_ elements: [Element]) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(elements)
                try data.write(to: self.v4ElementsFileURL, options: .atomic)
                Debug.logCache("Saved \(elements.count) v4 elements to \(self.v4ElementsFileURL.lastPathComponent)")
            } catch {
                Debug.logCache("Failed to save v4 elements: \(error.localizedDescription)")
            }
        }
    }

    private func hasV4CachedData() -> Bool {
        guard FileManager.default.fileExists(atPath: v4ElementsFileURL.path) else { return false }
        return (loadV4Elements()?.isEmpty == false)
    }

    private func loadV4SyncState() -> V4SyncState {
        do {
            let data = try Data(contentsOf: v4SyncStateFileURL)
            return try JSONDecoder().decode(V4SyncState.self, from: data)
        } catch {
            return .empty
        }
    }

    private func saveV4SyncState(_ state: V4SyncState) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: self.v4SyncStateFileURL, options: .atomic)
            } catch {
                Debug.logCache("Failed to save v4 sync state: \(error.localizedDescription)")
            }
        }
    }

    fileprivate static func mergeElements(existing: [Element], incoming: [Element]) -> [Element] {
        var dictionary = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for element in incoming {
            let isDeleted = !(element.deletedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if isDeleted {
                dictionary.removeValue(forKey: element.id)
                continue
            }

            if let current = dictionary[element.id] {
                if isIncomingNewer(element, than: current) {
                    dictionary[element.id] = element
                }
            } else {
                dictionary[element.id] = element
            }
        }
        return Array(dictionary.values)
    }

    private static func isIncomingNewer(_ incoming: Element, than current: Element) -> Bool {
        switch (incoming.updatedAt, current.updatedAt) {
        case let (.some(incomingValue), .some(currentValue)):
            guard let incomingDate = parseStaticFlexibleDate(incomingValue),
                  let currentDate = parseStaticFlexibleDate(currentValue) else {
                return incomingValue >= currentValue
            }
            return incomingDate >= currentDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return true
        }
    }

    private func parseFlexibleDate(_ value: String) -> Date? {
        Self.parseStaticFlexibleDate(value)
    }

    private static func parseStaticFlexibleDate(_ value: String) -> Date? {
        if let full = iso8601WithFractional.date(from: value) ?? iso8601Basic.date(from: value) {
            return full
        }
        return dateOnly.date(from: value)
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let rfc1123Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()

    private static func rfc1123ToISO8601(_ header: String?) -> String? {
        guard let header, let date = rfc1123Formatter.date(from: header) else { return nil }
        return iso8601Basic.string(from: date)
    }

    private static func currentISO8601() -> String {
        iso8601Basic.string(from: Date())
    }
}
