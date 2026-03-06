import XCTest
import CoreLocation
import MapKit
@testable import bitlocal

@MainActor
final class MerchantSearchBehaviorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "search_v2_hybrid")
    }

    func testTwoCharacterQueryUsesLocalOnlyAndSkipsRemote() async {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Da Vinci Coffee"))
        ]

        viewModel.unifiedSearchText = "da"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        XCTAssertEqual(repo.searchPlaceQueries.count, 0)
        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.count, 1)
        XCTAssertTrue(viewModel.merchantSearchFreshResults.isEmpty)
    }

    func testThreeCharacterQueryCallsRemoteAndAddsFreshSection() async {
        let repo = MockBTCMapRepository()
        repo.searchPlacesHandler = { _, completion in
            completion(.success([Self.placeRecord(id: 99, name: "Coffee Spot")]))
        }

        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 10, name: "Coffee House"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForRemoteQuery(on: repo)

        XCTAssertEqual(repo.searchPlaceQueries.count, 1)
        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.count, 1)
        XCTAssertEqual(viewModel.merchantSearchFreshResults.count, 1)
        XCTAssertEqual(viewModel.merchantSearchFreshResults.first?.id, 99)
        XCTAssertFalse(viewModel.merchantSearchIsOfflineFallback)
    }

    func testRemoteFailureRetainsLocalPrimaryAndSetsOfflineState() async {
        let repo = MockBTCMapRepository()
        repo.searchPlacesHandler = { _, completion in
            completion(.failure(MockError.network))
        }

        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 20, name: "Coffee House"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForRemoteQuery(on: repo)

        XCTAssertEqual(repo.searchPlaceQueries.count, 1)
        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.count, 1)
        XCTAssertTrue(viewModel.merchantSearchFreshResults.isEmpty)
        XCTAssertTrue(viewModel.merchantSearchIsOfflineFallback)
        XCTAssertNotNil(viewModel.merchantSearchError)
    }

    func testPunctuationInsensitiveLocalMatchFindsSteakNShake() async {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 25770, name: "Steak 'n Shake"))
        ]

        viewModel.unifiedSearchText = "Steak n Shake"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.count, 1)
        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.first?.id, "25770")
    }

    func testWorldwideQueryUsesGlobalRemoteSearchWithoutRadius() async {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .worldwide
        viewModel.unifiedSearchText = "coffee"

        viewModel.performUnifiedSearch()
        await waitForRemoteQuery(on: repo)

        XCTAssertEqual(repo.searchPlaceQueries.count, 1)
        let query = try? XCTUnwrap(repo.searchPlaceQueries.first)
        XCTAssertEqual(query?.name, "coffee")
        XCTAssertNil(query?.lat)
        XCTAssertNil(query?.lon)
        XCTAssertNil(query?.radiusKM)
    }

    func testBoostedLocalMerchantSortsAheadOfNonBoostedLocalMerchant() async {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Coffee House", boostedUntil: nil)),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 2, name: "Coffee Roasters", boostedUntil: "2099-01-01T00:00:00Z"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(2, on: viewModel)

        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.map(\.id), ["2", "1"])
    }

    func testExpiredBoostDoesNotAffectLocalMerchantOrdering() async {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 10, name: "Coffee House", boostedUntil: nil)),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 11, name: "Coffee Roasters", boostedUntil: "2024-01-01T00:00:00Z"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(2, on: viewModel)

        XCTAssertEqual(viewModel.merchantSearchPrimaryResults.map(\.id), ["10", "11"])
    }

    func testBrowseOrderingShowsBoostedVisibleMerchantsFirstThenDistance() {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.userLocation = CLLocation(latitude: 36.17, longitude: -86.78)

        let nonBoostedNear = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 100, name: "Near", lat: 36.171, lon: -86.78, boostedUntil: nil)
        )
        let boostedFarther = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 101, name: "Boosted Farther", lat: 36.175, lon: -86.78, boostedUntil: "2099-01-01T00:00:00Z")
        )
        let boostedNearest = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 102, name: "Boosted Nearest", lat: 36.1705, lon: -86.78, boostedUntil: "2099-01-01T00:00:00Z")
        )
        let nonBoostedFar = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 103, name: "Far", lat: 36.19, lon: -86.78, boostedUntil: nil)
        )

        let ordered = [nonBoostedNear, boostedFarther, boostedNearest, nonBoostedFar]
            .sorted(by: viewModel.merchantBrowseSortOrder)

        XCTAssertEqual(ordered.map(\.id), ["102", "101", "100", "103"])
    }

    func testBrowseOrderingFallsBackToMapCenterAndIgnoresExpiredBoosts() {
        let repo = MockBTCMapRepository()
        let viewModel = ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: 0
        )
        viewModel.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 36.17, longitude: -86.78),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )

        let expiredCloser = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 200, name: "Expired", lat: 36.1705, lon: -86.78, boostedUntil: "2024-01-01T00:00:00Z")
        )
        let regularFarther = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(id: 201, name: "Regular", lat: 36.1715, lon: -86.78, boostedUntil: nil)
        )

        let ordered = [regularFarther, expiredCloser]
            .sorted(by: viewModel.merchantBrowseSortOrder)

        XCTAssertEqual(ordered.map(\.id), ["200", "201"])
    }

    private static func placeRecord(
        id: Int,
        name: String,
        lat: Double = 36.17,
        lon: Double = -86.78,
        boostedUntil: String? = nil
    ) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: lat,
            lon: lon,
            icon: nil,
            name: name,
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
            boostedUntil: boostedUntil,
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
            osmBrand: name,
            osmBrandWikidata: nil
        )
    }

    private func waitForRemoteQuery(on repo: MockBTCMapRepository) async {
        for _ in 0..<20 {
            if !repo.searchPlaceQueries.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func waitForPrimaryResultCount(_ count: Int, on viewModel: ContentViewModel) async {
        for _ in 0..<30 {
            if viewModel.merchantSearchPrimaryResults.count == count { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

private enum MockError: Error {
    case network
}

private final class MockBTCMapRepository: BTCMapRepositoryProtocol {
    var searchPlacesHandler: ((V4SearchQuery, @escaping (Result<[V4PlaceRecord], Error>) -> Void) -> Void)?
    private(set) var searchPlaceQueries: [V4SearchQuery] = []

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        searchPlaceQueries.append(query)
        if let searchPlacesHandler {
            searchPlacesHandler(query, completion)
        } else {
            completion(.success([]))
        }
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        completion(.failure(MockError.network))
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func loadCachedElements() -> [Element]? { [] }
    func hasCachedData() -> Bool { false }
    func refreshElements(completion: @escaping ([Element]?) -> Void) { completion([]) }
    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) { completion(.failure(MockError.network)) }
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) { completion(.success([])) }
}
