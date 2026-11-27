import Foundation
import Testing
import CoreLocation
import MapKit
@testable import bitlocal

/// Exercises `MerchantSearchController` on its own, without a `ContentViewModel`.
@MainActor
@Suite(.serialized, .tags(.search))
final class MerchantSearchControllerTests {
    private let previousHybridFlag: Bool?

    init() {
        previousHybridFlag = UserDefaults.standard.object(forKey: "search_v2_hybrid") as? Bool
        UserDefaults.standard.set(true, forKey: "search_v2_hybrid")
    }

    deinit {
        if let previousHybridFlag {
            UserDefaults.standard.set(previousHybridFlag, forKey: "search_v2_hybrid")
        } else {
            UserDefaults.standard.removeObject(forKey: "search_v2_hybrid")
        }
    }

    @Test func localSearchFiltersHostVisibleElements() async {
        let service = MockSearchService()
        let host = FakeSearchHost()
        host.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Coffee House", icon: "local_cafe")),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 2, name: "Hardware Store"))
        ]
        let controller = makeController(service: service, host: host)

        controller.unifiedSearchText = "coffee"
        controller.performUnifiedSearch()
        await waitUntil { controller.merchantSearchPrimaryResults.count == 1 }

        #expect(controller.merchantSearchPrimaryResults.map(\.id) == ["1"])
        #expect(controller.merchantSearchIsWaitingForLocalDebounce == false)
        #expect(service.searchPlaceQueries.count == 0)
        #expect(host.hydratedPlaceholderBatches.isEmpty == false)
    }

    @Test func shortQueryClearsResultsWithoutSearching() {
        let service = MockSearchService()
        let host = FakeSearchHost()
        host.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Coffee House"))
        ]
        let controller = makeController(service: service, host: host)

        controller.unifiedSearchText = "c"
        controller.performUnifiedSearch()

        #expect(controller.merchantSearchPrimaryResults.isEmpty)
        #expect(controller.merchantSearchIsWaitingForLocalDebounce == false)
        #expect(host.pruneForceCalls == [true])
    }

    @Test func legacyWorldwideSearchQueriesRemoteAndPublishesFreshResults() async {
        UserDefaults.standard.set(false, forKey: "search_v2_hybrid")
        let remote = Self.placeRecord(id: 7, name: "Coffee Abroad", icon: "local_cafe")
        let service = MockSearchService()
        service.searchPlacesHandler = { _, completion in
            completion(.success([remote]))
        }
        let controller = makeController(service: service, host: FakeSearchHost())
        controller.selectedMerchantSearchScope = .worldwide

        controller.unifiedSearchText = "coffee"
        controller.performUnifiedSearch()
        await waitUntil { controller.merchantSearchFreshResults.count == 1 }

        #expect(service.searchPlaceQueries.isEmpty == false)
        #expect(controller.merchantSearchFreshResults.map(\.idString) == ["7"])
        #expect(controller.merchantSearchIsLoading == false)
        #expect(controller.merchantSearchError == nil)
    }

    @Test func legacyWorldwideSearchFailureFallsBackOffline() async {
        UserDefaults.standard.set(false, forKey: "search_v2_hybrid")
        let service = MockSearchService()
        service.searchPlacesHandler = { _, completion in
            completion(.failure(MockSearchError.network))
        }
        let controller = makeController(service: service, host: FakeSearchHost())
        controller.selectedMerchantSearchScope = .worldwide

        controller.unifiedSearchText = "coffee"
        controller.performUnifiedSearch()
        await waitUntil { controller.merchantSearchIsOfflineFallback }

        #expect(controller.merchantSearchIsOfflineFallback)
        #expect(controller.merchantSearchError != nil)
        #expect(controller.merchantSearchIsLoading == false)
    }

    @Test func resetForMerchantAlertDigestClearsSearchState() async {
        let host = FakeSearchHost()
        host.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Coffee House", icon: "local_cafe"))
        ]
        let controller = makeController(service: MockSearchService(), host: host)
        controller.isSearchActive = true
        controller.unifiedSearchText = "coffee"
        controller.performUnifiedSearch()
        await waitUntil { controller.merchantSearchPrimaryResults.count == 1 }
        controller.setMerchantSearchMapResults(controller.merchantSearchPrimaryResults)

        controller.resetForMerchantAlertDigest()

        #expect(controller.unifiedSearchText == "")
        #expect(controller.isSearchActive == false)
        #expect(controller.merchantSearchPrimaryResults.isEmpty)
        #expect(controller.merchantSearchMapResults.isEmpty)
        #expect(controller.localFilteredMerchants.isEmpty)
    }

    @Test func previewHydrationUpdatesResultsAndUpsertsIntoHost() async {
        UserDefaults.standard.set(false, forKey: "search_v2_hybrid")
        let partial = Self.placeRecord(id: 9, name: "Coffee Abroad", icon: "local_cafe")
        let service = MockSearchService()
        service.searchPlacesHandler = { _, completion in completion(.success([partial])) }
        service.fetchPlaceHandler = { _, completion in completion(.success(partial)) }
        let host = FakeSearchHost()
        let controller = makeController(service: service, host: host)
        controller.selectedMerchantSearchScope = .worldwide
        controller.unifiedSearchText = "coffee"
        controller.performUnifiedSearch()
        await waitUntil { controller.merchantSearchFreshResults.count == 1 }

        #expect(controller.shouldHydrateSearchResult(partial))
        controller.hydrateMerchantSearchPreviewIfNeeded(partial)
        await waitUntil { !host.upsertedElements.isEmpty }

        #expect(service.fetchPlaceIDs == ["9"])
        #expect(host.upsertedElements.map(\.id) == ["9"])
    }

    private func makeController(service: MockSearchService, host: FakeSearchHost) -> MerchantSearchController {
        let controller = MerchantSearchController(
            btcMapRepository: service,
            unifiedSearchDebounceNanoseconds: 0,
            unifiedSearchWorldwideDebounceNanoseconds: 0,
            localSearchWorldwideDebounceNanoseconds: 0
        )
        controller.host = host
        // Keep the host alive for the duration of the test.
        retainedHosts.append(host)
        return controller
    }

    private var retainedHosts: [FakeSearchHost] = []

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private static func placeRecord(
        id: Int,
        name: String,
        icon: String? = nil,
        lat: Double = 36.17,
        lon: Double = -86.78,
        boostedUntil: String? = nil
    ) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: lat,
            lon: lon,
            icon: icon,
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
}

private final class FakeSearchHost: MerchantSearchHost {
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.17, longitude: -86.78),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    var userLocation: CLLocation?
    var visibleElements: [Element] = []
    var mapDisplayMode: MapDisplayMode = .merchants
    var hasLoadedInitialData = true
    var allElements: [Element] = []
    private(set) var hydratedPlaceholderBatches: [[Element]] = []
    private(set) var pruneForceCalls: [Bool] = []
    private(set) var upsertedElements: [Element] = []

    func elementsForDisplay(_ elements: [Element]) -> [Element] { elements }

    func hydratePlaceholderNamesIfNeeded(in elements: [Element]) {
        hydratedPlaceholderBatches.append(elements)
    }

    func pruneTransientMerchantCachesIfNeeded(force: Bool) {
        pruneForceCalls.append(force)
    }

    func upsertElementIntoStore(_ element: Element) {
        upsertedElements.append(element)
    }
}

private enum MockSearchError: Error {
    case network
}

private final class MockSearchService: BTCMapSearchServiceProtocol {
    var searchPlacesHandler: ((V4SearchQuery, @escaping (Result<[V4PlaceRecord], Error>) -> Void) -> Void)?
    var fetchPlaceHandler: ((String, @escaping (Result<V4PlaceRecord, Error>) -> Void) -> Void)?
    private(set) var searchPlaceQueries: [V4SearchQuery] = []
    private(set) var fetchPlaceIDs: [String] = []

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        searchPlaceQueries.append(query)
        if let searchPlacesHandler {
            searchPlacesHandler(query, completion)
        } else {
            completion(.success([]))
        }
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        fetchPlaceIDs.append(id)
        if let fetchPlaceHandler {
            fetchPlaceHandler(id, completion)
        } else {
            completion(.failure(MockSearchError.network))
        }
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }
}
