import Foundation
import Testing
import CoreLocation
import MapKit
@testable import bitlocal

@MainActor
@Suite(.serialized, .tags(.search))
struct MerchantSearchBehaviorTests {
    init() {
        UserDefaults.standard.set(true, forKey: "search_v2_hybrid")
    }

    @Test func twoCharacterQueryUsesLocalOnlyAndSkipsRemote() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Da Vinci Coffee"))
        ]

        viewModel.unifiedSearchText = "da"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        #expect(repo.searchPlaceQueries.count == 0)
        #expect(viewModel.merchantSearchPrimaryResults.map(\.id) == ["1"])
        #expect(viewModel.merchantSearchFreshResults.isEmpty)
    }

    @Test func nearbySearchUsesLocalOnlyAndSkipsRemoteTopUp() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = (1...8).map {
            V4PlaceToElementMapper.placeRecordToElement(
                Self.placeRecord(id: $0, name: "Cafe \($0)", icon: "local_cafe")
            )
        }

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(8, on: viewModel)

        #expect(repo.searchPlaceQueries.count == 0)
        #expect(viewModel.merchantSearchPrimaryResults.count == 8)
    }

    @Test func nearbySearchWaitsForDebounceBeforeUpdatingPrimaryResults() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo, unifiedSearchDebounceNanoseconds: 200_000_000)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Free Market"))
        ]

        viewModel.unifiedSearchText = "free"
        viewModel.performUnifiedSearch()

        #expect(viewModel.merchantSearchPrimaryResults.isEmpty)
        #expect(viewModel.merchantSearchIsWaitingForLocalDebounce)

        await waitForPrimaryResultCount(1, on: viewModel)

        #expect(viewModel.merchantSearchPrimaryResults.map(\.id) == ["1"])
        #expect(viewModel.merchantSearchIsWaitingForLocalDebounce == false)
    }

    @Test func coffeeQueryMatchesNearbyCategoryLocallyWithoutRemote() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 10, name: "Coffee House", icon: "local_cafe")),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 11, name: "Cafe Sats", icon: "local_cafe"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(2, on: viewModel)

        #expect(repo.searchPlaceQueries.count == 0)
        #expect(Set(viewModel.merchantSearchPrimaryResults.map(\.id)) == ["10", "11"])
        #expect(viewModel.merchantSearchFreshResults.isEmpty)
    }

    @Test func dessertQueryMatchesIceCreamLocallyWithoutRemote() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 21, name: "Koko's Ice Cream", icon: "icecream"))
        ]

        viewModel.unifiedSearchText = "dessert"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        #expect(viewModel.merchantSearchPrimaryResults.first?.id == "21")
        #expect(repo.searchPlaceQueries.count == 0)
    }

    @Test func nearbySearchRemoteFailureStateIsNotUsed() async {
        let repo = MockBTCMapRepository()
        repo.searchPlacesHandler = { _, completion in
            completion(.failure(MockError.network))
        }

        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 20, name: "Coffee House", icon: "local_cafe"))
        ]

        viewModel.unifiedSearchText = "coffee"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        #expect(viewModel.merchantSearchPrimaryResults.map(\.id) == ["20"])
        #expect(viewModel.merchantSearchFreshResults.isEmpty)
        #expect(viewModel.merchantSearchIsOfflineFallback == false)
        #expect(viewModel.merchantSearchError == nil)
        #expect(repo.searchPlaceQueries.count == 0)
    }

    @Test func mapElementsFollowDisplayedSearchResultsWhenSearching() {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        let cafe = Self.element(id: "1", icon: "local_cafe")
        let diner = Self.element(id: "2", icon: "restaurant")

        viewModel.mapDisplayMode = .merchants
        viewModel.unifiedSearchText = "coffee"
        viewModel.setAllElementsForTesting([cafe, diner])
        viewModel.setMerchantSearchMapResults([cafe])

        #expect(viewModel.mapElementsForCurrentDisplay.map(\.id) == ["1"])
    }

    @Test func mapElementsShowAllMerchantsWhenSearchIsTooShort() {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        let cafe = Self.element(id: "1", icon: "local_cafe")
        let diner = Self.element(id: "2", icon: "restaurant")

        viewModel.mapDisplayMode = .merchants
        viewModel.unifiedSearchText = "c"
        viewModel.setAllElementsForTesting([cafe, diner])
        viewModel.setMerchantSearchMapResults([cafe])

        #expect(viewModel.mapElementsForCurrentDisplay.map(\.id) == ["1", "2"])
    }

    @Test func clearingMapAnnotationsResetsCoordinatorCachesForSameResultReentry() {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        let coordinator = MapView.Coordinator(viewModel: viewModel, topPadding: 0, bottomPadding: 0)
        let mapView = MKMapView()
        let cafe = Self.element(id: "1", icon: "local_cafe")

        mapView.addAnnotation(Annotation(element: cafe))
        coordinator.lastElementsHash = [cafe].hashValue
        coordinator.lastVisibleElementIDs = [cafe.id]

        #expect(mapView.annotations.compactMap { ($0 as? Annotation)?.element?.id } == ["1"])

        #expect(coordinator.clearMerchantAnnotations(on: mapView))
        #expect(coordinator.lastElementsHash == nil)
        #expect(coordinator.lastVisibleElementIDs == [])
        #expect(mapView.annotations.compactMap { $0 as? Annotation }.isEmpty)
    }

    @Test func punctuationInsensitiveLocalMatchFindsSteakNShake() async {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.visibleElements = [
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 25770, name: "Steak 'n Shake"))
        ]

        viewModel.unifiedSearchText = "Steak n Shake"
        viewModel.performUnifiedSearch()
        await waitForPrimaryResultCount(1, on: viewModel)

        #expect(viewModel.merchantSearchPrimaryResults.first?.id == "25770")
    }

    @Test func categoryGroupResolutionCoversExistingAndExpandedIcons() {
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "local_cafe") == [.coffee])
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "local_grocery_store").contains(.groceries))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "local_atm").contains(.finance))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "content_cut").contains(.beauty))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "local_gas_station").contains(.auto))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "colorize").contains(.beauty))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "diamond").contains(.shopping))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "build").contains(.services))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "attach_money").contains(.finance))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "dentistry").contains(.health))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "cooking").contains(.food))
        #expect(ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: "tapas").contains(.food))
    }

    @Test func categoryGroupResolutionFallsBackToIconPlatformTag() {
        let element = Self.element(id: "fallback", icon: "restaurant")
        let elementWithTaggedIcon = Element(
            id: element.id,
            osmJSON: element.osmJSON,
            tags: Tags(
                category: nil,
                iconPlatform: "local_cafe",
                paymentCoinos: nil,
                paymentPouch: nil,
                boostExpires: nil,
                categoryPlural: nil,
                paymentProvider: nil,
                paymentURI: nil
            ),
            createdAt: element.createdAt,
            updatedAt: element.updatedAt,
            deletedAt: element.deletedAt,
            address: element.address,
            v4Metadata: nil
        )

        let groups = ElementCategorySymbols.merchantCategoryGroups(for: elementWithTaggedIcon)

        #expect(groups.contains(.coffee))
    }

    @Test func dynamicCategoryChipsAreSortedByVisibleCountAndCapped() {
        let elements = [
            Self.element(id: "1", icon: "local_cafe"),
            Self.element(id: "2", icon: "local_cafe"),
            Self.element(id: "3", icon: "restaurant"),
            Self.element(id: "4", icon: "local_atm"),
            Self.element(id: "5", icon: "hotel"),
            Self.element(id: "6", icon: "content_cut"),
            Self.element(id: "7", icon: "local_grocery_store"),
            Self.element(id: "8", icon: "build"),
            Self.element(id: "9", icon: "games")
        ]

        let chips = ElementCategorySymbols.merchantCategoryChips(for: elements, limit: 6)

        #expect(chips.count == 6)
        #expect(chips.first?.group == .coffee)
        #expect(chips.contains(where: { $0.group == .food }))
        #expect(chips.contains(where: { $0.group == .recreation && $0.count == 1 && chips.count > 6 }) == false)
    }

    @Test func browseOrderingShowsBoostedVisibleMerchantsFirstThenDistance() {
        let repo = MockBTCMapRepository()
        let viewModel = makeViewModel(repo: repo)
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

        #expect(ordered.map(\.id) == ["102", "101", "100", "103"])
    }

    private func makeViewModel(
        repo: MockBTCMapRepository,
        unifiedSearchDebounceNanoseconds: UInt64 = 400_000_000,
        unifiedSearchWorldwideDebounceNanoseconds: UInt64 = 700_000_000,
        localSearchWorldwideDebounceNanoseconds: UInt64 = 250_000_000
    ) -> ContentViewModel {
        ContentViewModel(
            btcMapRepository: repo,
            unifiedSearchDebounceNanoseconds: unifiedSearchDebounceNanoseconds,
            unifiedSearchWorldwideDebounceNanoseconds: unifiedSearchWorldwideDebounceNanoseconds,
            localSearchWorldwideDebounceNanoseconds: localSearchWorldwideDebounceNanoseconds
        )
    }

    private static func element(id: String, icon: String) -> Element {
        V4PlaceToElementMapper.placeRecordToElement(
            placeRecord(id: Int(id) ?? 0, name: "Place \(id)", icon: icon)
        )
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

    private func waitForRemoteQueryCount(_ count: Int, on repo: MockBTCMapRepository) async {
        for _ in 0..<40 {
            if repo.searchPlaceQueries.count >= count { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    private func waitForPrimaryResultCount(_ count: Int, on viewModel: ContentViewModel) async {
        for _ in 0..<40 {
            if viewModel.merchantSearchPrimaryResults.count == count { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func waitForFreshResultCount(_ count: Int, on viewModel: ContentViewModel) async {
        for _ in 0..<40 {
            if viewModel.merchantSearchFreshResults.count == count { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func waitForOfflineState(on viewModel: ContentViewModel) async {
        for _ in 0..<40 {
            if viewModel.merchantSearchIsOfflineFallback { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
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
    func lastSuccessfulSyncAtISO8601() -> String? { nil }
    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) { completion(.success([])) }
    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) { completion(.failure(MockError.network)) }
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) { completion(.success([])) }
}
