import XCTest
@testable import bitlocal

final class V4SearchQueryEncodingTests: XCTestCase {
    func testEncodesNameRadiusAndTagFilters() {
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

        XCTAssertEqual(items["name"], "coffee")
        XCTAssertEqual(items["lat"], "36.12")
        XCTAssertEqual(items["lon"], "-86.67")
        XCTAssertEqual(items["radius_km"], "20.0")
        XCTAssertEqual(items["tag_name"], "payment:coinos")
        XCTAssertEqual(items["tag_value"], "yes")
    }

    func testShortNameIsStillAValidNameFilter() {
        let query = V4SearchQuery(name: "ab", lat: nil, lon: nil, radiusKM: nil, tagName: nil, tagValue: nil)
        XCTAssertFalse(query.isEmpty)
        let items = Dictionary(uniqueKeysWithValues: query.queryItems().compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(items["name"], "ab")
    }
}

final class PlaceShareLinkBuilderTests: XCTestCase {
    func testCreatesCanonicalShareURLForValidID() {
        let url = PlaceShareLinkBuilder.makeShareURL(forPlaceID: "12345")
        XCTAssertEqual(url?.absoluteString, "https://www.bitlocal.app/place/12345")
    }

    func testRejectsInvalidPlaceID() {
        XCTAssertNil(PlaceShareLinkBuilder.makeShareURL(forPlaceID: ""))
        XCTAssertNil(PlaceShareLinkBuilder.makeShareURL(forPlaceID: "12/34"))
        XCTAssertNil(PlaceShareLinkBuilder.makeShareURL(forPlaceID: " abc "))
    }
}

final class BTCMapMerchantURLBuilderTests: XCTestCase {
    func testCreatesMerchantURLFromPlaceID() {
        let element = Self.makeElement(
            id: "34515",
            lat: 12.34,
            lon: 56.78
        )

        let url = BTCMapMerchantURLBuilder.makeURL(for: element)

        XCTAssertEqual(url?.absoluteString, "https://btcmap.org/merchant/34515")
    }

    func testFallsBackToMapURLWhenPlaceIDIsInvalid() {
        let element = Self.makeElement(
            id: "invalid/id",
            lat: 12.34,
            lon: 56.78
        )

        let url = BTCMapMerchantURLBuilder.makeURL(for: element)

        XCTAssertEqual(url?.absoluteString, "https://btcmap.org/map?lat=12.34&long=56.78")
    }

    func testReturnsNilWithoutValidIDOrCoordinates() {
        let element = Self.makeElement(
            id: "invalid/id",
            lat: nil,
            lon: nil
        )

        XCTAssertNil(BTCMapMerchantURLBuilder.makeURL(for: element))
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

final class DeepLinkParserTests: XCTestCase {
    func testParsesAllowedPlaceLink() {
        let url = URL(string: "https://www.bitlocal.app/place/9876")!
        XCTAssertEqual(DeepLinkParser.parse(url: url), .place(id: "9876"))
    }

    func testRejectsUnsupportedHostOrPath() {
        XCTAssertNil(DeepLinkParser.parse(url: URL(string: "https://example.com/place/9876")!))
        XCTAssertNil(DeepLinkParser.parse(url: URL(string: "https://www.bitlocal.app/places/9876")!))
        XCTAssertNil(DeepLinkParser.parse(url: URL(string: "http://www.bitlocal.app/place/9876")!))
    }
}

@MainActor
final class DeepLinkHandlingTests: XCTestCase {
    private var previousShareFlagValue: Bool = false

    override func setUp() {
        super.setUp()
        previousShareFlagValue = UserDefaults.standard.bool(forKey: FeatureFlags.sharePlaceLinksKey)
        UserDefaults.standard.set(true, forKey: FeatureFlags.sharePlaceLinksKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(previousShareFlagValue, forKey: FeatureFlags.sharePlaceLinksKey)
        super.tearDown()
    }

    func testHandleIncomingURLFetchesAndNavigatesToPlace() async {
        let repo = DeepLinkMockRepository()
        repo.fetchPlaceHandler = { id, completion in
            XCTAssertEqual(id, "4242")
            completion(.success(Self.makePlaceRecord(id: 4242)))
        }

        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        let url = URL(string: "https://www.bitlocal.app/place/4242")!

        viewModel.handleIncomingURL(url)
        await waitForCondition { viewModel.selectedElement?.id == "4242" }

        XCTAssertEqual(viewModel.path.last?.id, "4242")
        XCTAssertEqual(viewModel.mapDisplayMode, .merchants)
        XCTAssertNil(viewModel.deepLinkUnavailableState)
    }

    func testHandleIncomingURLShowsUnavailableStateOnFailure() async {
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

        XCTAssertEqual(viewModel.deepLinkUnavailableState?.placeID, "9999")
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
            osmAddrCountry: nil,
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

private final class DeepLinkMockRepository: BTCMapRepositoryProtocol {
    var fetchPlaceHandler: ((String, @escaping (Result<V4PlaceRecord, Error>) -> Void) -> Void)?

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        if let fetchPlaceHandler {
            fetchPlaceHandler(id, completion)
        } else {
            completion(.failure(DeepLinkMockError.notFound))
        }
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func loadCachedElements() -> [Element]? { [] }
    func loadCachedElements(ids: [String]) -> [Element] { [] }
    func hasCachedData() -> Bool { false }
    func refreshElements(completion: @escaping ([Element]?) -> Void) { completion([]) }
    func upsertFetchedPlace(_ record: V4PlaceRecord) -> Element { V4PlaceToElementMapper.placeRecordToElement(record) }
    func persistMergedAddress(_ address: Address?, forMerchantID merchantID: String) -> Element? { nil }
    func processAddressEnrichmentJobs(limit: Int) {}
    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) { completion(.failure(DeepLinkMockError.notFound)) }
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) { completion(.success([])) }
}
