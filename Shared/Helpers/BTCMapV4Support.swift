import Foundation

enum BTCMapRequestMetadata {
    static var appUserAgent: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "BitLocal-iOS/\(version) (\(build); iOS)"
    }
}

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
        "osm:addr:state", "osm:addr:postcode", "osm:operator", "osm:brand", "osm:brand:wikidata"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        var request = makeRequest(url: snapshotURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
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
        guard let url = components.url else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        let request = makeRequest(url: url)
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

        let request = makeRequest(url: url)
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
        let request = makeRequest(url: url)
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
        var request = makeRequest(url: url, method: "POST")
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
        var request = makeRequest(url: url)
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

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")
        return request
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

            let request = makeRequest(url: url)
            session.dataTask(with: request) { data, response, error in
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
        let request = makeRequest(url: url)
        session.dataTask(with: request) { data, response, error in
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
        let request = makeRequest(url: url)
        session.dataTask(with: request) { data, response, error in
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

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")
        return request
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

        let request = makeRequest(url: url)
        session.dataTask(with: request) { data, response, error in
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
                iconPlatform: record.icon,
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
            iconPlatform: record.icon,
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
        addrState: String?,
        addrPostcode: String?
    ) -> OsmTags {
        let categoryAssignment = ElementCategorySymbols.osmTagAssignment(forCategoryIcon: categoryIcon)

        return OsmTags(
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

    private let v2Client = BTCMapV2Client()
    private let v2AreasClient = BTCMapV2AreasClient()
    private let v3Client = BTCMapV3AreasClient()
    private let v4Client: BTCMapV4ClientProtocol
    private let userDefaults: UserDefaults
    private let modeKey = "btcmap_data_source_mode"
    private let cacheWriteQueue = DispatchQueue(label: "app.bitlocal.btcmap-cache-writes", qos: .utility)
    private let refreshStateQueue = DispatchQueue(label: "app.bitlocal.btcmap-refresh-state", qos: .userInitiated)
    private var isV4RefreshInFlight = false
    private var pendingV4RefreshCompletions: [([Element]?) -> Void] = []

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

    private var dataSourceMode: BTCMapDataSourceMode {
        guard let raw = userDefaults.string(forKey: modeKey),
              let mode = BTCMapDataSourceMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    private func refreshV4(allowV2Fallback: Bool, completion: @escaping ([Element]?) -> Void) {
        let shouldStartRefresh = refreshStateQueue.sync { () -> Bool in
            pendingV4RefreshCompletions.append(completion)
            guard !isV4RefreshInFlight else {
                Debug.logTiming("sync", "coalescing refresh onto in-flight v4 sync")
                return false
            }
            isV4RefreshInFlight = true
            return true
        }

        guard shouldStartRefresh else { return }

        let hadV4Cache = hasV4CachedData()
        let finishRefresh: ([Element]?) -> Void = { [weak self] elements in
            self?.finishV4Refresh(elements: elements)
        }
        let startIncremental: (String?, [Element]?) -> Void = { [weak self] initialAnchorOverride, initialExistingOverride in
            Debug.logTiming("sync", "starting v4 incremental sync (hadCache=\(hadV4Cache))")
            self?.performV4IncrementalSync(
                initialAnchorOverride: initialAnchorOverride,
                initialExistingOverride: initialExistingOverride,
                completion: { result in
                switch result {
                case .success(let elements):
                    Debug.logTiming("sync", "v4 incremental sync completed with \(elements.count) elements")
                    finishRefresh(elements)
                case .failure(let error):
                    Debug.logAPI("BTCMap v4 incremental sync failed: \(error.localizedDescription)")
                    if allowV2Fallback && !hadV4Cache {
                        self?.v2Client.refreshElements(completion: finishRefresh)
                    } else {
                        finishRefresh(self?.loadV4Elements() ?? self?.v2Client.loadCachedElements())
                    }
                }
                }
            )
        }

        if !hadV4Cache {
            Debug.logAPI("BTCMapRepository: no v4 cache, bootstrapping snapshot")
            Debug.logTiming("sync", "starting v4 snapshot bootstrap")
            v4Client.fetchSnapshot { [weak self] result in
                guard let self else {
                    completion(nil)
                    return
                }
                switch result {
                case .success(let payload):
                    let fallbackTimestamp = Self.rfc1123ToISO8601(payload.lastModified) ?? Self.currentISO8601()
                    let initialIncrementalAnchor = Self.rfc1123ToISO8601(payload.lastModified) ?? fallbackTimestamp
                    let mapped = payload.records.map { V4PlaceToElementMapper.snapshotRecordToElement($0, fallbackTimestamp: fallbackTimestamp) }
                    Debug.logTiming("sync", "snapshot bootstrap fetched \(mapped.count) records; initial anchor=\(initialIncrementalAnchor)")
                    self.saveV4Elements(mapped, reason: "snapshot-bootstrap")
                    var syncState = self.loadV4SyncState()
                    syncState.snapshotLastModifiedRFC1123 = payload.lastModified
                    // Follow BTC Map's recommended flow: bootstrap from the CDN snapshot,
                    // then incrementally apply only changes newer than the snapshot.
                    syncState.incrementalAnchorUpdatedSince = initialIncrementalAnchor
                    syncState.schemaVersion = V4SyncState.currentSchemaVersion
                    self.saveV4SyncState(syncState)
                    startIncremental(initialIncrementalAnchor, mapped)
                case .failure(let error):
                    Debug.logAPI("BTCMap v4 snapshot bootstrap failed: \(error.localizedDescription)")
                    if allowV2Fallback {
                        self.v2Client.refreshElements(completion: finishRefresh)
                    } else {
                        finishRefresh(nil)
                    }
                }
            }
            return
        }

        startIncremental(nil, nil)
    }

    private func finishV4Refresh(elements: [Element]?) {
        let completions = refreshStateQueue.sync { () -> [([Element]?) -> Void] in
            let callbacks = pendingV4RefreshCompletions
            pendingV4RefreshCompletions.removeAll()
            isV4RefreshInFlight = false
            return callbacks
        }

        completions.forEach { $0(elements) }
    }

    private func performV4IncrementalSync(
        initialAnchorOverride: String? = nil,
        initialExistingOverride: [Element]? = nil,
        completion: @escaping (Result<[Element], Error>) -> Void
    ) {
        let existing = initialExistingOverride ?? loadV4Elements() ?? []
        var syncState = loadV4SyncState()
        var anchor = initialAnchorOverride
            ?? syncState.incrementalAnchorUpdatedSince
            ?? Self.rfc1123ToISO8601(syncState.snapshotLastModifiedRFC1123)
            ?? Self.epochISO8601
        var merged = existing
        var pageCount = 0
        var maxPages = 20

        if shouldForceFullNameBackfill(existing: existing, syncState: syncState) {
            anchor = Self.epochISO8601
            syncState.incrementalAnchorUpdatedSince = Self.epochISO8601
            maxPages = 200
            Debug.logAPI("BTCMapRepository: forcing one-time full v4 backfill to replace stale merchant names")
        }

        Debug.logTiming("sync", "incremental sync stepper ready (existing=\(existing.count), anchor=\(anchor), maxPages=\(maxPages))")

        func step() {
            pageCount += 1
            Debug.logTiming("sync", "requesting incremental page \(pageCount) from anchor \(anchor)")
            v4Client.fetchPlaces(updatedSince: anchor, includeDeleted: true) { [weak self] result in
                guard let self else {
                    completion(.success(merged))
                    return
                }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let records):
                    Debug.logTiming("sync", "received incremental page \(pageCount) with \(records.count) records")
                    if records.isEmpty {
                        syncState.schemaVersion = V4SyncState.currentSchemaVersion
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4Elements(merged, reason: "incremental-empty-page")
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

                    self.saveV4SyncState(syncState)

                    if records.count >= 5000 && pageCount < maxPages {
                        step()
                    } else {
                        syncState.schemaVersion = V4SyncState.currentSchemaVersion
                        syncState.lastSuccessfulSyncAt = Self.currentISO8601()
                        self.saveV4Elements(merged, reason: "incremental-final-page")
                        self.saveV4SyncState(syncState)
                        completion(.success(merged))
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
        do {
            let data = try Data(contentsOf: v4ElementsFileURL)
            let elements = try JSONDecoder().decode([Element].self, from: data)
            return elements.isEmpty ? nil : elements
        } catch {
            return nil
        }
    }

    private func saveV4Elements(_ elements: [Element], reason: String = "unspecified") {
        cacheWriteQueue.async {
            do {
                let data = try JSONEncoder().encode(elements)
                try data.write(to: self.v4ElementsFileURL, options: .atomic)
                Debug.logCache("Saved \(elements.count) v4 elements to \(self.v4ElementsFileURL.lastPathComponent) [reason=\(reason)]")
                Debug.logTiming("sync", "saved \(elements.count) v4 elements [reason=\(reason)]")
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
        cacheWriteQueue.async {
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: self.v4SyncStateFileURL, options: .atomic)
            } catch {
                Debug.logCache("Failed to save v4 sync state: \(error.localizedDescription)")
            }
        }
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
