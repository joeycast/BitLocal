import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.search))
struct V4SearchQueryEncodingTests {
    @Test func encodesNameRadiusAndTagFilters() {
        let query = V4SearchQuery(
            name: "coffee",
            lat: 36.12,
            lon: -86.67,
            radiusKM: 20,
            tagName: "payment:coinos",
            tagValue: "yes"
        )

        let items = Dictionary(uniqueKeysWithValues: query.queryItems().compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(items["name"] == "coffee")
        #expect(items["lat"] == "36.12")
        #expect(items["lon"] == "-86.67")
        #expect(items["radius_km"] == "20.0")
        #expect(items["tag_name"] == "payment:coinos")
        #expect(items["tag_value"] == "yes")
    }

    @Test func shortNameIsStillAValidNameFilter() {
        let query = V4SearchQuery(name: "ab", lat: nil, lon: nil, radiusKM: nil, tagName: nil, tagValue: nil)
        #expect(query.isEmpty == false)
        let items = Dictionary(uniqueKeysWithValues: query.queryItems().compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(items["name"] == "ab")
    }
}

@Suite(.tags(.routing))
struct PlaceShareLinkBuilderTests {
    @Test func createsCanonicalShareURLForValidID() {
        let url = PlaceShareLinkBuilder.makeShareURL(forPlaceID: "12345")
        #expect(url?.absoluteString == "https://www.bitlocal.app/place/12345")
    }

    @Test func rejectsInvalidPlaceID() {
        #expect(PlaceShareLinkBuilder.makeShareURL(forPlaceID: "") == nil)
        #expect(PlaceShareLinkBuilder.makeShareURL(forPlaceID: "12/34") == nil)
        #expect(PlaceShareLinkBuilder.makeShareURL(forPlaceID: " abc ") == nil)
    }
}

@Suite(.tags(.routing))
struct BTCMapMerchantURLBuilderTests {
    @Test func createsMerchantURLFromPlaceID() {
        let element = Self.makeElement(
            id: "34515",
            lat: 12.34,
            lon: 56.78
        )

        let url = BTCMapMerchantURLBuilder.makeURL(for: element)

        #expect(url?.absoluteString == "https://btcmap.org/merchant/34515")
    }

    @Test func fallsBackToMapURLWhenPlaceIDIsInvalid() {
        let element = Self.makeElement(
            id: "invalid/id",
            lat: 12.34,
            lon: 56.78
        )

        let url = BTCMapMerchantURLBuilder.makeURL(for: element)

        #expect(url?.absoluteString == "https://btcmap.org/map?lat=12.34&long=56.78")
    }

    @Test func returnsNilWithoutValidIDOrCoordinates() {
        let element = Self.makeElement(
            id: "invalid/id",
            lat: nil,
            lon: nil
        )

        #expect(BTCMapMerchantURLBuilder.makeURL(for: element) == nil)
    }

    private static func makeElement(id: String, lat: Double?, lon: Double?) -> Element {
        Element(
            id: id,
            osmJSON: makeOsmJSON(lat: lat, lon: lon),
            tags: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil,
            address: nil,
            v4Metadata: nil
        )
    }

    private static func makeOsmJSON(lat: Double?, lon: Double?) -> OsmJSON? {
        guard let lat, let lon else { return nil }
        let data = Data(#"{"lat":\#(lat),"lon":\#(lon)}"#.utf8)
        return try? JSONDecoder().decode(OsmJSON.self, from: data)
    }
}

@Suite(.tags(.routing))
struct DeepLinkParserTests {
    private let insecureScheme = "http" + "://"

    @Test func parsesAllowedPlaceLink() {
        let url = URL(string: "https://www.bitlocal.app/place/9876")!
        #expect(DeepLinkParser.parse(url: url) == .place(id: "9876"))
    }

    @Test func rejectsUnsupportedHostOrPath() {
        #expect(DeepLinkParser.parse(url: URL(string: "https://example.com/place/9876")!) == nil)
        #expect(DeepLinkParser.parse(url: URL(string: "https://www.bitlocal.app/places/9876")!) == nil)
        #expect(DeepLinkParser.parse(url: URL(string: "\(insecureScheme)www.bitlocal.app/place/9876")!) == nil)
    }
}

@Suite(.tags(.formatting))
struct WebsiteURLCleaningTests {
    @Test func cleansDuplicatedProtocolsToHTTPS() {
        let url = ("http" + "://" + "https" + "://" + "bitlocal.app").cleanedWebsiteURL()

        #expect(url?.absoluteString == "https://bitlocal.app")
    }

    @Test func addsHTTPSWhenSchemeIsMissing() {
        let url = "bitlocal.app".cleanedWebsiteURL()

        #expect(url?.absoluteString == "https://bitlocal.app")
    }
}

@MainActor
@Suite(.serialized, .tags(.routing))
final class DeepLinkHandlingTests {
    private let previousShareFlagValue: Bool

    init() {
        previousShareFlagValue = UserDefaults.standard.bool(forKey: FeatureFlags.sharePlaceLinksKey)
        UserDefaults.standard.set(true, forKey: FeatureFlags.sharePlaceLinksKey)
    }

    deinit {
        UserDefaults.standard.set(previousShareFlagValue, forKey: FeatureFlags.sharePlaceLinksKey)
    }

    @Test func handleIncomingURLFetchesAndNavigatesToPlace() async {
        let repo = DeepLinkMockRepository()
        repo.fetchPlaceHandler = { id, completion in
            #expect(id == "4242")
            completion(.success(Self.makePlaceRecord(id: 4242)))
        }

        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        let url = URL(string: "https://www.bitlocal.app/place/4242")!

        viewModel.handleIncomingURL(url)
        await waitForCondition { viewModel.selectedElement?.id == "4242" }

        #expect(viewModel.path.last?.id == "4242")
        #expect(viewModel.mapDisplayMode == .merchants)
        #expect(viewModel.deepLinkUnavailableState == nil)
    }

    @Test func handleIncomingURLShowsUnavailableStateOnFailure() async {
        let repo = DeepLinkMockRepository()
        repo.fetchPlaceHandler = { _, completion in
            completion(.failure(DeepLinkMockError.notFound))
        }

        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        let url = URL(string: "https://www.bitlocal.app/place/9999")!

        viewModel.handleIncomingURL(url)
        await waitForCondition { viewModel.deepLinkUnavailableState != nil }

        #expect(viewModel.deepLinkUnavailableState?.placeID == "9999")
    }

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 500_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func makePlaceRecord(id: Int) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: 36.16,
            lon: -86.78,
            icon: "cafe",
            name: "Shared Place",
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            deletedAt: nil,
            verifiedAt: nil,
            osmID: nil,
            osmURL: nil,
            phone: nil,
            website: nil,
            twitter: nil,
            facebook: nil,
            instagram: nil,
            line: nil,
            telegram: nil,
            email: nil,
            boostedUntil: nil,
            requiredAppURL: nil,
            description: nil,
            image: nil,
            paymentProvider: nil,
            osmPaymentBitcoin: nil,
            osmCurrencyXBT: nil,
            osmPaymentOnchain: nil,
            osmPaymentLightning: nil,
            osmPaymentLightningContactless: nil,
            osmAddrHouseNumber: nil,
            osmAddrStreet: nil,
            osmAddrCity: nil,
            osmAddrState: nil,
            osmAddrPostcode: nil,
            osmOperator: nil,
            osmBrand: nil,
            osmBrandWikidata: nil
        )
    }
}

private enum DeepLinkMockError: Error {
    case notFound
}

private final class DeepLinkMockRepository: BTCMapRepositoryProtocol, @unchecked Sendable {
    var fetchPlaceHandler: ((String, @escaping (Result<V4PlaceRecord, Error>) -> Void) -> Void)?

    func searchPlaces(query: V4SearchQuery, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping @Sendable (Result<V4PlaceRecord, Error>) -> Void) {
        if let fetchPlaceHandler {
            fetchPlaceHandler(id, completion)
        } else {
            completion(.failure(DeepLinkMockError.notFound))
        }
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping @Sendable (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping @Sendable (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func loadCachedElements() -> [Element]? { [] }
    func hasCachedData() -> Bool { false }
    func refreshElements(completion: @escaping @Sendable ([Element]?) -> Void) { completion([]) }
    func lastSuccessfulSyncAtISO8601() -> String? { nil }
    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V2AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Area(id: Int, completion: @escaping @Sendable (Result<V3AreaRecord, Error>) -> Void) { completion(.failure(DeepLinkMockError.notFound)) }
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaElementRecord], Error>) -> Void) { completion(.success([])) }
}
