import Foundation
import BitLocalDomain

/// The BTC Map v4 calls the sync engine needs. A protocol so tests use fakes.
public protocol BTCMapPlacesClient: Sendable {
    /// The thin CDN snapshot of every place, plus its `Last-Modified` date.
    func snapshot() async throws -> (places: [BTCMapSnapshotPlace], lastModified: Date?)
    /// Places changed since `updatedSince` (ISO 8601), including deletions, oldest first.
    func places(updatedSince: String, limit: Int) async throws -> [BTCMapPlace]
    /// One place with every field the app shows.
    func place(id: MerchantID) async throws -> BTCMapPlace
}

public enum BTCMapClientError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
}

/// Live v4 client on `URLSession` async APIs.
public struct BTCMapClient: BTCMapPlacesClient {
    public static let fields = [
        "id", "lat", "lon", "icon", "name", "display_name", "address",
        "opening_hours", "comments", "created_at", "updated_at", "deleted_at",
        "verified_at", "osm_id", "osm_url", "phone", "website", "email",
        "twitter", "facebook", "instagram", "telegram", "line",
        "boosted_until", "required_app_url", "description", "image", "payment_provider",
        "osm:payment:bitcoin", "osm:currency:XBT", "osm:payment:onchain",
        "osm:payment:lightning", "osm:payment:lightning_contactless",
        "osm:addr:housenumber", "osm:addr:street", "osm:addr:city",
        "osm:addr:state", "osm:addr:postcode", "osm:operator", "osm:brand", "osm:brand:wikidata",
    ]

    let session: URLSession
    let userAgent: String
    let baseURL: URL
    let snapshotURL: URL

    public init(
        session: URLSession = .shared,
        userAgent: String,
        baseURL: URL = URL(string: "https://api.btcmap.org/v4")!,
        snapshotURL: URL = URL(string: "https://cdn.static.btcmap.org/api/v4/places.json")!
    ) {
        self.session = session
        self.userAgent = userAgent
        self.baseURL = baseURL
        self.snapshotURL = snapshotURL
    }

    public func snapshot() async throws -> (places: [BTCMapSnapshotPlace], lastModified: Date?) {
        var request = makeRequest(snapshotURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await load(request)
        let places = try JSONDecoder().decode([BTCMapSnapshotPlace].self, from: data)
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified").flatMap(Self.parseHTTPDate)
        return (places, lastModified)
    }

    public func places(updatedSince: String, limit: Int) async throws -> [BTCMapPlace] {
        var components = URLComponents(url: baseURL.appendingPathComponent("places"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields", value: Self.fields.joined(separator: ",")),
            URLQueryItem(name: "updated_since", value: updatedSince),
            URLQueryItem(name: "include_deleted", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await load(makeRequest(components.url!))
        return try JSONDecoder().decode([BTCMapPlace].self, from: data)
    }

    public func place(id: MerchantID) async throws -> BTCMapPlace {
        var components = URLComponents(url: baseURL.appendingPathComponent("places/\(id.rawValue)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields.joined(separator: ","))]
        let (data, _) = try await load(makeRequest(components.url!))
        return try JSONDecoder().decode(BTCMapPlace.self, from: data)
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BTCMapClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw BTCMapClientError.httpStatus(http.statusCode) }
        return (data, http)
    }

    /// RFC 1123 dates from `Last-Modified` ("Sun, 08 Nov 2026 15:00:00 GMT").
    static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}
