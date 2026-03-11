import CoreLocation
import Foundation

enum BTCMapV4Error: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyQuery
    case invalidBody

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid BTCMap v4 URL"
        case .invalidResponse: return "Invalid BTCMap v4 response"
        case .httpStatus(let code, let message): return "BTCMap v4 HTTP \(code): \(message ?? "Unknown error")"
        case .emptyQuery: return "Search query is empty"
        case .invalidBody: return "Invalid request body"
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
        "id", "lat", "lon", "icon", "name", "display_name", "address",
        "opening_hours", "comments", "created_at", "updated_at", "deleted_at",
        "verified_at", "osm_id", "osm_url", "phone", "website", "email",
        "twitter", "facebook", "instagram", "telegram", "line",
        "boosted_until", "required_app_url", "description", "image", "payment_provider",
        "osm:payment:bitcoin", "osm:currency:XBT", "osm:payment:onchain",
        "osm:payment:lightning", "osm:payment:lightning_contactless",
        "osm:addr:housenumber", "osm:addr:street", "osm:addr:city",
        "osm:addr:country", "osm:addr:state", "osm:addr:postcode",
        "osm:operator", "osm:brand", "osm:brand:wikidata"
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

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        components.queryItems = query.queryItems()
        performRequest(url: components.url, completion: completion)
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

    private func performRequest(url: URL?, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
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
                let records = try self.decoder.decode([V4EventRecord].self, from: data)
                completion(.success(records))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func performJSONRequest<T: Decodable>(path: String, body: [String: Any], completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: "https://api.btcmap.org/v4/\(path)") else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(BTCMapV4Error.invalidBody))
            return
        }

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
                completion(.success(try self.decoder.decode(T.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func performGETJSONRequest<T: Decodable>(path: String, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: "https://api.btcmap.org/v4/\(path)") else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
                completion(.success(try self.decoder.decode(T.self, from: data)))
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

enum BTCMapV3Error: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid BTCMap v3 URL"
        case .invalidResponse: return "Invalid BTCMap v3 response"
        case .httpStatus(let code, let message): return "BTCMap v3 HTTP \(code): \(message ?? "Unknown error")"
        }
    }
}

final class BTCMapV3AreasClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v3")!
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAreas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("areas"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "updated_since", value: updatedSince),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        performRequest(url: components.url, completion: completion)
    }

    func fetchArea(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("areas").appendingPathComponent(String(id))
        performSingleRequest(url: url, completion: completion)
    }

    func fetchAreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) {
        let pageLimit = max(1, limit)
        let maxPages = 50
        var cursor = updatedSince
        var page = 0
        var collected: [V3AreaElementRecord] = []

        func step() {
            guard var components = URLComponents(url: baseURL.appendingPathComponent("area-elements"), resolvingAgainstBaseURL: false) else {
                completion(.failure(BTCMapV3Error.invalidURL))
                return
            }
            components.queryItems = [
                URLQueryItem(name: "area_id", value: String(areaID)),
                URLQueryItem(name: "updated_since", value: cursor),
                URLQueryItem(name: "limit", value: String(pageLimit))
            ]
            guard let url = components.url else {
                completion(.failure(BTCMapV3Error.invalidURL))
                return
            }

            session.dataTask(with: url) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let data, let http = response as? HTTPURLResponse else {
                    completion(.failure(BTCMapV3Error.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let message = String(data: data.prefix(500), encoding: .utf8)
                    completion(.failure(BTCMapV3Error.httpStatus(http.statusCode, message)))
                    return
                }
                do {
                    let decoded = try self.decoder.decode([V3AreaElementRecord].self, from: data)
                    let filtered = decoded.filter { $0.areaID == areaID }
                    if !filtered.isEmpty {
                        collected.append(contentsOf: filtered)
                    }

                    page += 1
                    let nextCursor = decoded.last?.updatedAt
                    let canContinue = decoded.count == pageLimit
                        && page < maxPages
                        && nextCursor != nil
                        && nextCursor != cursor

                    guard canContinue, let nextCursor else {
                        completion(.success(collected))
                        return
                    }
                    cursor = nextCursor
                    step()
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }

        step()
    }

    private func performRequest<T: Decodable>(url: URL?, completion: @escaping (Result<[T], Error>) -> Void) {
        guard let url else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV3Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV3Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let decoded = try self.decoder.decode([T].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func performSingleRequest<T: Decodable>(url: URL?, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV3Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV3Error.httpStatus(http.statusCode, message)))
                return
            }
            if let object = try? self.decoder.decode(T.self, from: data) {
                completion(.success(object))
                return
            }
            if let array = try? self.decoder.decode([T].self, from: data), let first = array.first {
                completion(.success(first))
                return
            }
            completion(.failure(BTCMapV3Error.invalidResponse))
        }.resume()
    }
}

final class BTCMapV2AreasClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v2")!
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAreas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("areas"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "updated_since", value: updatedSince),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                completion(.failure(BTCMapV3Error.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data.prefix(500), encoding: .utf8)
                completion(.failure(BTCMapV3Error.httpStatus(http.statusCode, message)))
                return
            }
            do {
                let decoded = try self.decoder.decode([V2AreaRecord].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

struct V4PlaceToElementMapper {
    static func snapshotRecordToElement(_ record: V4PlaceSnapshotRecord, fallbackTimestamp: String) -> Element {
        let placeholderName = "BTC Map Place #\(record.id)"
        let osmTags = makeOsmTags(
            name: placeholderName,
            operatorName: nil,
            brandName: nil,
            brandWikidata: nil,
            categoryIcon: record.icon,
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
            addrCountry: nil,
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
            name: record.preferredName ?? "BTC Map Place #\(record.id)",
            operatorName: record.osmOperator,
            brandName: record.osmBrand,
            brandWikidata: record.osmBrandWikidata,
            categoryIcon: record.icon,
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
            addrStreet: record.osmAddrStreet,
            addrCity: record.osmAddrCity,
            addrCountry: record.osmAddrCountry,
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
        let country = Address.countryComponents(from: record.osmAddrCountry)
        if record.osmAddrHouseNumber != nil ||
            record.osmAddrStreet != nil ||
            record.osmAddrCity != nil ||
            record.osmAddrState != nil ||
            record.osmAddrPostcode != nil ||
            country.countryName != nil ||
            country.countryCode != nil {
            address = Address(
                streetNumber: record.osmAddrHouseNumber,
                streetName: record.osmAddrStreet,
                cityOrTownName: record.osmAddrCity,
                postalCode: Address.normalizedPostalCode(
                    record.osmAddrPostcode,
                    countryName: country.countryName,
                    countryCode: country.countryCode,
                    regionOrStateName: record.osmAddrState
                ),
                regionOrStateName: record.osmAddrState,
                countryName: country.countryName,
                countryCode: country.countryCode
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
        brandName: String?,
        brandWikidata: String?,
        categoryIcon: String?,
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
        addrCountry: String?,
        addrState: String?,
        addrPostcode: String?
    ) -> OsmTags {
        let categoryAssignment = ElementCategorySymbols.osmTagAssignment(forCategoryIcon: categoryIcon)

        return OsmTags(
            addrCity: addrCity,
            addrCountry: addrCountry,
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
            brand: brandName,
            brandWikidata: brandWikidata,
            description: description,
            descriptionEn: nil,
            website: website,
            contactWebsite: nil,
            phone: phone,
            contactPhone: nil,
            openingHours: openingHours,
            cuisine: value(forTagKey: "cuisine", assignment: categoryAssignment),
            shop: value(forTagKey: "shop", assignment: categoryAssignment),
            sport: value(forTagKey: "sport", assignment: categoryAssignment),
            tourism: value(forTagKey: "tourism", assignment: categoryAssignment),
            healthcare: value(forTagKey: "healthcare", assignment: categoryAssignment),
            craft: value(forTagKey: "craft", assignment: categoryAssignment),
            amenity: value(forTagKey: "amenity", assignment: categoryAssignment),
            place: value(forTagKey: "place", assignment: categoryAssignment),
            leisure: value(forTagKey: "leisure", assignment: categoryAssignment),
            office: value(forTagKey: "office", assignment: categoryAssignment),
            building: value(forTagKey: "building", assignment: categoryAssignment),
            company: value(forTagKey: "company", assignment: categoryAssignment)
        )
    }

    private static func value(
        forTagKey key: String,
        assignment: (tagKey: String, tagValue: String)?
    ) -> String? {
        guard assignment?.tagKey == key else { return nil }
        return assignment?.tagValue
    }
}

final class BTCMapRepository: BTCMapRepositoryProtocol {
    static let shared = BTCMapRepository()
    static let epochISO8601 = "1970-01-01T00:00:00Z"
    private static let incrementalRefreshThreshold: TimeInterval = 6 * 60 * 60

    private let v2Client = BTCMapV2Client()
    private let v2AreasClient = BTCMapV2AreasClient()
    private let v3Client = BTCMapV3AreasClient()
    private let v4Client: BTCMapV4ClientProtocol
    private let merchantStore: MerchantStore
    private let userDefaults: UserDefaults
    private let modeKey = "btcmap_data_source_mode"
    private let enrichmentQueue = DispatchQueue(label: "btcmap-repository.enrichment", qos: .utility)
    private let geocoder = Geocoder.shared
    private var isEnrichmentProcessing = false

    init(
        v4Client: BTCMapV4ClientProtocol = BTCMapV4Client(),
        merchantStore: MerchantStore = BTCMapRepository.makeDefaultMerchantStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.v4Client = v4Client
        self.merchantStore = merchantStore
        self.userDefaults = userDefaults
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

    func loadCachedElements(ids: [String]) -> [Element] {
        merchantStore.loadElements(ids: ids)
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

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        v4Client.fetchEvents(query: query, completion: completion)
    }

    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) {
        v3Client.fetchAreas(updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) {
        v2AreasClient.fetchAreas(updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) {
        v3Client.fetchArea(id: id, completion: completion)
    }

    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) {
        v3Client.fetchAreaElements(areaID: areaID, updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        v4Client.fetchPlaceComments(placeID: placeID, completion: completion)
    }

    @discardableResult
    func upsertFetchedPlace(_ record: V4PlaceRecord) -> Element {
        let element = V4PlaceToElementMapper.placeRecordToElement(record)
        merchantStore.upsert(element)
        scheduleCityLinkageResolution(for: [element.id])
        return merchantStore.loadElements(ids: [element.id]).first ?? element
    }

    @discardableResult
    func persistMergedAddress(_ address: Address?, forMerchantID merchantID: String) -> Element? {
        let persisted = merchantStore.persistMergedAddress(address, forMerchantID: merchantID)
        if persisted != nil {
            scheduleCityLinkageResolution(for: [merchantID])
        }
        return persisted
    }

    func processAddressEnrichmentJobs(limit: Int) {
        guard limit > 0 else { return }

        enrichmentQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isEnrichmentProcessing else { return }

            let candidates = self.merchantStore.pendingEnrichmentCandidates(limit: limit)
            guard !candidates.isEmpty else { return }

            self.isEnrichmentProcessing = true
            self.processEnrichmentCandidates(candidates, index: 0)
        }
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
        let currentElements = loadV4Elements() ?? []
        let syncState = loadV4SyncState()
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

        let requiresForcedBackfill = shouldForceFullNameBackfill(existing: currentElements, syncState: syncState)
        if hadV4Cache && !requiresForcedBackfill && !shouldPerformIncrementalSync(syncState: syncState) {
            completion(currentElements)
            return
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
                    self.merchantStore.replaceAllElements(mapped)
                    var syncState = self.loadV4SyncState()
                    syncState.snapshotLastModifiedRFC1123 = payload.lastModified
                    syncState.bundledSourceAnchor = fallbackTimestamp
                    // Snapshot payload omits names and rich fields. Force a full incremental
                    // backfill once so cached elements are upgraded to complete place records.
                    syncState.incrementalAnchorUpdatedSince = Self.epochISO8601
                    syncState.schemaVersion = 0
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
        var pageCount = 0
        var maxPages = 20

        if shouldForceFullNameBackfill(existing: existing, syncState: syncState) {
            anchor = Self.epochISO8601
            syncState.incrementalAnchorUpdatedSince = Self.epochISO8601
            maxPages = 200
            Debug.logAPI("BTCMapRepository: forcing one-time full v4 backfill to replace placeholder merchant names")
        }

        func step() {
            pageCount += 1
            v4Client.fetchPlaces(updatedSince: anchor, includeDeleted: true) { [weak self] result in
                guard let self else {
                    completion(.success(existing))
                    return
                }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let records):
                    if records.isEmpty {
                        syncState.schemaVersion = V4SyncState.currentSchemaVersion
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4SyncState(syncState)
                        completion(.success(self.loadV4Elements() ?? existing))
                        return
                    }

                    let incoming = records.map(V4PlaceToElementMapper.placeRecordToElement)
                    incoming.forEach { element in
                        let isDeleted = !(element.deletedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                        if isDeleted {
                            self.merchantStore.deleteMerchant(id: element.id)
                        } else {
                            self.merchantStore.upsert(element)
                        }
                    }

                    let updatedMerchantIDs = incoming
                        .filter { $0.deletedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
                        .map(\.id)
                    self.scheduleCityLinkageResolution(for: updatedMerchantIDs)

                    if let maxUpdated = records.compactMap({ $0.updatedAt }).max(),
                       self.parseFlexibleDate(maxUpdated) != nil {
                        anchor = maxUpdated
                        syncState.incrementalAnchorUpdatedSince = maxUpdated
                    }

                    self.saveV4SyncState(syncState)

                    if records.count >= 5000 && pageCount < maxPages {
                        step()
                    } else {
                        syncState.schemaVersion = V4SyncState.currentSchemaVersion
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4SyncState(syncState)
                        self.processAddressEnrichmentJobs(limit: 15)
                        completion(.success(self.loadV4Elements() ?? existing))
                    }
                }
            }
        }

        step()
    }

    private func shouldForceFullNameBackfill(existing: [Element], syncState: V4SyncState) -> Bool {
        guard syncState.schemaVersion < V4SyncState.currentSchemaVersion else { return false }
        guard !existing.isEmpty else { return false }
        return existing.contains { element in
            let name = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.hasPrefix("BTC Map Place #")
        }
    }

    private func loadV4Elements() -> [Element]? {
        merchantStore.loadElements()
    }

    private func hasV4CachedData() -> Bool {
        merchantStore.hasCachedData()
    }

    private func loadV4SyncState() -> V4SyncState {
        merchantStore.loadSyncState()
    }

    private func saveV4SyncState(_ state: V4SyncState) {
        merchantStore.saveSyncState(state)
    }

    private func shouldPerformIncrementalSync(syncState: V4SyncState, referenceDate: Date = Date()) -> Bool {
        guard let lastSuccessfulSyncAt = syncState.lastSuccessfulSyncAt,
              let lastSyncDate = parseFlexibleDate(lastSuccessfulSyncAt) else {
            return true
        }
        return referenceDate.timeIntervalSince(lastSyncDate) >= Self.incrementalRefreshThreshold
    }

    private func processEnrichmentCandidates(_ candidates: [MerchantEnrichmentCandidate], index: Int) {
        guard index < candidates.count else {
            enrichmentQueue.async { [weak self] in
                self?.isEnrichmentProcessing = false
            }
            return
        }

        let candidate = candidates[index]
        merchantStore.markEnrichmentAttemptStarted(for: candidate.merchantID)

        let location = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        geocoder.reverseGeocode(location: location, requestKey: "merchant:\(candidate.merchantID)") { [weak self] response in
            guard let self else { return }

            if let placemark = response.placemark {
                let geocodedAddress = Address(
                    streetNumber: self.normalized(placemark.subThoroughfare),
                    streetName: self.normalized(placemark.thoroughfare),
                    cityOrTownName: self.normalized(placemark.locality),
                    postalCode: Address.normalizedPostalCode(
                        self.normalized(placemark.postalCode),
                        countryName: self.normalized(placemark.country),
                        countryCode: self.normalized(placemark.isoCountryCode),
                        regionOrStateName: self.normalized(placemark.administrativeArea)
                    ),
                    regionOrStateName: self.normalized(placemark.administrativeArea),
                    countryName: self.normalized(placemark.country),
                    countryCode: self.normalized(placemark.isoCountryCode)
                )

                let fallback = Address.merged(preferred: geocodedAddress, fallback: candidate.mergedAddress)
                let merged = Address.merged(preferred: candidate.sourceAddress, fallback: fallback)
                _ = self.persistMergedAddress(merged, forMerchantID: candidate.merchantID)

                if Address.needsEnrichment(merged) {
                    self.merchantStore.markEnrichmentDeferred(
                        for: candidate.merchantID,
                        status: "partial",
                        retryAfter: Date().addingTimeInterval(24 * 60 * 60)
                    )
                }
            } else if let retryAfter = response.retryAfter {
                self.merchantStore.markEnrichmentDeferred(
                    for: candidate.merchantID,
                    status: "failed",
                    retryAfter: retryAfter,
                    errorCode: (response.error as NSError?)?.domain
                )
            } else {
                self.merchantStore.markEnrichmentDeferred(
                    for: candidate.merchantID,
                    status: "no_result",
                    retryAfter: Date().addingTimeInterval(24 * 60 * 60)
                )
            }

            self.enrichmentQueue.async { [weak self] in
                self?.processEnrichmentCandidates(candidates, index: index + 1)
            }
        }
    }

    private func scheduleCityLinkageResolution(for merchantIDs: [String]) {
        let uniqueMerchantIDs = Array(Set(merchantIDs))
        guard !uniqueMerchantIDs.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for merchantID in uniqueMerchantIDs {
                guard let merchant = self.merchantStore.loadElements(ids: [merchantID]).first else { continue }
                guard let address = merchant.address else {
                    self.merchantStore.processPendingCityLinkage(forMerchantID: merchantID, locationID: nil, cityKey: nil)
                    continue
                }

                let country = Address.normalizedAddressComponent(address.localizedCountryName ?? address.countryName ?? address.countryCode) ?? ""
                let city = Address.normalizedAddressComponent(address.cityOrTownName) ?? ""
                guard !city.isEmpty, !country.isEmpty else {
                    self.merchantStore.processPendingCityLinkage(
                        forMerchantID: merchantID,
                        locationID: nil,
                        cityKey: nil
                    )
                    continue
                }

                let region = Address.normalizedAddressComponent(address.regionOrStateName) ?? ""
                let cityKey = MerchantAlertsCityNormalizer.cityKey(city: city, region: region, country: country)
                let resolved = await CityIndexStore.shared.result(forCityKey: cityKey)
                self.merchantStore.processPendingCityLinkage(
                    forMerchantID: merchantID,
                    locationID: resolved?.locationID,
                    cityKey: resolved?.cityKey ?? cityKey
                )
            }
        }
    }

    private func normalized(_ value: String?) -> String? {
        Address.normalizedAddressComponent(value)
    }

    private static func makeDefaultMerchantStore() -> MerchantStore {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return MerchantStore(
            legacyElementsURL: cachesDirectory?.appendingPathComponent("btcmap_elements_v4.json"),
            legacySyncStateURL: cachesDirectory?.appendingPathComponent("btcmap_v4_sync_state.json")
        )
    }

    static func mergeElements(existing: [Element], incoming: [Element]) -> [Element] {
        var dictionary = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for element in incoming {
            let isDeleted = !(element.deletedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if isDeleted {
                dictionary.removeValue(forKey: element.id)
                continue
            }

            if let current = dictionary[element.id] {
                if shouldPreferIncoming(element, over: current) || isIncomingNewer(element, than: current) {
                    dictionary[element.id] = element
                }
            } else {
                dictionary[element.id] = element
            }
        }
        return Array(dictionary.values)
    }

    private static func shouldPreferIncoming(_ incoming: Element, over current: Element) -> Bool {
        let currentName = current.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingName = incoming.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentIsPlaceholder = currentName.hasPrefix("BTC Map Place #")
        let incomingIsPlaceholder = incomingName.hasPrefix("BTC Map Place #")
        return currentIsPlaceholder && !incomingIsPlaceholder && !incomingName.isEmpty
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
