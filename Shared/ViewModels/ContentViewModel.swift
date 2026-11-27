//
//  ContentViewModel.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//

// ContentViewModel.swift

import SwiftUI
import Combine
import CoreLocation
import MapKit
import Foundation // for Debug logging
import Observation


@Observable
final class ContentViewModel: NSObject, CLLocationManagerDelegate, MKMapViewDelegate, MerchantSearchHost {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    var userLocation: CLLocation?
    var isUpdatingLocation = false
    /// Reverse-geocode results. Intentionally not observed — cache writes
    /// must not invalidate SwiftUI views.
    let geocodingCache = LRUCache<String, ReverseGeocodingCacheEntry>(maxSize: 1_000)
    /// Coarse spatial cache mapping ~11km regions to ISO country codes.
    /// Populated as a side effect of reverse geocoding; used to assign country
    /// codes to merchants that already have complete addresses without needing
    /// an additional geocode request.
    @ObservationIgnored var countryCodeByRegion: [String: String] = [:]
    /// Tracks which coarse regions already have a pending country-code geocode
    /// so we only fire one request per ~11 km area.
    @ObservationIgnored var pendingRegionCodeLookups: Set<String> = []
    var path: [BitLocalNavigationRoute] = []
    var selectedElement: Element?
    var deepLinkUnavailableState: DeepLinkUnavailableState?
    /// Row cell view-model cache. Intentionally `@ObservationIgnored` so lazy row
    /// hydration during SwiftUI `body` evaluation never triggers view invalidation.
    @ObservationIgnored var cellViewModels: [String: ElementCellViewModel] = [:]

    @MainActor
    func cachedCellViewModel(for element: Element) -> ElementCellViewModel {
        if let existing = cellViewModels[element.id] {
            let currentName = existing.element.displayNameForUI ?? ""
            let nextName = element.displayNameForUI ?? ""
            let currentUpdated = existing.element.updatedAt ?? ""
            let nextUpdated = element.updatedAt ?? ""
            if currentName == nextName && currentUpdated == nextUpdated {
                return existing
            }
        }
        let vm = ElementCellViewModel(
            element: element,
            userLocation: userLocation,
            viewModel: self
        )
        cellViewModels[element.id] = vm
        return vm
    }
    /// Observed merchant catalog snapshot. Mutations go through `merchantElementStore`.
    var allElements: [Element] = []
    /// Bumps when the merchant store mutates (for index invalidation / observers).
    var merchantStoreRevision: UInt64 = 0
    var visibleElements: [Element] = []
    var activeMerchantAlertDigest: CityDigest?
    var isLoading: Bool = false
    /// Last successful merchant dataset sync (from repository sync state).
    var lastSuccessfulSyncAt: Date?
    /// True when the most recent repository refresh returned no usable data while the store was empty.
    var merchantSyncFailed = false
    var merchantSyncStatusMessage: String?
    /// When true, Bitcoin ATMs are omitted from the merchant map and nearby list.
    var hideATMsFromMapAndList: Bool =
        UserDefaults.standard.bool(forKey: ContentViewModel.hideATMsFromMapAndListKey)
    var topPadding: CGFloat = 0
    /// Settled sheet bottom inset for map edge padding / camera math.
    /// Updated only when a detent selection settles — not during drag sampling.
    var bottomPadding: CGFloat = 0
    /// Leading column inset when the collapsible sheet is pinned to the leading edge
    /// (e.g. iPhone Duo unfolded landscape), so map centering avoids hiding pins under it.
    @ObservationIgnored var leadingSheetInset: CGFloat = 0
    /// Active layout shell derived from size classes + container geometry.
    @ObservationIgnored var layoutMode: AppLayoutMode = .compactSheet
    /// Live sheet geometry isolated from this object so detent drag does not
    /// invalidate views observing unrelated properties.
    let sheetGeometry = SheetGeometryModel()
    /// Non-observed target used to defer map invalidation until the system sheet
    /// finishes its release-to-detent animation.
    @ObservationIgnored var pendingSheetDetentHeight: CGFloat?
    var initialRegionSet = false // Track if initial region has been set
    var forceMapRefresh = false // Flag to force map annotation refresh
    var isReadyForPostOnboardingPresentation = true
    var selectionSource: SelectionSource = .unknown
    // Unified search state (owned by @Observable MerchantSearchController; forwarded for existing views)
    let merchantSearch: MerchantSearchController
    var unifiedSearchText: String {
        get { merchantSearch.unifiedSearchText }
        set { merchantSearch.unifiedSearchText = newValue }
    }
    var isSearchActive: Bool {
        get { merchantSearch.isSearchActive }
        set { merchantSearch.isSearchActive = newValue }
    }
    var selectedMerchantSearchScope: MerchantSearchScope {
        get { merchantSearch.selectedMerchantSearchScope }
        set { merchantSearch.selectedMerchantSearchScope = newValue }
    }
    var merchantSearchPrimaryResults: [Element] { merchantSearch.merchantSearchPrimaryResults }
    var merchantSearchMapResults: [Element] { merchantSearch.merchantSearchMapResults }
    var merchantSearchFreshResults: [V4PlaceRecord] { merchantSearch.merchantSearchFreshResults }
    var merchantSearchIsLoading: Bool { merchantSearch.merchantSearchIsLoading }
    var merchantSearchIsWaitingForLocalDebounce: Bool { merchantSearch.merchantSearchIsWaitingForLocalDebounce }
    var merchantSearchError: String? { merchantSearch.merchantSearchError }
    var merchantSearchIsOfflineFallback: Bool { merchantSearch.merchantSearchIsOfflineFallback }
    // Events
    var eventsIncludePast = false
    var eventsIsLoading = false
    var eventsError: String?
    var eventsResults: [V4EventRecord] = []
    var hasLoadedEvents = false
    // Area browser
    var areaBrowserAreas: [V3AreaRecord] = []
    var areaBrowserIsLoading = false
    var areaBrowserError: String?
    var communityMapAreas: [V2AreaRecord] = []
    var communityMapAreasIsLoading = false
    var hasLoadedCommunityMapAreas = false
    var selectedCommunityArea: V2AreaRecord?
    var presentedCommunityArea: V2AreaRecord?
    var communityMemberElements: [Element] = []
    var communityMemberElementIDs: Set<String> = []
    var communityMembersIsLoading = false
    var communityMembersError: String?
    var selectedAreaID: Int?
    var selectedAreaElementCount: Int?
    var hasLoadedAreas = false
    // Community map mode
    var mapDisplayMode: MapDisplayMode = .merchants
    @ObservationIgnored var cachedCommunityOverlays: [MKPolygon]?
    @ObservationIgnored var lastOverlayAreasHash: Int?
    @ObservationIgnored var cachedCommunityListAreas: [V2AreaRecord] = []
    @ObservationIgnored var lastCommunityListAreasHash: Int?
    @ObservationIgnored var cachedVisibleCommunityListAreas: [V2AreaRecord] = []
    @ObservationIgnored var lastVisibleCommunityListCacheKey: VisibleCommunityListCacheKey?
    @ObservationIgnored var communityGeoJSONHydrationInFlight = false
    @ObservationIgnored var requestedCommunityAreaDetailIDs = Set<Int>()
    /// Spatial index over merchant coordinates for community polygon membership.
    @ObservationIgnored var merchantSpatialIndex = MerchantSpatialIndex()
    @ObservationIgnored var merchantSpatialIndexSignature: Int = 0

    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder.shared
    let centerMapToCoordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()     // Publisher to center map to a coordinate
    let btcMapRepository: BTCMapRepositoryProtocol
    /// Identity-keyed merchant catalog (first extraction from ContentViewModel god-object).
    let merchantElementStore = MerchantElementStore()
    @ObservationIgnored private lazy var placeDeepLinkResolver = PlaceDeepLinkResolver(repository: btcMapRepository)
    
    // Startup state tracking
    var isInitialStartup = true
    var hasLoadedInitialData = false
    
    // App state tracking
    var appState: AppState = .active
    @ObservationIgnored private var hasBeenInactive = false
    
    @ObservationIgnored var lastCenteredCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private var geocodingCacheSaveTask: Task<Void, Never>?
    private let geocodingCacheFileURL = URL.cachesDirectory.appending(path: "geocoding_cache.json")
    
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var debounceTimer: AnyCancellable?
    @ObservationIgnored private var pendingDeepLink: AppDeepLink?
    @ObservationIgnored var latestCommunitySelectionRequestID = UUID()
    @ObservationIgnored var hasScheduledCommunityPrefetch = false
    @ObservationIgnored var communityPrefetchWorkItem: DispatchWorkItem?
    /// Fires when the next boosted merchant expires so pin tints update while the app stays active.
    @ObservationIgnored private var boostExpiryRefreshWorkItem: DispatchWorkItem?
    @ObservationIgnored var shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
    @ObservationIgnored var shouldReleasePostOnboardingPresentationAfterNextMapRender = false
    @ObservationIgnored var postOnboardingPresentationFallbackTask: Task<Void, Never>?
    @ObservationIgnored private var placeholderNameHydrationInFlight = Set<String>()
    @ObservationIgnored private var placeholderNameHydrationAttempted = Set<String>()
    @ObservationIgnored private var placeholderNameHydrationPendingResults: [String: Element] = [:]
    @ObservationIgnored private var placeholderNameHydrationApplyWorkItem: DispatchWorkItem?
    let cellViewModelCacheLimit = 250
    
    // Use a queue for thread-safe access to mapView
    private let mapViewQueue = DispatchQueue(label: "mapview.queue", qos: .userInitiated)
    @ObservationIgnored private var _mapView: MKMapView?
    
    var mapView: MKMapView? {
        get {
            return mapViewQueue.sync { _mapView }
        }
        set {
            mapViewQueue.sync { _mapView = newValue }
        }
    }
    
    enum AppState {
        case active, inactive, background
    }

    enum SelectionSource {
        case mapAnnotation
        case list
        case unknown
    }

    static let hideATMsFromMapAndListKey = "hideATMsFromMapAndList"
    
    override init() {
        self.btcMapRepository = BTCMapRepository.shared
        self.merchantSearch = MerchantSearchController(btcMapRepository: BTCMapRepository.shared)
        super.init()
        configureBindings()
    }

    init(
        btcMapRepository: BTCMapRepositoryProtocol,
        unifiedSearchDebounceNanoseconds: UInt64 = 400_000_000,
        unifiedSearchWorldwideDebounceNanoseconds: UInt64 = 700_000_000,
        localSearchWorldwideDebounceNanoseconds: UInt64 = 250_000_000
    ) {
        self.btcMapRepository = btcMapRepository
        self.merchantSearch = MerchantSearchController(
            btcMapRepository: btcMapRepository,
            unifiedSearchDebounceNanoseconds: unifiedSearchDebounceNanoseconds,
            unifiedSearchWorldwideDebounceNanoseconds: unifiedSearchWorldwideDebounceNanoseconds,
            localSearchWorldwideDebounceNanoseconds: localSearchWorldwideDebounceNanoseconds
        )
        super.init()
        configureBindings()
    }

    private func configureBindings() {
        loadGeocodingCache()
        refreshLastSuccessfulSyncAtFromRepository()
        locationManager.delegate = self
        setupCenterMapSubscription()
        merchantSearch.host = self
        visibleElementsSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] elements in
                guard let self else { return }
                let displayElements = self.elementsForDisplay(elements)
                Debug.logTiming("map", "visibleElementsSubject received -> count=\(displayElements.count) (raw=\(elements.count))")
                self.visibleElements = displayElements
                self.hydratePlaceholderNamesIfNeeded(in: displayElements)
                self.merchantSearch.refreshMerchantSearchFromVisibleElementsIfNeeded()
                self.pruneTransientMerchantCachesIfNeeded()
                // Visible pins only — off-screen expired boosts re-tint when recreated on pan.
                self.scheduleBoostExpiryMapRefreshIfNeeded(for: displayElements)
            }
            .store(in: &cancellables)
        mapStoppedMovingSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                Debug.logTiming(
                    "onboarding",
                    "mapStoppedMovingSubject received (settle=\(self.shouldReleasePostOnboardingPresentationAfterNextMapSettle), render=\(self.shouldReleasePostOnboardingPresentationAfterNextMapRender), ready=\(self.isReadyForPostOnboardingPresentation))"
                )
                guard self.shouldReleasePostOnboardingPresentationAfterNextMapSettle else { return }
                self.shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
                self.finishPostOnboardingPresentationIfNeeded()
            }
            .store(in: &cancellables)
    }

    func hydratePlaceholderNamesIfNeeded(in elements: [Element]) {
        let candidateIDs = elements.compactMap { element -> String? in
            let name = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard Element.isInvalidPrimaryName(name) else { return nil }
            return element.id
        }

        guard !candidateIDs.isEmpty else { return }
        let idsToHydrate = candidateIDs.filter {
            !placeholderNameHydrationInFlight.contains($0) && !placeholderNameHydrationAttempted.contains($0)
        }
        guard !idsToHydrate.isEmpty else { return }

        let batch = Array(idsToHydrate.prefix(20))
        batch.forEach {
            placeholderNameHydrationInFlight.insert($0)
            placeholderNameHydrationAttempted.insert($0)
        }

        for id in batch {
            btcMapRepository.fetchPlace(id: id) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.placeholderNameHydrationInFlight.remove(id)

                    guard case .success(let record) = result else {
                        // Still flush any other pending results when the batch drains.
                        if self.placeholderNameHydrationInFlight.isEmpty {
                            self.applyPendingPlaceholderNameHydrations()
                        }
                        return
                    }
                    let hydrated = V4PlaceToElementMapper.placeRecordToElement(record)
                    self.placeholderNameHydrationPendingResults[id] = hydrated

                    // Apply immediately when the batch finishes; otherwise coalesce
                    // rapid completions so we don't rebuild allElements per place.
                    if self.placeholderNameHydrationInFlight.isEmpty {
                        self.placeholderNameHydrationApplyWorkItem?.cancel()
                        self.applyPendingPlaceholderNameHydrations()
                    } else {
                        self.schedulePlaceholderNameHydrationApply()
                    }
                }
            }
        }
    }

    private func schedulePlaceholderNameHydrationApply() {
        placeholderNameHydrationApplyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyPendingPlaceholderNameHydrations()
        }
        placeholderNameHydrationApplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func applyPendingPlaceholderNameHydrations() {
        guard !placeholderNameHydrationPendingResults.isEmpty else { return }
        let pending = placeholderNameHydrationPendingResults
        placeholderNameHydrationPendingResults.removeAll(keepingCapacity: true)
        placeholderNameHydrationApplyWorkItem = nil

        upsertMerchants(Array(pending.values), forceMapRefresh: true)

        if let selectedID = selectedElement?.id, let updated = pending[selectedID] {
            selectedElement = updated
        }
        Debug.logTiming("data", "applied \(pending.count) placeholder name hydrations in one store update")
    }

    func requestPlaceholderNameHydration(for elements: [Element]) {
        hydratePlaceholderNamesIfNeeded(in: elements)
    }

    func setSelectionSource(_ source: SelectionSource) {
        selectionSource = source
    }

    func consumeSelectionSource() -> SelectionSource {
        let source = selectionSource
        selectionSource = .unknown
        return source
    }

    func handleIncomingURL(_ url: URL) {
        guard FeatureFlags.isSharePlaceLinksEnabled else { return }
        guard let deepLink = DeepLinkParser.parse(url: url) else {
            Debug.log("Ignored URL: \(url.absoluteString)")
            return
        }
        handleDeepLink(deepLink)
    }

    func handleIncomingUserActivity(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let webpageURL = activity.webpageURL else {
            return
        }
        handleIncomingURL(webpageURL)
    }

    func retryDeepLinkUnavailablePlaceLookup() {
        guard let state = deepLinkUnavailableState else { return }
        deepLinkUnavailableState = nil
        handleDeepLink(.place(id: state.placeID))
    }

    func openMapHomeFromDeepLinkUnavailable() {
        deepLinkUnavailableState = nil
        mapDisplayMode = .merchants
        path = []
        selectedElement = nil
    }

    func searchNearbyFromDeepLinkUnavailable() {
        deepLinkUnavailableState = nil
        mapDisplayMode = .merchants
        path = []
        selectedElement = nil
        isSearchActive = true
        unifiedSearchText = ""
        performUnifiedSearch()
        if let userLocation {
            centerMap(to: userLocation.coordinate, force: true)
        }
    }

    func resolvePendingDeepLinkIfNeeded() {
        guard appState == .active, let pendingDeepLink else { return }
        self.pendingDeepLink = nil
        handleDeepLink(pendingDeepLink, allowQueue: false)
    }
    
    func handleAppBecameActive() {
        Debug.log("App became active - previous state: \(appState)")
        let wasInactive = hasBeenInactive
        
        // Batch state changes to minimize UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.appState = .active
            self.hasBeenInactive = false
            self.resolvePendingDeepLinkIfNeeded()

            // Re-evaluate boost styling / annotation content after background time.
            if wasInactive {
                self.forceMapRefresh = true
            }
            self.scheduleBoostExpiryMapRefreshIfNeeded()
            
            // Only fetch if we were previously inactive/background and don't have data
            if wasInactive && (self.allElements.isEmpty || self.shouldRefreshAfterInactive()) {
                Debug.log("App returning from inactive state - refreshing data")
                self.refreshAfterInactive()
            }
        }
    }

    /// Schedules a map annotation refresh at the soonest future boost expiry so
    /// orange pins re-tint without requiring the app to go inactive first.
    /// Caps the delay at 1 hour and re-evaluates so long-lived boosts still get covered.
    private func scheduleBoostExpiryMapRefreshIfNeeded(for elements: [Element]? = nil) {
        boostExpiryRefreshWorkItem?.cancel()
        boostExpiryRefreshWorkItem = nil

        let source = elements ?? visibleElements
        let now = Date.now
        let soonestExpiry = source
            .compactMap(\.boostExpirationDate)
            .filter { $0 > now }
            .min()
        guard let soonestExpiry else { return }

        let delay = min(max(soonestExpiry.timeIntervalSince(now) + 0.25, 0.1), 3_600)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Debug.logMap("Boost expiry timer fired — refreshing map annotations")
            self.forceMapRefresh = true
            self.scheduleBoostExpiryMapRefreshIfNeeded()
        }
        boostExpiryRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func handleAppBecameInactive() {
        Debug.log("App became inactive")
        // Use async to batch potential state changes during rapid transitions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState = .inactive
            self.hasBeenInactive = true
        }
    }

    func handleAppEnteredBackground() {
        Debug.log("App entered background")
        // Background state change is final, update immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState = .background
            self.hasBeenInactive = true
            self.saveGeocodingCache()
        }
    }

    private func handleDeepLink(_ deepLink: AppDeepLink, allowQueue: Bool = true) {
        guard FeatureFlags.isSharePlaceLinksEnabled else { return }

        guard appState == .active else {
            if allowQueue {
                pendingDeepLink = deepLink
                Debug.log("Queued deep link until app is active")
            }
            return
        }

        switch deepLink {
        case .place(let placeID):
            handlePlaceDeepLink(placeID: placeID)
        }
    }

    private func handlePlaceDeepLink(placeID: String) {
        // Validate before touching map mode so a malformed link doesn't
        // yank the user out of communities view (resolver re-checks too).
        guard PlaceShareLinkBuilder.isValidPlaceID(placeID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            presentDeepLinkUnavailable(
                placeID: placeID,
                reason: PlaceDeepLinkResolver.invalidIdentifierReason()
            )
            return
        }

        mapDisplayMode = .merchants
        isSearchActive = false

        placeDeepLinkResolver.resolve(placeID: placeID) { [weak self] resolution in
            DispatchQueue.main.async {
                guard let self else { return }
                switch resolution {
                case .invalidIdentifier:
                    self.presentDeepLinkUnavailable(
                        placeID: placeID,
                        reason: PlaceDeepLinkResolver.invalidIdentifierReason()
                    )
                case .deleted:
                    self.presentDeepLinkUnavailable(
                        placeID: placeID,
                        reason: PlaceDeepLinkResolver.deletedPlaceReason()
                    )
                case .success(let element):
                    self.upsertElementIntoStore(element)
                    if let coordinate = element.mapCoordinate {
                        self.centerMap(to: coordinate, force: true)
                    }
                    self.setSelectionSource(.unknown)
                    self.selectedElement = element
                    self.path = [.place(element)]
                    self.deepLinkUnavailableState = nil
                case .failure(let message):
                    self.presentDeepLinkUnavailable(placeID: placeID, reason: message)
                }
            }
        }
    }

    private func presentDeepLinkUnavailable(placeID: String, reason: String) {
        Debug.log("Deep link place unavailable: id=\(placeID), reason=\(reason)")
        deepLinkUnavailableState = PlaceDeepLinkResolver.unavailableState(placeID: placeID)
    }

    private let geocodingCacheIOQueue = DispatchQueue(label: "app.bitlocal.geocodingCacheIO", qos: .utility)

    func scheduleGeocodingCacheSave() {
        geocodingCacheSaveTask?.cancel()
        geocodingCacheSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.saveGeocodingCache(synchronous: false)
        }
    }

    private func loadGeocodingCache() {
        let fileURL = geocodingCacheFileURL
        let cache = geocodingCache
        geocodingCacheIOQueue.async { [weak self] in
            guard let data = try? Data(contentsOf: fileURL) else { return }
            do {
                let decoded = try JSONDecoder().decode([String: ReverseGeocodingCacheEntry].self, from: data)
                cache.mergeMissingValues(decoded)
                Debug.log("Loaded geocoding cache: \(decoded.count) entries")
            } catch {
                do {
                    let legacy = try JSONDecoder().decode([String: Address].self, from: data)
                    let migrated = legacy.mapValues { ReverseGeocodingCacheEntry.forAddress($0) }
                    cache.mergeMissingValues(migrated)
                    Debug.log("Migrated geocoding cache: \(migrated.count) entries")
                    Task { @MainActor [weak self] in
                        self?.scheduleGeocodingCacheSave()
                    }
                } catch {
                    Debug.log("Failed to load geocoding cache: \(error.localizedDescription)")
                }
            }
        }
    }

    private func saveGeocodingCache(synchronous: Bool = true) {
        let values = geocodingCache.allValues()
        guard !values.isEmpty else { return }
        let fileURL = geocodingCacheFileURL
        let writeBlock: @Sendable () -> Void = {
            do {
                let data = try JSONEncoder().encode(values)
                try data.write(to: fileURL, options: [.atomic])
                Debug.log("Saved geocoding cache: \(values.count) entries")
            } catch {
                Debug.log("Failed to save geocoding cache: \(error.localizedDescription)")
            }
        }
        if synchronous {
            geocodingCacheIOQueue.sync(execute: writeBlock)
        } else {
            geocodingCacheIOQueue.async(execute: writeBlock)
        }
    }

    private func shouldRefreshAfterInactive() -> Bool {
        // Add logic to determine if refresh is needed
        // For example, check if last update was more than X minutes ago
        return true // For now, always refresh
    }

    private func refreshAfterInactive() {
        // Reset states that might be stale
        self.isLoading = false
        self.forceMapRefresh = true
        
        // Restart location if we don't have user location
        if self.userLocation == nil {
            self.requestWhenInUseLocationPermission()
        }
        
        // Fetch fresh data
        self.fetchElements()
    }
    
    // Request location
}
