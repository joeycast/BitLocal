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

final class BTCMapV4Client: BTCMapV4ClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v4")!
    private let snapshotURL = URL(string: "https://cdn.static.btcmap.org/api/v4/places.json")!
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

    private func fetchData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BTCMapV4Error.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)
            throw BTCMapV4Error.httpStatus(http.statusCode, message)
        }
        return (data, http)
    }

    private func performDecodedRequest<T: Decodable>(
        url: URL?,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard let url else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        let request = makeRequest(url: url)
        Task {
            do {
                let (data, _) = try await fetchData(for: request)
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        var request = makeRequest(url: snapshotURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        Task {
            do {
                let (data, http) = try await fetchData(for: request)
                let records = try JSONDecoder().decode([V4PlaceSnapshotRecord].self, from: data)
                let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                completion(.success((records, lastModified)))
            } catch {
                completion(.failure(error))
            }
        }
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
        performDecodedRequest(url: components.url, completion: completion)
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
        performDecodedRequest(url: components.url, completion: completion)
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
        performDecodedRequest(url: components.url, completion: completion)
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false) else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        components.queryItems = query.queryItems()
        performDecodedRequest(url: components.url, completion: completion)
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        guard let encodedID = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.btcmap.org/v4/places/\(encodedID)/comments") else {
            completion(.failure(BTCMapV4Error.invalidURL))
            return
        }
        performDecodedRequest(url: url, completion: completion)
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

final class BTCMapV3AreasClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v3")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(BTCMapRequestMetadata.appUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetchData(for url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            throw BTCMapV3Error.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(500), encoding: .utf8)
            throw BTCMapV3Error.httpStatus(http.statusCode, message)
        }
        return data
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
        Task {
            var cursor = updatedSince
            var page = 0
            var collected: [V3AreaElementRecord] = []

            do {
                while true {
                    guard var components = URLComponents(url: baseURL.appendingPathComponent("area-elements"), resolvingAgainstBaseURL: false) else {
                        throw BTCMapV3Error.invalidURL
                    }
                    components.queryItems = [
                        URLQueryItem(name: "area_id", value: String(areaID)),
                        URLQueryItem(name: "updated_since", value: cursor),
                        URLQueryItem(name: "limit", value: String(pageLimit))
                    ]
                    guard let url = components.url else {
                        throw BTCMapV3Error.invalidURL
                    }

                    let data = try await fetchData(for: url)
                    let decoded = try JSONDecoder().decode([V3AreaElementRecord].self, from: data)
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
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func performRequest<T: Decodable>(url: URL?, completion: @escaping (Result<[T], Error>) -> Void) {
        guard let url else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        Task {
            do {
                let data = try await fetchData(for: url)
                let decoded = try JSONDecoder().decode([T].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func performSingleRequest<T: Decodable>(url: URL?, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url else {
            completion(.failure(BTCMapV3Error.invalidURL))
            return
        }
        Task {
            do {
                let data = try await fetchData(for: url)
                let decoder = JSONDecoder()
                if let object = try? decoder.decode(T.self, from: data) {
                    completion(.success(object))
                    return
                }
                if let array = try? decoder.decode([T].self, from: data), let first = array.first {
                    completion(.success(first))
                    return
                }
                completion(.failure(BTCMapV3Error.invalidResponse))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

final class BTCMapV2AreasClient: @unchecked Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.btcmap.org/v2")!

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
        Task {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(BTCMapV3Error.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let message = String(data: data.prefix(500), encoding: .utf8)
                    completion(.failure(BTCMapV3Error.httpStatus(http.statusCode, message)))
                    return
                }
                let decoded = try JSONDecoder().decode([V2AreaRecord].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
