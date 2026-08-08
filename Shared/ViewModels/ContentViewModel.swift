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

enum MapDisplayMode: String {
    case merchants
    case communities
}

enum MerchantSearchScope: String, CaseIterable, Identifiable {
    case onMap = "Nearby"
    case worldwide = "Worldwide"

    var id: String { rawValue }
}

enum SearchTextNormalizer {
    private static let allowedScalars = CharacterSet.alphanumerics.union(.whitespacesAndNewlines)

    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        var cleaned = String.UnicodeScalarView()
        cleaned.reserveCapacity(folded.unicodeScalars.count)

        for scalar in folded.unicodeScalars {
            if allowedScalars.contains(scalar) {
                cleaned.append(scalar)
            } else {
                cleaned.append(" ")
            }
        }

        return String(cleaned)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func matches(normalizedQuery: String, normalizedCandidate: String) -> Bool {
        guard !normalizedQuery.isEmpty, !normalizedCandidate.isEmpty else { return false }
        if normalizedCandidate.contains(normalizedQuery) { return true }

        let queryTokens = normalizedTokens(from: normalizedQuery)
        let candidateTokens = normalizedTokens(from: normalizedCandidate)
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return false }

        return queryTokens.allSatisfy { queryToken in
            candidateTokens.contains(where: { candidateToken in
                candidateToken.hasPrefix(queryToken)
            })
        }
    }

    private static func normalizedTokens(from normalizedText: String) -> [String] {
        normalizedText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

// DeepLinkUnavailableState lives in PlaceDeepLinkResolver.swift.
// MerchantSearchDocument/Match/Plan live in MerchantSearchEngine.swift.

private struct VisibleCommunityListCacheKey: Equatable {
    let areasHash: Int
    let mapMode: MapDisplayMode
    let selectedCommunityID: String?
    let viewportMinXBucket: Int
    let viewportMinYBucket: Int
    let viewportMaxXBucket: Int
    let viewportMaxYBucket: Int
}

final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    @Published var userLocation: CLLocation?
    @Published var isUpdatingLocation = false
    /// Reverse-geocode results. Intentionally not `@Published` — cache writes
    /// must not invalidate the entire `ContentViewModel` observation graph.
    let geocodingCache = LRUCache<String, ReverseGeocodingCacheEntry>(maxSize: 1_000)
    /// Coarse spatial cache mapping ~11km regions to ISO country codes.
    /// Populated as a side effect of reverse geocoding; used to assign country
    /// codes to merchants that already have complete addresses without needing
    /// an additional geocode request.
    var countryCodeByRegion: [String: String] = [:]
    /// Tracks which coarse regions already have a pending country-code geocode
    /// so we only fire one request per ~11 km area.
    var pendingRegionCodeLookups: Set<String> = []
    @Published var path: [Element] = []
    @Published var selectedElement: Element?
    @Published var deepLinkUnavailableState: DeepLinkUnavailableState?
    @Published var cellViewModels: [String: ElementCellViewModel] = [:]
    /// Published merchant catalog snapshot. Mutations go through `merchantElementStore`.
    @Published private(set) var allElements: [Element] = []
    /// Bumps when the merchant store mutates (for index invalidation / observers).
    @Published private(set) var merchantStoreRevision: UInt64 = 0
    @Published var visibleElements: [Element] = []
    @Published private(set) var activeMerchantAlertDigest: CityDigest?
    @Published var isLoading: Bool = false
    /// Last successful merchant dataset sync (from repository sync state).
    @Published private(set) var lastSuccessfulSyncAt: Date?
    /// True when the most recent repository refresh returned no usable data while the store was empty.
    @Published private(set) var merchantSyncFailed = false
    @Published private(set) var merchantSyncStatusMessage: String?
    /// When true, Bitcoin ATMs are omitted from the merchant map and nearby list.
    @Published private(set) var hideATMsFromMapAndList: Bool =
        UserDefaults.standard.bool(forKey: ContentViewModel.hideATMsFromMapAndListKey)
    @Published var topPadding: CGFloat = 0
    @Published var bottomPadding: CGFloat = 0
    @Published var liveBottomPadding: CGFloat = 0
    @Published var initialRegionSet = false // Track if initial region has been set
    @Published var forceMapRefresh = false // Flag to force map annotation refresh
    @Published var isReadyForPostOnboardingPresentation = true
    @Published var selectionSource: SelectionSource = .unknown
    // Unified search state
    @Published var unifiedSearchText = ""
    @Published var isSearchActive = false
    @Published private(set) var localFilteredMerchants: [Element] = []
    @Published var selectedMerchantSearchScope: MerchantSearchScope = .onMap
    @Published private(set) var merchantSearchPrimaryResults: [Element] = []
    @Published private(set) var merchantSearchMapResults: [Element] = []
    @Published private(set) var merchantSearchFreshResults: [V4PlaceRecord] = []
    @Published private(set) var merchantSearchNormalizedQuery = ""
    @Published var searchMatchingAreas: [V3AreaRecord] = []
    // Remote merchant search
    @Published var merchantSearchResults: [V4PlaceRecord] = []
    @Published var merchantSearchIsLoading = false
    @Published private(set) var merchantSearchIsWaitingForLocalDebounce = false
    @Published var merchantSearchError: String?
    @Published var merchantSearchIsOfflineFallback = false
    @Published var merchantSearchRadiusKM: Double = 20
    @Published var merchantSearchProviderFilter = ""
    // Events
    @Published var eventsIncludePast = false
    @Published var eventsIsLoading = false
    @Published var eventsError: String?
    @Published var eventsResults: [V4EventRecord] = []
    @Published var hasLoadedEvents = false
    // Area browser
    @Published var areaBrowserAreas: [V3AreaRecord] = []
    @Published var areaBrowserIsLoading = false
    @Published var areaBrowserError: String?
    @Published var communityMapAreas: [V2AreaRecord] = []
    @Published var communityMapAreasIsLoading = false
    @Published var hasLoadedCommunityMapAreas = false
    @Published var selectedCommunityArea: V2AreaRecord?
    @Published var presentedCommunityArea: V2AreaRecord?
    @Published var communityMemberElements: [Element] = []
    @Published var communityMemberElementIDs: Set<String> = []
    @Published var communityMembersIsLoading = false
    @Published var communityMembersError: String?
    @Published var selectedAreaID: Int?
    @Published var selectedAreaElementCount: Int?
    @Published var hasLoadedAreas = false
    // Community map mode
    @Published var mapDisplayMode: MapDisplayMode = .merchants
    private var cachedCommunityOverlays: [MKPolygon]?
    private var lastOverlayAreasHash: Int?
    private var cachedCommunityListAreas: [V2AreaRecord] = []
    private var lastCommunityListAreasHash: Int?
    private var cachedVisibleCommunityListAreas: [V2AreaRecord] = []
    private var lastVisibleCommunityListCacheKey: VisibleCommunityListCacheKey?
    private var communityGeoJSONHydrationInFlight = false
    private var requestedCommunityAreaDetailIDs = Set<Int>()
    /// Spatial index over merchant coordinates for community polygon membership.
    private var merchantSpatialIndex = MerchantSpatialIndex()
    private var merchantSpatialIndexSignature: Int = 0

    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder.shared
    let centerMapToCoordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()     // Publisher to center map to a coordinate
    private let btcMapRepository: BTCMapRepositoryProtocol
    /// Identity-keyed merchant catalog (first extraction from ContentViewModel god-object).
    private let merchantElementStore = MerchantElementStore()
    private lazy var placeDeepLinkResolver = PlaceDeepLinkResolver(repository: btcMapRepository)
    
    // Startup state tracking
    @Published var isInitialStartup = true
    @Published var hasLoadedInitialData = false
    
    // App state tracking
    @Published var appState: AppState = .active
    private var hasBeenInactive = false
    
    private var lastCenteredCoordinate: CLLocationCoordinate2D?
    private var geocodingCacheSaveWorkItem: DispatchWorkItem?
    private let geocodingCacheFileURL: URL = {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (cachesDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("geocoding_cache.json")
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?
    private var unifiedSearchDebounceTask: Task<Void, Never>?
    private var localMerchantSearchTask: Task<Void, Never>?
    private let unifiedSearchDebounceNanoseconds: UInt64
    private let unifiedSearchWorldwideDebounceNanoseconds: UInt64
    private let localSearchWorldwideDebounceNanoseconds: UInt64
    private var latestMerchantSearchRequestID = UUID()
    private var pendingDeepLink: AppDeepLink?
    private var merchantSearchAnchorCenter: CLLocationCoordinate2D?
    private var merchantSearchAnchorQuery = ""
    private let merchantSearchRequeryDistanceMeters: CLLocationDistance = 5_000
    private var latestCommunitySelectionRequestID = UUID()
    private var hasScheduledCommunityPrefetch = false
    private var communityPrefetchWorkItem: DispatchWorkItem?
    private var didRestorePersistedMerchantCategory = false
    /// Fires when the next boosted merchant expires so pin tints update while the app stays active.
    private var boostExpiryRefreshWorkItem: DispatchWorkItem?
    private var shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
    private var shouldReleasePostOnboardingPresentationAfterNextMapRender = false
    private var postOnboardingPresentationFallbackTask: Task<Void, Never>?
    private var placeholderNameHydrationInFlight = Set<String>()
    private var placeholderNameHydrationAttempted = Set<String>()
    private var placeholderNameHydrationPendingResults: [String: Element] = [:]
    private var placeholderNameHydrationApplyWorkItem: DispatchWorkItem?
    private var merchantSearchDocumentByID: [String: MerchantSearchDocument] = [:]
    private var merchantSearchDocumentSignatureByID: [String: String] = [:]
    private var merchantSearchLocalMatchScoreByID: [String: Int] = [:]
    private var merchantSearchStrongLocalHitCount = 0
    private var merchantSearchPreviewHydrationInFlight = Set<String>()
    private var merchantSearchLoadingTimeoutTask: Task<Void, Never>?
    private let merchantSearchV2HybridFlagKey = "search_v2_hybrid"
    private let cellViewModelCacheLimit = 250
    private let merchantSearchDocumentCacheLimit = 1_200
    
    // Use a queue for thread-safe access to mapView
    private let mapViewQueue = DispatchQueue(label: "mapview.queue", qos: .userInitiated)
    private var _mapView: MKMapView?
    
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

    private static let hideATMsFromMapAndListKey = "hideATMsFromMapAndList"
    
    override init() {
        self.btcMapRepository = BTCMapRepository.shared
        self.unifiedSearchDebounceNanoseconds = 400_000_000
        self.unifiedSearchWorldwideDebounceNanoseconds = 700_000_000
        self.localSearchWorldwideDebounceNanoseconds = 250_000_000
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
        self.unifiedSearchDebounceNanoseconds = unifiedSearchDebounceNanoseconds
        self.unifiedSearchWorldwideDebounceNanoseconds = unifiedSearchWorldwideDebounceNanoseconds
        self.localSearchWorldwideDebounceNanoseconds = localSearchWorldwideDebounceNanoseconds
        super.init()
        configureBindings()
    }

    private func configureBindings() {
        loadGeocodingCache()
        refreshLastSuccessfulSyncAtFromRepository()
        locationManager.delegate = self
        setupCenterMapSubscription()
        visibleElementsSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] elements in
                guard let self else { return }
                let displayElements = self.elementsForDisplay(elements)
                Debug.logTiming("map", "visibleElementsSubject received -> count=\(displayElements.count) (raw=\(elements.count))")
                self.visibleElements = displayElements
                self.hydratePlaceholderNamesIfNeeded(in: displayElements)
                self.refreshMerchantSearchFromVisibleElementsIfNeeded()
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

    private func hydratePlaceholderNamesIfNeeded(in elements: [Element]) {
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
        let now = Date()
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
                    self.path = [element]
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

    func scheduleGeocodingCacheSave() {
        geocodingCacheSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveGeocodingCache()
        }
        geocodingCacheSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func loadGeocodingCache() {
        guard let data = try? Data(contentsOf: geocodingCacheFileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: ReverseGeocodingCacheEntry].self, from: data)
            geocodingCache.setValues(decoded)
            Debug.log("Loaded geocoding cache: \(decoded.count) entries")
        } catch {
            do {
                let legacy = try JSONDecoder().decode([String: Address].self, from: data)
                let migrated = legacy.mapValues { ReverseGeocodingCacheEntry.forAddress($0) }
                geocodingCache.setValues(migrated)
                Debug.log("Migrated geocoding cache: \(migrated.count) entries")
                scheduleGeocodingCacheSave()
            } catch {
                Debug.log("Failed to load geocoding cache: \(error.localizedDescription)")
            }
        }
    }

    private func saveGeocodingCache() {
        let values = geocodingCache.allValues()
        guard !values.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(values)
            try data.write(to: geocodingCacheFileURL, options: [.atomic])
            Debug.log("Saved geocoding cache: \(values.count) entries")
        } catch {
            Debug.log("Failed to save geocoding cache: \(error.localizedDescription)")
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
    func requestWhenInUseLocationPermission() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            Debug.log("Requesting location permission - current auth status: \(self.locationManager.authorizationStatus.rawValue)")
            
            if self.locationManager.authorizationStatus == .notDetermined {
                self.locationManager.requestWhenInUseAuthorization()
            }
            
            if self.locationManager.authorizationStatus == .authorizedWhenInUse ||
               self.locationManager.authorizationStatus == .authorizedAlways {
                self.isUpdatingLocation = true
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    // Get latest location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            Debug.log("No location in didUpdateLocations")
            return
        }

        Debug.log("Location updated: \(latestLocation.coordinate)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Only center the map on the user's location if this is the first update (initial launch)
            if !self.initialRegionSet {
                self.centerMap(to: latestLocation.coordinate)
                self.initialRegionSet = true
            }

            if self.shouldReleasePostOnboardingPresentationAfterNextMapSettle {
                let didStartRecentering = self.centerMap(to: latestLocation.coordinate, force: true)
                if !didStartRecentering {
                    Debug.logTiming("onboarding", "location update recenter skipped; releasing immediately")
                    self.shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
                    self.finishPostOnboardingPresentationIfNeeded()
                }
            }

            // Always update userLocation and region for other uses, but don't recenter the map
            let currentSpan = self.region.span
            self.region = MKCoordinateRegion(center: latestLocation.coordinate, span: currentSpan)
            self.userLocation = latestLocation
            self.userLocationSubject.send(latestLocation)
        }
        manager.stopUpdatingLocation()
        isUpdatingLocation = false
    }
    
    // locationManager failure scenario (could not get user location)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Debug.log("LocationManager error: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.isUpdatingLocation = false
            self?.cancelPendingPostOnboardingMapPresentation()
        }
    }
    
    // Handle authorization changes
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Debug.log("Location authorization changed to: \(status.rawValue)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.userLocation == nil {
                    self.isUpdatingLocation = true
                    manager.startUpdatingLocation()
                }
            case .denied, .restricted:
                self.isUpdatingLocation = false
                Debug.log("Location access denied or restricted")
                self.cancelPendingPostOnboardingMapPresentation()
            case .notDetermined:
                Debug.log("Location authorization not determined")
            @unknown default:
                Debug.log("Unknown location authorization status")
            }
        }
    }
    
    // Calculate distance between element and user location
    func distanceInMiles(element: Element) -> Double? {
        guard let userLocation = userLocation,
              let coord = element.mapCoordinate else {
            return nil
        }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let distanceInMiles = distanceInMeters / 1609.34
        return distanceInMiles
    }

    // Returns a localized distance string based on user settings
    func localizedDistanceString(element: Element, distanceUnit: DistanceUnit) -> String? {
        guard let userLocation = userLocation, let coord = element.mapCoordinate else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let useMetric: Bool
        switch distanceUnit {
        case .auto:
            useMetric = Locale.current.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        if useMetric {
            let km = distanceInMeters / 1000
            return String(format: "%.1f km", km)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }
    
    // Determining distance from center
    func distanceFromCenter(location: CLLocationCoordinate2D) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let annotationLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        return centerLocation.distance(from: annotationLocation)
    }

    func distanceFromListFocus(element: Element) -> CLLocationDistance? {
        guard let coordinate = element.mapCoordinate else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if let focusCoordinate = listFocusCoordinate() {
            let focus = CLLocation(latitude: focusCoordinate.latitude, longitude: focusCoordinate.longitude)
            return focus.distance(from: target)
        }

        if let user = userLocation {
            return user.distance(from: target)
        }

        let mapCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return mapCenter.distance(from: target)
    }

    func distanceForMerchantBrowseOrder(element: Element) -> CLLocationDistance? {
        guard let coordinate = element.mapCoordinate else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if let userLocation {
            return userLocation.distance(from: target)
        }

        let mapCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return mapCenter.distance(from: target)
    }

    func merchantBrowseSortOrder(_ lhs: Element, _ rhs: Element) -> Bool {
        let lhsBoosted = lhs.isCurrentlyBoosted()
        let rhsBoosted = rhs.isCurrentlyBoosted()
        if lhsBoosted != rhsBoosted {
            return lhsBoosted && !rhsBoosted
        }

        let lhsDistance = distanceForMerchantBrowseOrder(element: lhs) ?? .greatestFiniteMagnitude
        let rhsDistance = distanceForMerchantBrowseOrder(element: rhs) ?? .greatestFiniteMagnitude
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsName = normalizedMerchantName(lhs.displayName ?? "")
        let rhsName = normalizedMerchantName(rhs.displayName ?? "")
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id < rhs.id
    }

    private func listFocusCoordinate() -> CLLocationCoordinate2D? {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let mapView = mapView else { return nil }

        let focusRect = mapListViewportRect(for: mapView)

        let centerPoint = CGPoint(x: focusRect.midX, y: focusRect.midY)
        return mapView.convert(centerPoint, toCoordinateFrom: mapView)
    }

    func effectiveIPhoneViewportBottomInset(mapHeight: CGFloat, enforceDefaultFloor: Bool = true) -> CGFloat {
        let defaultInset = mapHeight * 0.30
        let liveInset = enforceDefaultFloor ? max(bottomPadding, defaultInset) : max(bottomPadding, 0)
        let largeDetentThreshold = mapHeight * 0.70
        // Match map centering behavior: treat large detent as default viewport inset.
        if liveInset >= largeDetentThreshold {
            return defaultInset
        }
        return min(liveInset, mapHeight - 1)
    }

    func mapListViewportInsets(for mapView: MKMapView) -> UIEdgeInsets {
        let topInset = max(topPadding, 0)
        let bottomInset: CGFloat
        if UIDevice.current.userInterfaceIdiom == .phone {
            bottomInset = effectiveIPhoneViewportBottomInset(mapHeight: mapView.bounds.height)
        } else {
            bottomInset = 0
        }
        return UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
    }

    func mapListViewportRect(for mapView: MKMapView) -> CGRect {
        let rect = mapView.bounds.inset(by: mapListViewportInsets(for: mapView))
        guard rect.width > 1, rect.height > 1 else { return mapView.bounds }
        return rect
    }

    func mapRect(for viewportRect: CGRect, in mapView: MKMapView) -> MKMapRect {
        let topLeft = mapView.convert(
            CGPoint(x: viewportRect.minX, y: viewportRect.minY),
            toCoordinateFrom: mapView
        )
        let bottomRight = mapView.convert(
            CGPoint(x: viewportRect.maxX, y: viewportRect.maxY),
            toCoordinateFrom: mapView
        )
        let topLeftPoint = MKMapPoint(topLeft)
        let bottomRightPoint = MKMapPoint(bottomRight)

        return MKMapRect(
            x: min(topLeftPoint.x, bottomRightPoint.x),
            y: min(topLeftPoint.y, bottomRightPoint.y),
            width: abs(topLeftPoint.x - bottomRightPoint.x),
            height: abs(topLeftPoint.y - bottomRightPoint.y)
        )
    }

    private func merchantAlertElements(for digest: CityDigest) -> [Element] {
        let ids = digest.merchantIDs
        guard !ids.isEmpty else { return [] }

        return merchantElementStore.elements(ids: ids)
    }

    private func merchantAlertMissingIDs(for digest: CityDigest) -> [String] {
        let currentIDs = Set(allElements.map(\.id))
        return digest.merchantIDs.filter { !currentIDs.contains($0) }
    }

    private func fitMapToMerchantAlertElements(_ elements: [Element], animated: Bool) {
        guard !elements.isEmpty else {
            forceMapRefresh = true
            return
        }

        forceMapRefresh = true

        let coordinates = elements.compactMap(\.mapCoordinate)
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            centerMap(to: coordinate, force: true)
            return
        }

        guard let mapView else {
            let latitudes = coordinates.map(\.latitude)
            let longitudes = coordinates.map(\.longitude)
            let center = CLLocationCoordinate2D(
                latitude: (latitudes.min()! + latitudes.max()!) / 2,
                longitude: (longitudes.min()! + longitudes.max()!) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.4, 0.02),
                longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.4, 0.02)
            )
            let region = MKCoordinateRegion(center: center, span: span)
            updateMapRegion(center: region.center, span: region.span, animated: animated)
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }

        let edgePadding = mapListViewportInsets(for: mapView)
        DispatchQueue.main.async {
            mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: animated)
        }
    }
    
    // Zoom to element
    func zoomToElement(_ element: Element) {
        guard let mapView = mapView,
              let targetCoordinate = element.mapCoordinate else {
            Debug.log("Cannot zoom to element - mapView or coordinate missing")
            return
        }

        DispatchQueue.main.async {
            let zoomDistance = self.singlePassClusterRevealDistanceMeters(
                elementCoordinate: targetCoordinate,
                mapView: mapView
            )
            self.setDetentAwareZoom(
                center: targetCoordinate,
                distanceMeters: zoomDistance,
                mapView: mapView,
                animated: true
            )
            self.selectElementAfterClusterZoom(
                element,
                mapView: mapView,
                remainingAttempts: 5
            )
        }
    }

    private func selectElementAfterClusterZoom(
        _ element: Element,
        mapView: MKMapView,
        remainingAttempts: Int
    ) {
        guard remainingAttempts > 0 else {
            if let coordinate = element.mapCoordinate {
                centerMapWithoutZoom(to: coordinate, animated: true)
            }
            return
        }

        if let annotation = mapView.annotations.first(where: {
            ($0 as? Annotation)?.element?.id == element.id
        }) {
            let isClustered = isAnnotationClustered(annotation, on: mapView)
            if !isClustered {
                if let coordinate = element.mapCoordinate {
                    centerMapWithoutZoom(to: coordinate, animated: false)
                }
                mapView.selectAnnotation(annotation, animated: true)
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.selectElementAfterClusterZoom(
                element,
                mapView: mapView,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    func selectAnnotation(for element: Element, animated: Bool = true) {
        guard let mapView = mapView else { return }
        if let cluster = mapView.annotations
            .compactMap({ $0 as? MKClusterAnnotation })
            .first(where: { cluster in
                cluster.memberAnnotations.contains { member in
                    (member as? Annotation)?.element?.id == element.id
                }
            }) {
            mapView.selectAnnotation(cluster, animated: animated)
            return
        }
        if let annotation = mapView.annotations.first(where: {
            ($0 as? Annotation)?.element?.id == element.id
        }) {
            mapView.selectAnnotation(annotation, animated: animated)
        }
    }

    func centerMapWithoutZoom(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        guard let mapView = mapView else {
            updateMapRegion(center: coordinate, span: region.span, animated: animated)
            return
        }

        let currentSpan = mapView.region.span
        let adjustedCenterCoordinate = viewportAdjustedCenterCoordinate(
            for: coordinate,
            on: mapView
        )
        let adjustedRegion = MKCoordinateRegion(center: adjustedCenterCoordinate, span: currentSpan)

        let apply = {
            self.region = adjustedRegion
            mapView.setRegion(adjustedRegion, animated: animated)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func selectAnnotationForListSelection(
        _ element: Element,
        animated: Bool = true,
        allowCameraMovement: Bool = true,
        allowDirectSelectionRecentering: Bool = false
    ) {
        guard let mapView = mapView else { return }

        if let coordinate = element.mapCoordinate,
           let annotation = mapView.annotations.first(where: {
               ($0 as? Annotation)?.element?.id == element.id
           }) {
            let isClustered = isAnnotationClustered(annotation, on: mapView)
            if !isClustered {
                if allowDirectSelectionRecentering {
                    centerMapWithoutZoom(to: coordinate, animated: animated)
                }
                mapView.selectAnnotation(annotation, animated: animated)
                return
            }
        }

        if !allowCameraMovement {
            return
        }

        // If the specific annotation is not currently selectable (typically clustered),
        // force the zoom-reveal flow.
        zoomToElement(element)
    }

    private func isAnnotationClustered(_ annotation: MKAnnotation, on mapView: MKMapView) -> Bool {
        mapView.annotations
            .compactMap { $0 as? MKClusterAnnotation }
            .contains { cluster in
                cluster.memberAnnotations.contains { member in
                    member === annotation
                }
            }
    }

    private func viewportAdjustedCenterCoordinate(
        for targetCoordinate: CLLocationCoordinate2D,
        on mapView: MKMapView
    ) -> CLLocationCoordinate2D {
        let viewportRect = mapListViewportRect(for: mapView)
        let desiredPoint = CGPoint(x: viewportRect.midX, y: viewportRect.midY)
        let currentPoint = mapView.convert(targetCoordinate, toPointTo: mapView)
        let offsetX = currentPoint.x - desiredPoint.x
        let offsetY = currentPoint.y - desiredPoint.y
        let adjustedCenterPoint = CGPoint(
            x: mapView.bounds.midX + offsetX,
            y: mapView.bounds.midY + offsetY
        )
        return mapView.convert(adjustedCenterPoint, toCoordinateFrom: mapView)
    }

    private func setDetentAwareRegion(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        mapView: MKMapView,
        animated: Bool
    ) {
        let region = MKCoordinateRegion(center: center, span: span)
        let edgePadding = mapListViewportInsets(for: mapView)
        mapView.setVisibleMapRect(region.mapRect, edgePadding: edgePadding, animated: animated)
    }

    private func setDetentAwareZoom(
        center: CLLocationCoordinate2D,
        distanceMeters: CLLocationDistance,
        mapView: MKMapView,
        animated: Bool
    ) {
        let metersPerPoint = MKMapPointsPerMeterAtLatitude(center.latitude)
        let size = max(distanceMeters, 40) * metersPerPoint
        let mapPoint = MKMapPoint(center)
        let rect = MKMapRect(
            x: mapPoint.x - (size / 2),
            y: mapPoint.y - (size / 2),
            width: size,
            height: size
        )
        let edgePadding = mapListViewportInsets(for: mapView)
        mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: animated)
    }

    private func setDetentAwareCenterKeepingCurrentZoom(
        center: CLLocationCoordinate2D,
        mapView: MKMapView,
        animated: Bool
    ) {
        let adjustedCenter = viewportAdjustedCenterCoordinate(for: center, on: mapView)
        mapView.setRegion(
            MKCoordinateRegion(center: adjustedCenter, span: mapView.region.span),
            animated: animated
        )
    }

    private func singlePassClusterRevealDistanceMeters(
        elementCoordinate: CLLocationCoordinate2D,
        mapView: MKMapView
    ) -> CLLocationDistance {
        let targetLocation = CLLocation(latitude: elementCoordinate.latitude, longitude: elementCoordinate.longitude)
        let viewportWidthPoints = max(mapListViewportRect(for: mapView).width, 1)
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(elementCoordinate.latitude)
        let currentVisibleWidthMeters = max(mapView.visibleMapRect.width / mapPointsPerMeter, 80)

        let containingCluster = mapView.annotations
            .compactMap { $0 as? MKClusterAnnotation }
            .first { cluster in
                cluster.memberAnnotations.contains { member in
                    let c = member.coordinate
                    return abs(c.latitude - elementCoordinate.latitude) < 0.0000001 &&
                        abs(c.longitude - elementCoordinate.longitude) < 0.0000001
                }
            }

        var nearestNeighborMeters: CLLocationDistance?
        if let containingCluster {
            for member in containingCluster.memberAnnotations {
                let memberCoordinate = member.coordinate
                let sameTarget =
                    abs(memberCoordinate.latitude - elementCoordinate.latitude) < 0.0000001 &&
                    abs(memberCoordinate.longitude - elementCoordinate.longitude) < 0.0000001
                if sameTarget { continue }

                let memberLocation = CLLocation(
                    latitude: memberCoordinate.latitude,
                    longitude: memberCoordinate.longitude
                )
                let distance = targetLocation.distance(from: memberLocation)
                if distance <= 0.1 { continue }
                nearestNeighborMeters = min(nearestNeighborMeters ?? distance, distance)
            }
        }

        // Aim for clear on-screen separation between target and nearest neighbor in one move.
        let targetSeparationPoints: Double = 170
        let desiredWidthMeters: CLLocationDistance
        if let nearestNeighborMeters {
            let metersPerPoint = nearestNeighborMeters / targetSeparationPoints
            desiredWidthMeters = metersPerPoint * viewportWidthPoints
        } else {
            desiredWidthMeters = currentVisibleWidthMeters * 0.20
        }

        // TODO: For ultra-close pairs (~9m apart like 25975/25976), consider a
        // single conditional fallback pass with a tighter minimum only when still clustered.
        let zoomedWidthMeters = min(desiredWidthMeters, currentVisibleWidthMeters * 0.18)
        // Allow tighter zoom for extremely close merchants that otherwise stay clustered.
        return min(max(zoomedWidthMeters, 35), 2200)
    }
    
    private func setupCenterMapSubscription() {
        centerMapToCoordinateSubject
            .sink { [weak self] coordinate in
                guard let self = self, let mapView = self.mapView else {
                    Debug.log("Cannot center map - mapView missing")
                    return
                }
                let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                let region = MKCoordinateRegion(center: coordinate, span: newZoomLevel)
                let edgePadding = UIEdgeInsets(
                    top: topPadding + 10,
                    left: 20,
                    bottom: bottomPadding + 100,
                    right: 20
                )
                
                DispatchQueue.main.async {
                    mapView.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: region), animated: true)
                    mapView.setVisibleMapRect(region.mapRect, edgePadding: edgePadding, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    func centerMap(to coordinate: CLLocationCoordinate2D, force: Bool = false) -> Bool {
        guard let mapView = mapView else {
            Debug.log("Cannot center map - mapView is nil")
            return false
        }

        Debug.logTiming("map", "centerMap requested (force=\(force), lat=\(coordinate.latitude), lon=\(coordinate.longitude))")

        // Allow centering if:
        // 1. Force is true (user explicitly requested it)
        // 2. Never centered before
        // 3. Coordinate is significantly different
        // 4. Map's current center is far from target (user moved map)
        
        let shouldCenter: Bool
        
        if force, let lastCoord = lastCenteredCoordinate {
            let coordinateDistance = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))

            let currentCenter = mapView.region.center
            let currentCenterDistance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))

            let isAlreadyNearTarget = coordinateDistance <= 10 && currentCenterDistance <= 100
            if isAlreadyNearTarget {
                Debug.logTiming(
                    "map",
                    "centerMap skipped forced no-op (coord change: \(coordinateDistance)m, map drift: \(currentCenterDistance)m)"
                )
                return false
            }

            shouldCenter = true
            Debug.log("Centering map (forced) to coordinate: \(coordinate)")
        } else if force {
            shouldCenter = true
            Debug.log("Centering map (forced) to coordinate: \(coordinate)")
        } else if lastCenteredCoordinate == nil {
            shouldCenter = true
            Debug.log("Centering map (first time) to coordinate: \(coordinate)")
        } else if let lastCoord = lastCenteredCoordinate {
            let coordinateDistance = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            
            let currentCenter = mapView.region.center
            let currentCenterDistance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            
            // Center if coordinate changed significantly OR map was moved away from target
            shouldCenter = coordinateDistance > 10 || currentCenterDistance > 100
            
            if !shouldCenter {
                Debug.log("Skipping centerMap - coordinate similar (\(coordinateDistance)m) and map close to target (\(currentCenterDistance)m)")
                return false
            } else {
                Debug.log("Centering map to coordinate: \(coordinate) (coord change: \(coordinateDistance)m, map drift: \(currentCenterDistance)m)")
            }
        } else {
            shouldCenter = true
            Debug.log("Centering map to coordinate: \(coordinate)")
        }
        
        if shouldCenter {
            lastCenteredCoordinate = coordinate
            
            // Build a small MKMapRect around the user location:
            let mapPoint = MKMapPoint(coordinate)
            let metersPerPoint = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
            let mapSize = MKMapSize(width: 10000 * metersPerPoint, height: 10000 * metersPerPoint)
            let mapRect = MKMapRect(
                origin: MKMapPoint(x: mapPoint.x - mapSize.width / 2,
                                   y: mapPoint.y - mapSize.height / 2),
                size: mapSize
            )

            DispatchQueue.main.async {
                // If on iPad, center with NO horizontal inset—so the map pane centers user dot visually.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    let edgePadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                    mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: true)
                } else {
                    // iPhone: preserve your bottom‐sheet inset (unchanged)
                    let screenHeight = UIScreen.main.bounds.height
                    let bottomSheetHeight = screenHeight * (0.8 / 3.0)
                    let edgePadding = UIEdgeInsets(top: 0, left: 0, bottom: bottomSheetHeight, right: 0)
                    mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: true)
                }
            }
        }

        return shouldCenter
    }

    func preparePostOnboardingPresentation() {
        let authorizationStatus = locationManager.authorizationStatus
        Debug.logTiming("onboarding", "preparePostOnboardingPresentation(auth=\(authorizationStatus.rawValue), hasLocation=\(userLocation != nil))")

        if canPresentMainUIImmediatelyAfterOnboarding {
            Debug.logTiming(
                "onboarding",
                "post-onboarding gate skipped; map content already available (loaded=\(hasLoadedInitialData), visible=\(visibleElements.count), annotations=\(currentMerchantAnnotationCount))"
            )
            finishPostOnboardingPresentationImmediately()

            if let userLocation {
                centerMap(to: userLocation.coordinate, force: true)
            } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                requestWhenInUseLocationPermission()
            }
            return
        }

        schedulePostOnboardingPresentationFallback()

        if let userLocation {
            isReadyForPostOnboardingPresentation = false
            shouldReleasePostOnboardingPresentationAfterNextMapSettle = true
            shouldReleasePostOnboardingPresentationAfterNextMapRender = false
            Debug.logTiming("onboarding", "post-onboarding gate armed for existing user location")
            let didStartRecentering = centerMap(to: userLocation.coordinate, force: true)
            if !didStartRecentering {
                Debug.logTiming("onboarding", "post-onboarding recenter skipped; releasing immediately")
                shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
                finishPostOnboardingPresentationIfNeeded()
            }
            return
        }

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            isReadyForPostOnboardingPresentation = false
            shouldReleasePostOnboardingPresentationAfterNextMapSettle = true
            shouldReleasePostOnboardingPresentationAfterNextMapRender = false
            Debug.logTiming("onboarding", "post-onboarding gate armed while waiting for location update")
            requestWhenInUseLocationPermission()
            return
        }

        Debug.logTiming("onboarding", "post-onboarding gate not needed; releasing immediately")
        finishPostOnboardingPresentationIfNeeded()
    }

    func notifyPostOnboardingMapRenderFinished() {
        Debug.logTiming(
            "onboarding",
            "notifyPostOnboardingMapRenderFinished(armed=\(shouldReleasePostOnboardingPresentationAfterNextMapRender))"
        )
        guard shouldReleasePostOnboardingPresentationAfterNextMapRender else { return }
        Debug.logTiming("map", "post-onboarding map fully rendered")
        shouldReleasePostOnboardingPresentationAfterNextMapRender = false
        finishPostOnboardingPresentationIfNeeded()
    }

    func finishPostOnboardingPresentationIfNeeded() {
        Debug.logTiming(
            "onboarding",
            "finishPostOnboardingPresentationIfNeeded(settle=\(shouldReleasePostOnboardingPresentationAfterNextMapSettle), render=\(shouldReleasePostOnboardingPresentationAfterNextMapRender))"
        )
        guard !shouldReleasePostOnboardingPresentationAfterNextMapSettle,
              !shouldReleasePostOnboardingPresentationAfterNextMapRender else { return }
        postOnboardingPresentationFallbackTask?.cancel()
        postOnboardingPresentationFallbackTask = nil
        Debug.logTiming("onboarding", "post-onboarding presentation released")
        isReadyForPostOnboardingPresentation = true
        forceMapRefresh = true
    }

    private func cancelPendingPostOnboardingMapPresentation() {
        postOnboardingPresentationFallbackTask?.cancel()
        postOnboardingPresentationFallbackTask = nil
        Debug.logTiming(
            "onboarding",
            "cancelPendingPostOnboardingMapPresentation(settle=\(shouldReleasePostOnboardingPresentationAfterNextMapSettle), render=\(shouldReleasePostOnboardingPresentationAfterNextMapRender))"
        )
        shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
        shouldReleasePostOnboardingPresentationAfterNextMapRender = false
        isReadyForPostOnboardingPresentation = true
        forceMapRefresh = true
    }

    private func schedulePostOnboardingPresentationFallback() {
        postOnboardingPresentationFallbackTask?.cancel()
        postOnboardingPresentationFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            guard self.shouldReleasePostOnboardingPresentationAfterNextMapSettle
                    || self.shouldReleasePostOnboardingPresentationAfterNextMapRender else { return }
            Debug.logTiming(
                "onboarding",
                "post-onboarding presentation fallback released (settle=\(self.shouldReleasePostOnboardingPresentationAfterNextMapSettle), render=\(self.shouldReleasePostOnboardingPresentationAfterNextMapRender))"
            )
            self.cancelPendingPostOnboardingMapPresentation()
        }
    }

    private var currentMerchantAnnotationCount: Int {
        mapView?.annotations.compactMap { $0 as? Annotation }.count ?? 0
    }

    private var canPresentMainUIImmediatelyAfterOnboarding: Bool {
        guard hasLoadedInitialData else { return false }
        return !visibleElements.isEmpty || currentMerchantAnnotationCount > 0
    }

    private func finishPostOnboardingPresentationImmediately() {
        shouldReleasePostOnboardingPresentationAfterNextMapSettle = false
        shouldReleasePostOnboardingPresentationAfterNextMapRender = false
        finishPostOnboardingPresentationIfNeeded()
    }
    
    // Add a method for user-initiated centering (location button)
    func centerMapToUserLocation() {
        guard let userLocation = userLocation else {
            Debug.log("Cannot center to user location - location not available")
            return
        }
        
        Debug.log("User requested centering to location")
        centerMap(to: userLocation.coordinate, force: true)
    }
    
    // Update map region
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        let updatedSpan = span ?? region.span

        // If this is the first time setting the region, do it asynchronously on the main queue
        if !initialRegionSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.region = MKCoordinateRegion(center: center, span: updatedSpan)
                self.mapView?.setRegion(self.region, animated: animated)
                self.initialRegionSet = true
            }
        } else {
            // For subsequent changes, defer to avoid publishing during view updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.region = MKCoordinateRegion(center: center, span: updatedSpan)
                self.mapView?.setRegion(self.region, animated: animated)
            }
        }
    }

    // Keep view-model region in sync with MKMapView without issuing another map command.
    // This avoids camera/region feedback loops during animated map interactions.
    func syncRegionFromMap(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let newRegion = MKCoordinateRegion(center: center, span: span)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.region = newRegion
            if !self.initialRegionSet {
                self.initialRegionSet = true
            }
        }
    }
    
    // Deselect the currently selected annotation
    func deselectAnnotation() {
        selectedElement = nil
        DispatchQueue.main.async { [weak self] in
            self?.mapView?.selectedAnnotations.forEach { annotation in
                self?.mapView?.deselectAnnotation(annotation, animated: true)
            }
        }
    }

    // MARK: - Unified Search

    func performUnifiedSearch() {
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            MerchantSearchPersistence.clear()
        } else if let group = ElementCategorySymbols.resolvedCategoryGroup(
            forNormalizedQuery: SearchTextNormalizer.normalize(query)
        ), group.localizedLabel.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            // Only persist exact category chip labels — never free-text.
            MerchantSearchPersistence.saveCategoryGroup(group)
        }
        if merchantSearchV2HybridEnabled {
            performUnifiedSearchHybrid(query: query)
        } else {
            performUnifiedSearchLegacyRemotePrimary(query: query)
        }
    }

    /// Applies a category chip and persists the selection for return visits.
    func applyMerchantCategoryChip(_ chip: MerchantCategoryChip) {
        isSearchActive = true
        MerchantSearchPersistence.saveCategoryGroup(chip.group)
        unifiedSearchText = chip.localizedLabel
        performUnifiedSearch()
    }

    /// Clears search text and forgets any persisted category chip.
    func clearMerchantSearch(userInitiated: Bool = true) {
        if userInitiated {
            MerchantSearchPersistence.clear()
        }
        // Setting isSearchActive = false re-enters this method via the
        // bottom sheet's onChange; skip the redundant second search pass.
        let wasCleared = unifiedSearchText.isEmpty && !isSearchActive
        unifiedSearchText = ""
        isSearchActive = false
        guard !wasCleared else { return }
        performUnifiedSearch()
    }

    /// Restores the last category chip once after initial merchant data is ready.
    /// Free-text is intentionally not restored (avoids surprise worldwide queries).
    ///
    /// When the current viewport has no matches, keep trying on later map/list
    /// updates (do not set `didRestore…`) so cold-start over empty ocean can
    /// still restore after the user pans into a populated area.
    func restorePersistedMerchantCategoryIfNeeded() {
        guard !didRestorePersistedMerchantCategory else { return }
        guard mapDisplayMode == .merchants else { return }
        guard hasLoadedInitialData, !allElements.isEmpty else { return }
        // Local search filters the viewport (visibleElements); restoring before
        // any pins are on screen guarantees an empty "no results" takeover on
        // cold launch. Wait until the map has settled somewhere with merchants.
        guard !visibleElements.isEmpty else { return }
        guard unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // User already typed or selected something — never auto-restore over it.
            didRestorePersistedMerchantCategory = true
            return
        }
        guard let group = MerchantSearchPersistence.loadCategoryGroup() else {
            // Nothing to restore (missing/expired) — stop rechecking.
            didRestorePersistedMerchantCategory = true
            return
        }
        // Only take over the sheet when the category actually has matches in
        // the current viewport. Leave the flag false so a later pan/zoom can retry.
        let hasVisibleMatch = visibleElements.contains {
            ElementCategorySymbols.merchantCategoryGroups(for: $0).contains(group)
        }
        guard hasVisibleMatch else {
            Debug.logAPI("Deferred category chip restore (\(group.rawValue)): no visible matches in viewport")
            return
        }
        didRestorePersistedMerchantCategory = true
        isSearchActive = true
        unifiedSearchText = group.localizedLabel
        performUnifiedSearch()
        Debug.logAPI("Restored persisted merchant category chip: \(group.rawValue)")
    }

    private func refreshMerchantSearchFromVisibleElementsIfNeeded() {
        guard mapDisplayMode == .merchants else { return }
        guard merchantSearchV2HybridEnabled else { return }
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        localFilteredMerchants = filteredMerchantElements(
            in: visibleElements,
            normalizedQuery: normalizedQuery
        )
        merchantSearchPrimaryResults = localFilteredMerchants
        pruneFreshResultsAgainstPrimary()
        hydratePlaceholderNamesIfNeeded(in: Array(localFilteredMerchants.prefix(20)))
    }

    private func filteredMerchantElements(
        in source: [Element],
        normalizedQuery: String
    ) -> [Element] {
        let result = MerchantSearchEngine.filterElements(
            source,
            normalizedQuery: normalizedQuery,
            documentProvider: { [weak self] element in
                self?.merchantSearchDocument(for: element) ?? MerchantSearchEngine.document(for: element)
            }
        )
        merchantSearchLocalMatchScoreByID = result.scoresByID
        merchantSearchStrongLocalHitCount = result.strongHitCount

        return elementsForDisplay(result.elements.sorted(by: merchantElementSearchSortOrder))
    }

    private func performUnifiedSearchHybrid(query: String) {
        localMerchantSearchTask?.cancel()

        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchNormalizedQuery = ""
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            searchMatchingAreas = []
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            pruneTransientMerchantCachesIfNeeded(force: true)
            return
        }

        guard query.count >= 2 else {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchNormalizedQuery = ""
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            pruneTransientMerchantCachesIfNeeded(force: true)
            return
        }

        let normalizedQuery = SearchTextNormalizer.normalize(query)
        merchantSearchNormalizedQuery = normalizedQuery
        searchMatchingAreas = []
        scheduleLocalMerchantSearch(query: query, normalizedQuery: normalizedQuery)

        merchantSearchAnchorCenter = region.center
        merchantSearchAnchorQuery = query

        Debug.logAPI(
            "Merchant search queued (hybrid): query='\(query)', normalized='\(normalizedQuery)', scope=Nearby, local=\(localFilteredMerchants.count)"
        )
    }

    private func scheduleLocalMerchantSearch(query: String, normalizedQuery: String) {
        let source = visibleElements
        merchantSearchIsWaitingForLocalDebounce = true

        localMerchantSearchTask = Task { [weak self] in
            let debounceNanoseconds = self?.effectiveLocalMerchantSearchDebounceNanoseconds() ?? 0
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                self.merchantSearchIsWaitingForLocalDebounce = false
                let filtered = self.filteredMerchantElements(
                    in: source,
                    normalizedQuery: normalizedQuery
                )
                self.localFilteredMerchants = filtered
                self.merchantSearchPrimaryResults = filtered
                self.hydratePlaceholderNamesIfNeeded(in: Array(filtered.prefix(20)))
                self.pruneTransientMerchantCachesIfNeeded()
            }
        }
    }

    private func performUnifiedSearchLegacyRemotePrimary(query: String) {
        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            searchMatchingAreas = []
            clearMerchantSearchResults()
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        guard query.count >= 2 else {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            clearMerchantSearchResults()
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        searchMatchingAreas = []

        unifiedSearchDebounceTask?.cancel()
        merchantSearchResults = []
        merchantSearchFreshResults = []
        merchantSearchError = nil
        merchantSearchIsOfflineFallback = false

        merchantSearchAnchorCenter = region.center
        merchantSearchAnchorQuery = query

        Debug.logAPI("Merchant search queued (legacy): query='\(query)', center=(\(region.center.latitude), \(region.center.longitude)), radiusKM=\(merchantSearchRadiusKM)")

        unifiedSearchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: unifiedSearchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                merchantSearchText = query
                performRemoteMerchantSearch()
            }
        }
    }

    private func localMerchantSearchSource(for scope: MerchantSearchScope) -> [Element] {
        switch scope {
        case .onMap:
            return visibleElements
        case .worldwide:
            return []
        }
    }

    private func merchantSearchDocument(for element: Element) -> MerchantSearchDocument {
        let signature = MerchantSearchEngine.documentSignature(for: element)
        if merchantSearchDocumentSignatureByID[element.id] == signature,
           let cached = merchantSearchDocumentByID[element.id] {
            return cached
        }

        let document = MerchantSearchEngine.document(for: element)
        merchantSearchDocumentSignatureByID[element.id] = signature
        merchantSearchDocumentByID[element.id] = document
        return document
    }

    private func pruneTransientMerchantCachesIfNeeded(force: Bool = false) {
        let shouldPruneCellViewModels = force || cellViewModels.count > cellViewModelCacheLimit
        let shouldPruneSearchDocuments = force || merchantSearchDocumentByID.count > merchantSearchDocumentCacheLimit

        guard shouldPruneCellViewModels || shouldPruneSearchDocuments else { return }

        var retainedIDs: [String] = []
        retainedIDs.reserveCapacity(
            visibleElements.count +
            merchantSearchPrimaryResults.count +
            path.count +
            communityMemberElements.count + 1
        )

        func appendUnique(id: String?) {
            guard let id, !id.isEmpty, !retainedIDs.contains(id) else { return }
            retainedIDs.append(id)
        }

        visibleElements.forEach { appendUnique(id: $0.id) }
        merchantSearchPrimaryResults.forEach { appendUnique(id: $0.id) }
        path.forEach { appendUnique(id: $0.id) }
        communityMemberElements.prefix(100).forEach { appendUnique(id: $0.id) }
        appendUnique(id: selectedElement?.id)

        if shouldPruneCellViewModels {
            let keepIDs = Set(retainedIDs.prefix(cellViewModelCacheLimit))
            cellViewModels = cellViewModels.filter { keepIDs.contains($0.key) }
        }

        if shouldPruneSearchDocuments {
            let keepIDs = Set(retainedIDs.prefix(merchantSearchDocumentCacheLimit))
            merchantSearchDocumentByID = merchantSearchDocumentByID.filter { keepIDs.contains($0.key) }
            merchantSearchDocumentSignatureByID = merchantSearchDocumentSignatureByID.filter { keepIDs.contains($0.key) }
            merchantSearchLocalMatchScoreByID = merchantSearchLocalMatchScoreByID.filter { keepIDs.contains($0.key) }
        }
    }

    private func merchantSearchDocument(for record: V4PlaceRecord) -> MerchantSearchDocument {
        MerchantSearchEngine.document(for: record)
    }

    private func pruneFreshResultsAgainstPrimary() {
        let primaryIDs = Set(merchantSearchPrimaryResults.map(\.id))
        merchantSearchFreshResults = merchantSearchFreshResults.filter { !primaryIDs.contains($0.idString) }
    }

    func handleMerchantSearchMapRegionChange() {
        guard mapDisplayMode == .merchants else { return }
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        guard merchantSearchAnchorQuery == query,
              let anchor = merchantSearchAnchorCenter else {
            merchantSearchAnchorCenter = region.center
            merchantSearchAnchorQuery = query
            return
        }

        let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let currentLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let distance = anchorLocation.distance(from: currentLocation)
        guard distance >= merchantSearchRequeryDistanceMeters else { return }
        performUnifiedSearch()
    }

    /// Lazy-load events on first list appearance
    func ensureEventsLoaded() {
        guard !hasLoadedEvents else { return }
        hasLoadedEvents = true
        loadBTCMapEvents()
    }

    /// Lazy-load areas on first list appearance (needed for search suggestions)
    func ensureAreasLoaded() {
        if areaBrowserIsLoading { return }
        if hasLoadedAreas && !areaBrowserAreas.isEmpty { return }
        hasLoadedAreas = true
        loadAreaBrowserAreas()
    }

    /// Loads the BTC Map v2 areas feed used by btcmap.org's communities map.
    func ensureCommunityMapAreasLoaded() {
        ensureAreasLoaded() // v3 fallback can render local communities immediately.
        if communityMapAreasIsLoading { return }
        let currentCommunityGeoJSON = communityMapAreas.filter { $0.isCommunity && !$0.isDeleted && $0.geoJSON != nil }.count
        if hasLoadedCommunityMapAreas && !communityMapAreas.isEmpty {
            if currentCommunityGeoJSON >= 100 { return }
        }
        hasLoadedCommunityMapAreas = true
        communityMapAreasIsLoading = true
        loadCommunityMapAreasV2()
    }

    var mapElementsForCurrentDisplay: [Element] {
        switch mapDisplayMode {
        case .merchants:
            if let digest = activeMerchantAlertDigest {
                return elementsForDisplay(merchantAlertElements(for: digest))
            }
            let trimmedQuery = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.count >= 2 {
                return elementsForDisplay(merchantSearchMapResults)
            }
            return elementsForDisplay(allElements)
        case .communities:
            return selectedCommunityArea == nil ? [] : elementsForDisplay(communityMemberElements)
        }
    }

    var listElementsForCurrentDisplay: [Element] {
        if let digest = activeMerchantAlertDigest, mapDisplayMode == .merchants {
            return elementsForDisplay(merchantAlertElements(for: digest))
        }
        return visibleElements
    }

    /// Applies user display preferences (currently: optional ATM hiding).
    func elementsForDisplay(_ elements: [Element]) -> [Element] {
        guard hideATMsFromMapAndList else { return elements }
        return elements.filter { !$0.isATM }
    }

    func setHideATMsFromMapAndList(_ hide: Bool) {
        guard hideATMsFromMapAndList != hide else { return }
        hideATMsFromMapAndList = hide
        UserDefaults.standard.set(hide, forKey: Self.hideATMsFromMapAndListKey)

        if hide {
            visibleElements = visibleElements.filter { !$0.isATM }
            localFilteredMerchants = localFilteredMerchants.filter { !$0.isATM }
            merchantSearchPrimaryResults = merchantSearchPrimaryResults.filter { !$0.isATM }
            merchantSearchMapResults = merchantSearchMapResults.filter { !$0.isATM }
            communityMemberElements = communityMemberElements.filter { !$0.isATM }
        } else if !unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Re-run search so ATMs can reappear in results without a map pan.
            performUnifiedSearch()
        }

        forceMapRefresh = true
    }

    var isShowingMerchantAlertDigest: Bool {
        activeMerchantAlertDigest != nil
    }

    func setMerchantSearchMapResults(_ results: [Element]) {
        let filtered = elementsForDisplay(results)
        let currentIDs = merchantSearchMapResults.map(\.id)
        let newIDs = filtered.map(\.id)
        guard currentIDs != newIDs else { return }
        merchantSearchMapResults = filtered
    }

    func clearMerchantSearchMapResults() {
        guard !merchantSearchMapResults.isEmpty else { return }
        merchantSearchMapResults = []
    }

    func activateMerchantAlertDigest(_ digest: CityDigest) {
        activeMerchantAlertDigest = digest
        mapDisplayMode = .merchants
        unifiedSearchText = ""
        isSearchActive = false
        localFilteredMerchants = []
        merchantSearchPrimaryResults = []
        merchantSearchMapResults = []
        merchantSearchFreshResults = []
        merchantSearchNormalizedQuery = ""
        selectedCommunityArea = nil
        presentedCommunityArea = nil
        communityMemberElements = []
        communityMemberElementIDs = []
        path = []
        deselectAnnotation()

        let elements = merchantAlertElements(for: digest)
        fitMapToMerchantAlertElements(elements, animated: true)

        let missingIDs = merchantAlertMissingIDs(for: digest)
        guard !missingIDs.isEmpty else { return }

        Debug.log("Merchant alert digest missing \(missingIDs.count) merchant(s) locally; refreshing merchant dataset")
        fetchElements { [weak self] in
            guard let self else { return }
            guard self.activeMerchantAlertDigest?.id == digest.id else { return }

            let refreshedElements = self.merchantAlertElements(for: digest)
            self.fitMapToMerchantAlertElements(refreshedElements, animated: true)
        }
    }

    func clearMerchantAlertDigest() {
        guard activeMerchantAlertDigest != nil else { return }
        activeMerchantAlertDigest = nil
        forceMapRefresh = true
    }

#if DEBUG
    func setAllElementsForTesting(_ elements: [Element]) {
        replaceMerchantCatalog(elements, forceMapRefresh: false)
    }
#endif

    var isShowingCommunityMembersOnMap: Bool {
        mapDisplayMode == .communities && selectedCommunityArea != nil
    }

    var communityListAreas: [V2AreaRecord] {
        let areas = effectiveCommunityAreasForDisplay
        let currentHash = areas.hashValue
        if let lastCommunityListAreasHash, lastCommunityListAreasHash == currentHash {
            return cachedCommunityListAreas
        }

        let sorted = areas.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        cachedCommunityListAreas = sorted
        lastCommunityListAreasHash = currentHash
        return sorted
    }

    var visibleCommunityListAreas: [V2AreaRecord] {
        let allAreas = communityListAreas
        guard mapDisplayMode == .communities,
              selectedCommunityArea == nil,
              let mapView = mapView else {
            return allAreas
        }

        let visibleRect = mapRect(for: mapView.bounds, in: mapView)
        let viewportBucketScale = 1_000.0
        let cacheKey = VisibleCommunityListCacheKey(
            areasHash: allAreas.hashValue,
            mapMode: mapDisplayMode,
            selectedCommunityID: selectedCommunityArea?.id,
            viewportMinXBucket: Int((visibleRect.minX / viewportBucketScale).rounded()),
            viewportMinYBucket: Int((visibleRect.minY / viewportBucketScale).rounded()),
            viewportMaxXBucket: Int((visibleRect.maxX / viewportBucketScale).rounded()),
            viewportMaxYBucket: Int((visibleRect.maxY / viewportBucketScale).rounded())
        )
        if lastVisibleCommunityListCacheKey == cacheKey {
            return cachedVisibleCommunityListAreas
        }

        var visibleIDs = Set<String>()

        for polygon in communityOverlays {
            let areaID = (polygon.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !areaID.isEmpty, polygon.boundingMapRect.intersects(visibleRect) else { continue }
            visibleIDs.insert(areaID)
        }

        let visibleAreas = allAreas.filter { visibleIDs.contains($0.id) }
        cachedVisibleCommunityListAreas = visibleAreas
        lastVisibleCommunityListCacheKey = cacheKey
        return visibleAreas
    }

    func communityArea(withID id: String) -> V2AreaRecord? {
        communityMapAreas.first { $0.id == id }
    }

    private func loadCommunityMapAreasV2() {
        let loader = CommunityAreasLoader(repository: btcMapRepository)
        loader.loadAll(initialAnchor: "2022-01-01T00:00:00.000Z") { [weak self] areas, isComplete, error in
            guard let self else { return }
            if let error {
                self.communityMapAreasIsLoading = false
                self.hasLoadedCommunityMapAreas = false
                Debug.logAPI("loadCommunityMapAreasV2 failed: \(error.localizedDescription)")
                return
            }

            // Publish progressively so visible communities can appear immediately.
            self.communityMapAreas = areas
            self.forceMapRefresh = true
            if isComplete {
                self.communityMapAreasIsLoading = false
            }
        }
    }

    // MARK: - Community Map Mode

    var communityOverlays: [MKPolygon] {
        let currentHash = effectiveCommunityAreasForDisplay.hashValue
        if let cached = cachedCommunityOverlays, lastOverlayAreasHash == currentHash { return cached }

        var polygons: [MKPolygon] = []
        for area in effectiveCommunityAreasForDisplay {
            guard let geoJSON = area.geoJSON else { continue }
            for feature in geoJSON.features {
                let geom = feature.geometry
                switch geom.coordinates {
                case .polygon(let rings):
                    polygons.append(contentsOf: mkPolygons(from: rings, title: area.displayName, identifier: area.id))
                case .multiPolygon(let multiRings):
                    for rings in multiRings {
                        polygons.append(contentsOf: mkPolygons(from: rings, title: area.displayName, identifier: area.id))
                    }
                }
            }
        }

        cachedCommunityOverlays = polygons
        lastOverlayAreasHash = currentHash
        return polygons
    }

    private var effectiveCommunityAreasForDisplay: [V2AreaRecord] {
        let v2Areas = communityMapAreas.filter { $0.isCommunity && !$0.isDeleted && $0.geoJSON != nil }
        let fallbackAreas = fallbackCommunityAreasFromV3()

        // While v2 is still loading, keep fallback communities visible and layer in v2 progressively.
        if communityMapAreasIsLoading {
            var merged = IdentifiableIndex.byID(fallbackAreas)
            for area in v2Areas { merged[area.id] = area }
            return Array(merged.values)
        }

        return v2Areas.isEmpty ? fallbackAreas : v2Areas
    }

    private func fallbackCommunityAreasFromV3() -> [V2AreaRecord] {
        areaBrowserAreas
            .filter { area in
                area.tags?["type"] == "community" &&
                area.geoJSON != nil
            }
            .map { area in
                V2AreaRecord(
                    id: String(area.id),
                    tags: area.tags,
                    createdAt: nil,
                    updatedAt: area.updatedAt,
                    deletedAt: nil,
                    geoJSON: area.geoJSON
                )
            }
    }

    private func mkPolygons(from rings: [[[Double]]], title: String, identifier: String?) -> [MKPolygon] {
        guard let outerRing = rings.first, !outerRing.isEmpty else { return [] }
        let coords = outerRing.compactMap { point -> CLLocationCoordinate2D? in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
        guard coords.count >= 3 else { return [] }

        let splitRings = splitRingAtAntimeridian(coords)
        return splitRings.compactMap { ring in
            guard ring.count >= 3 else { return nil }
            var mutableRing = ring
            let polygon = MKPolygon(coordinates: &mutableRing, count: mutableRing.count)
            polygon.title = title
            polygon.subtitle = identifier
            return polygon
        }
    }

    private func splitRingAtAntimeridian(_ ring: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        var points = ring
        if let first = points.first, let last = points.last, coordinatesNearlyEqual(first, last) {
            points.removeLast()
        }
        guard points.count >= 3 else { return [] }

        var fragments: [[CLLocationCoordinate2D]] = [[points[0]]]

        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let delta = b.longitude - a.longitude

            if abs(delta) <= 180 {
                appendCoordinateIfNeeded(b, to: &fragments[fragments.count - 1])
                continue
            }

            // Crossing the antimeridian; split at +/-180 and continue on the opposite seam.
            let crossesEastward = delta < -180 // e.g. 170 -> -170 (across +180)
            let seamCurrent: CLLocationDegrees = crossesEastward ? 180 : -180
            let seamNext: CLLocationDegrees = crossesEastward ? -180 : 180
            let adjustedBLon = crossesEastward ? (b.longitude + 360) : (b.longitude - 360)
            let denominator = adjustedBLon - a.longitude

            if denominator == 0 {
                appendCoordinateIfNeeded(b, to: &fragments[fragments.count - 1])
                continue
            }

            let t = max(0, min(1, (seamCurrent - a.longitude) / denominator))
            let seamLat = a.latitude + ((b.latitude - a.latitude) * t)
            let pointOnCurrentSeam = CLLocationCoordinate2D(latitude: seamLat, longitude: seamCurrent)
            let pointOnNextSeam = CLLocationCoordinate2D(latitude: seamLat, longitude: seamNext)

            appendCoordinateIfNeeded(pointOnCurrentSeam, to: &fragments[fragments.count - 1])

            var nextFragment: [CLLocationCoordinate2D] = [pointOnNextSeam]
            appendCoordinateIfNeeded(b, to: &nextFragment)
            fragments.append(nextFragment)
        }

        return fragments.compactMap { fragment in
            var cleaned = collapseConsecutiveDuplicates(fragment)
            guard cleaned.count >= 3 else { return nil }
            if let first = cleaned.first, let last = cleaned.last, !coordinatesNearlyEqual(first, last) {
                cleaned.append(first)
            }
            // MKPolygon accepts open rings too, but closing produces more stable seam splits.
            guard cleaned.count >= 4 else { return nil }
            return cleaned
        }
    }

    private func appendCoordinateIfNeeded(_ coordinate: CLLocationCoordinate2D, to ring: inout [CLLocationCoordinate2D]) {
        if let last = ring.last, coordinatesNearlyEqual(last, coordinate) { return }
        ring.append(coordinate)
    }

    private func collapseConsecutiveDuplicates(_ ring: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for coordinate in ring {
            appendCoordinateIfNeeded(coordinate, to: &result)
        }
        return result
    }

    private func coordinatesNearlyEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.000001
    }

    func toggleMapMode() {
        let start = CFAbsoluteTimeGetCurrent()
        let switchingToCommunities = mapDisplayMode == .merchants
        Debug.log("⏱ toggleMapMode: START → switching to \(switchingToCommunities ? "communities" : "merchants")")

        // Reset community state only when the values actually differ from defaults,
        // avoiding unnecessary @Published emissions.
        if selectedCommunityArea != nil { selectedCommunityArea = nil }
        if !communityMemberElements.isEmpty { communityMemberElements = [] }
        if !communityMemberElementIDs.isEmpty { communityMemberElementIDs = [] }
        if communityMembersError != nil { communityMembersError = nil }
        if communityMembersIsLoading { communityMembersIsLoading = false }

        let afterReset = CFAbsoluteTimeGetCurrent()
        Debug.log("⏱ toggleMapMode: resets done in \(String(format: "%.1f", (afterReset - start) * 1000))ms")

        // Flip mode and refresh in a single pass.
        mapDisplayMode = switchingToCommunities ? .communities : .merchants
        forceMapRefresh = true

        let afterFlip = CFAbsoluteTimeGetCurrent()
        Debug.log("⏱ toggleMapMode: mode flipped in \(String(format: "%.1f", (afterFlip - afterReset) * 1000))ms")

        if switchingToCommunities {
            ensureCommunityMapAreasLoaded()
            Debug.log("⏱ toggleMapMode: ensureCommunityMapAreasLoaded in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - afterFlip) * 1000))ms")
        }

        Debug.log("⏱ toggleMapMode: TOTAL \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
    }

    func selectCommunity(_ area: V2AreaRecord, presentDetail: Bool = true) {
        ensureAreasLoaded()
        selectedCommunityArea = area
        if presentDetail {
            presentedCommunityArea = area
        }
        communityMembersError = nil
        communityMembersIsLoading = true
        communityMemberElements = []
        communityMemberElementIDs = []
        latestCommunitySelectionRequestID = UUID()
        let requestID = latestCommunitySelectionRequestID

        fitMapToCommunity(area, animated: true)

        // Match BTCMap community page behavior: derive members by polygon containment
        // against the synced v4 places dataset. Fall back to v3 area-elements only when
        // polygon data is unavailable.
        if let polygonMembers = communityMembersFromPolygon(for: area), !polygonMembers.isEmpty {
            communityMemberElements = polygonMembers
            communityMemberElementIDs = Set(polygonMembers.map(\.id))
            communityMembersError = nil
            let placeholderIDs = polygonMembers.compactMap { member -> String? in
                let name = member.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Element.isInvalidPrimaryName(name) ? member.id : nil
            }
            if placeholderIDs.isEmpty {
                communityMembersIsLoading = false
            } else {
                communityMembersIsLoading = true
                hydrateMissingCommunityMembers(
                    missingIDs: placeholderIDs,
                    seedMembers: polygonMembers,
                    requestID: requestID
                )
            }
            forceMapRefresh = true
            return
        }

        // V2 area IDs are slugs (e.g. "bitcoin-cordoba"); resolve the matching
        // V3 numeric ID via url_alias so we can query the area-elements endpoint.
        resolveV3AreaID(for: area) { [weak self] resolvedID in
            guard let self, let resolvedID else {
                DispatchQueue.main.async {
                    self?.communityMembersIsLoading = false
                    self?.communityMembersError = "Could not resolve community"
                    self?.forceMapRefresh = true
                }
                return
            }
            self.fetchCommunityMembers(areaID: resolvedID, requestID: requestID)
        }
    }

    private func fitMapToCommunity(_ area: V2AreaRecord, animated: Bool) {
        guard let mapView = mapView else {
            if let region = mapRegion(forCommunityArea: area) {
                updateMapRegion(center: region.center, span: region.span, animated: animated)
            }
            return
        }

        if let boundsRect = communityBoundingMapRect(for: area) {
            var edgePadding = mapListViewportInsets(for: mapView)
            edgePadding.top += 12
            edgePadding.left += 20
            edgePadding.bottom += 20
            edgePadding.right += 20

            DispatchQueue.main.async {
                mapView.setVisibleMapRect(boundsRect, edgePadding: edgePadding, animated: animated)
            }
            return
        }

        if let region = mapRegion(forCommunityArea: area) {
            updateMapRegion(center: region.center, span: region.span, animated: animated)
        }
    }

    private func communityBoundingMapRect(for area: V2AreaRecord) -> MKMapRect? {
        if let geoJSON = area.geoJSON, let geoRect = mapRectFromGeoJSON(geoJSON), !geoRect.isNull, !geoRect.isEmpty {
            return expandedCommunityRectIfNeeded(geoRect)
        }

        func parse(_ key: String) -> Double? {
            guard let raw = area.tags?[key] else { return nil }
            return Double(raw)
        }

        if let north = parse("box:north"),
           let south = parse("box:south"),
           let east = parse("box:east"),
           let west = parse("box:west") {
            let topLeft = CLLocationCoordinate2D(latitude: north, longitude: west)
            let bottomRight = CLLocationCoordinate2D(latitude: south, longitude: east)
            let topLeftPoint = MKMapPoint(topLeft)
            let bottomRightPoint = MKMapPoint(bottomRight)
            let rect = MKMapRect(
                x: min(topLeftPoint.x, bottomRightPoint.x),
                y: min(topLeftPoint.y, bottomRightPoint.y),
                width: abs(topLeftPoint.x - bottomRightPoint.x),
                height: abs(topLeftPoint.y - bottomRightPoint.y)
            )
            if !rect.isNull, !rect.isEmpty {
                return expandedCommunityRectIfNeeded(rect)
            }
        }

        return nil
    }

    private func mapRectFromGeoJSON(_ geoJSON: GeoJSONFeatureCollection) -> MKMapRect? {
        var rect = MKMapRect.null

        func includeCoordinate(_ coordinate: [Double]) {
            guard coordinate.count >= 2 else { return }
            let lon = coordinate[0]
            let lat = coordinate[1]
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return }
            let point = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }

        for feature in geoJSON.features {
            switch feature.geometry.coordinates {
            case .polygon(let rings):
                for ring in rings {
                    for coordinate in ring {
                        includeCoordinate(coordinate)
                    }
                }
            case .multiPolygon(let polygons):
                for rings in polygons {
                    for ring in rings {
                        for coordinate in ring {
                            includeCoordinate(coordinate)
                        }
                    }
                }
            }
        }

        return rect.isNull ? nil : rect
    }

    private func expandedCommunityRectIfNeeded(_ rect: MKMapRect) -> MKMapRect {
        let midpoint = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let minimumMeters: CLLocationDistance = 800
        let minimumMapPoints = minimumMeters * MKMapPointsPerMeterAtLatitude(midpoint.latitude)

        let additionalWidth = max(0, minimumMapPoints - rect.width)
        let additionalHeight = max(0, minimumMapPoints - rect.height)

        if additionalWidth == 0, additionalHeight == 0 {
            return rect
        }

        return rect.insetBy(dx: -(additionalWidth / 2), dy: -(additionalHeight / 2))
    }

    private func communityMembersFromPolygon(for area: V2AreaRecord) -> [Element]? {
        guard let geoJSON = area.geoJSON else { return nil }
        let polygons = geoJSONPolygons(from: geoJSON)
        guard !polygons.isEmpty else { return nil }

        ensureMerchantSpatialIndex()

        let candidates: [MerchantSpatialIndex.Entry]
        if let box = MerchantPolygonGeometry.boundingBox(for: polygons) {
            candidates = merchantSpatialIndex.candidates(
                minLatitude: box.minLat,
                maxLatitude: box.maxLat,
                minLongitude: box.minLon,
                maxLongitude: box.maxLon
            )
        } else {
            // Degenerate geometry — fall back to scanning everything that has coordinates.
            candidates = allElements.compactMap { element in
                guard let coordinate = element.mapCoordinate else { return nil }
                return MerchantSpatialIndex.Entry(
                    id: element.id,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }

        let byID = Dictionary(allElements.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var members: [Element] = []
        members.reserveCapacity(min(candidates.count, 256))

        for candidate in candidates {
            guard polygons.contains(where: { polygon in
                coordinateInPolygon(
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    rings: polygon
                )
            }) else { continue }
            if let element = byID[candidate.id] {
                members.append(element)
            }
        }
        return members
    }

    private func ensureMerchantSpatialIndex() {
        let signature = merchantStoreSignature(for: allElements)
        guard signature != merchantSpatialIndexSignature || merchantSpatialIndex.isEmpty else { return }
        let start = CFAbsoluteTimeGetCurrent()
        merchantSpatialIndex.rebuild(from: allElements, sourceSignature: signature)
        merchantSpatialIndexSignature = signature
        Debug.logTiming(
            "map",
            "merchant spatial index rebuilt entries=\(merchantSpatialIndex.entryCount) in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms"
        )
    }

    /// Sampled signature over id + coarse coordinates at several positions.
    /// Cheap enough for every membership query; catches wholesale replacements
    /// and sampled coordinate moves without hashing the full catalog.
    private func merchantStoreSignature(for elements: [Element]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        guard !elements.isEmpty else { return hasher.finalize() }

        let lastIndex = elements.count - 1
        let sampleIndexes: [Int] = [
            0,
            lastIndex / 4,
            lastIndex / 2,
            (3 * lastIndex) / 4,
            lastIndex
        ]
        var seen = Set<Int>()
        for index in sampleIndexes where seen.insert(index).inserted {
            let element = elements[index]
            hasher.combine(element.id)
            if let coordinate = element.mapCoordinate {
                // ~100m precision — enough to invalidate on real moves, cheap to hash.
                hasher.combine(Int((coordinate.latitude * 1_000).rounded()))
                hasher.combine(Int((coordinate.longitude * 1_000).rounded()))
            }
        }
        return hasher.finalize()
    }

    private func geoJSONPolygons(from collection: GeoJSONFeatureCollection) -> [[[[Double]]]] {
        var polygons: [[[[Double]]]] = []
        for feature in collection.features {
            switch feature.geometry.coordinates {
            case .multiPolygon(let multipolygon):
                polygons.append(contentsOf: multipolygon)
            case .polygon(let polygon):
                polygons.append(polygon)
            }
        }
        return polygons
    }

    private func coordinateInPolygon(latitude: Double, longitude: Double, rings: [[[Double]]]) -> Bool {
        guard let outer = rings.first, pointInRing(latitude: latitude, longitude: longitude, ring: outer) else {
            return false
        }

        // Exclude points that are inside holes.
        for hole in rings.dropFirst() {
            if pointInRing(latitude: latitude, longitude: longitude, ring: hole) {
                return false
            }
        }
        return true
    }

    private func pointInRing(latitude: Double, longitude: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1

        for i in ring.indices {
            guard ring[i].count >= 2, ring[j].count >= 2 else {
                j = i
                continue
            }

            let xi = ring[i][0]
            let yi = ring[i][1]
            let xj = ring[j][0]
            let yj = ring[j][1]
            let intersects = ((yi > latitude) != (yj > latitude))
                && (longitude < (xj - xi) * (latitude - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)

            if intersects {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func resolveV3AreaID(for area: V2AreaRecord, completion: @escaping (Int?) -> Void) {
        // If the V2 ID is already numeric, use it directly.
        if let parsed = Int(area.id) {
            completion(parsed)
            return
        }
        // The V3 url_alias lives inside tags, not the top-level urlAlias field.
        // Check already-loaded V3 areas for a tags["url_alias"] match.
        if let v3Match = areaBrowserAreas.first(where: { $0.tags?["url_alias"] == area.id }) {
            completion(v3Match.id)
            return
        }
        // V3 areas not loaded yet — fetch and search for a match.
        btcMapRepository.fetchV3Areas(updatedSince: "1970-01-01T00:00:00Z", limit: 10000) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let areas):
                    let match = areas.first(where: { $0.tags?["url_alias"] == area.id })
                    completion(match?.id)
                case .failure:
                    completion(nil)
                }
            }
        }
    }

    private func fetchCommunityMembers(areaID: Int, requestID: UUID) {
        btcMapRepository.fetchV3AreaElements(areaID: areaID, updatedSince: "1970-01-01T00:00:00Z", limit: 10000) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.latestCommunitySelectionRequestID == requestID else { return }
                switch result {
                case .failure(let error):
                    self.communityMemberElements = []
                    self.communityMemberElementIDs = []
                    self.communityMembersError = error.localizedDescription
                    self.communityMembersIsLoading = false
                case .success(let rows):
                    let activeIDs = Set(rows.compactMap { row -> String? in
                        let isDeleted = !(row.deletedAt?.isEmpty ?? true)
                        guard !isDeleted else { return nil }
                        let trimmed = row.elementID.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    })
                    self.communityMemberElementIDs = activeIDs
                    self.communityMembersError = nil

                    let cachedMembers = self.allElements.filter { activeIDs.contains($0.id) }
                    let cachedIDs = Set(cachedMembers.map(\.id))
                    let missingIDs = activeIDs.subtracting(cachedIDs)
                    let placeholderIDs = cachedMembers.compactMap { member -> String? in
                        let name = member.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return Element.isInvalidPrimaryName(name) ? member.id : nil
                    }
                    let idsToHydrate = Set(missingIDs).union(placeholderIDs)

                    if idsToHydrate.isEmpty {
                        self.communityMemberElements = cachedMembers
                        self.communityMembersIsLoading = false
                    } else {
                        self.communityMemberElements = cachedMembers
                        self.communityMembersIsLoading = true
                        self.hydrateMissingCommunityMembers(
                            missingIDs: Array(idsToHydrate),
                            seedMembers: cachedMembers,
                            requestID: requestID
                        )
                    }
                }
                self.forceMapRefresh = true
            }
        }
    }

    private func hydrateMissingCommunityMembers(missingIDs: [String], seedMembers: [Element], requestID: UUID) {
        guard !missingIDs.isEmpty else {
            communityMembersIsLoading = false
            return
        }

        let group = DispatchGroup()
        let resultQueue = DispatchQueue(label: "community-members-hydration-results")
        var hydratedMembers: [Element] = []

        for id in missingIDs {
            group.enter()
            btcMapRepository.fetchPlace(id: id) { result in
                defer { group.leave() }
                guard case .success(let record) = result else { return }
                let mapped = V4PlaceToElementMapper.placeRecordToElement(record)
                if !(mapped.deletedAt?.isEmpty ?? true) { return }
                resultQueue.sync {
                    hydratedMembers.append(mapped)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            guard self.latestCommunitySelectionRequestID == requestID else { return }

            var byID = IdentifiableIndex.byID(seedMembers)
            for member in hydratedMembers {
                byID[member.id] = member
            }
            self.communityMemberElements = Array(byID.values)

            if !hydratedMembers.isEmpty {
                self.upsertMerchants(hydratedMembers, forceMapRefresh: false)
            }

            self.communityMembersIsLoading = false
            self.communityMembersError = nil
            self.forceMapRefresh = true
        }
    }

    func clearSelectedCommunity() {
        selectedCommunityArea = nil
        communityMemberElements = []
        communityMemberElementIDs = []
        communityMembersIsLoading = false
        communityMembersError = nil
        forceMapRefresh = true
    }

    private func mapRegion(forCommunityArea area: V2AreaRecord) -> MKCoordinateRegion? {
        func parse(_ key: String) -> Double? {
            guard let raw = area.tags?[key] else { return nil }
            return Double(raw)
        }

        if let north = parse("box:north"),
           let south = parse("box:south"),
           let east = parse("box:east"),
           let west = parse("box:west") {
            let center = CLLocationCoordinate2D(latitude: (north + south) / 2, longitude: normalizedMidLongitude(west: west, east: east))
            let latDelta = max(abs(north - south) * 1.2, 0.03)
            let lonSpan = longitudeDeltaAcrossAntimeridian(west: west, east: east)
            let lonDelta = max(lonSpan * 1.2, 0.03)
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        }
        return nil
    }

    private func longitudeDeltaAcrossAntimeridian(west: Double, east: Double) -> Double {
        let direct = abs(east - west)
        return direct <= 180 ? direct : 360 - direct
    }

    private func normalizedMidLongitude(west: Double, east: Double) -> Double {
        if abs(east - west) <= 180 {
            return (west + east) / 2
        }
        let shiftedEast = east < west ? east + 360 : east
        var mid = (west + shiftedEast) / 2
        if mid > 180 { mid -= 360 }
        return mid
    }

    // MARK: - Merchant Search (v4)

    /// Internal property for remote search text (synced from unifiedSearchText)
    private var merchantSearchText: String = ""

    func clearMerchantSearchResults() {
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchResults = []
        merchantSearchFreshResults = []
        merchantSearchError = nil
        merchantSearchIsLoading = false
        merchantSearchIsOfflineFallback = false
    }

    private var merchantSearchV2HybridEnabled: Bool {
        if UserDefaults.standard.object(forKey: merchantSearchV2HybridFlagKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: merchantSearchV2HybridFlagKey)
    }

    // MARK: - BTCMap Events (v4)

    func clearEventsResults() {
        eventsResults = []
        eventsError = nil
        eventsIsLoading = false
    }

    func loadBTCMapEvents() {
        eventsIsLoading = true
        eventsError = nil

        let query = V4EventsQuery(includePast: eventsIncludePast, limit: 100)
        btcMapRepository.fetchEvents(query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.eventsIsLoading = false
                switch result {
                case .success(let events):
                    self.eventsResults = events.sorted { lhs, rhs in
                        let l = lhs.startsAt ?? lhs.updatedAt ?? ""
                        let r = rhs.startsAt ?? rhs.updatedAt ?? ""
                        return l < r
                    }
                case .failure(let error):
                    self.eventsResults = []
                    self.eventsError = error.localizedDescription
                }
            }
        }
    }

    func selectEvent(_ event: V4EventRecord) {
        guard let lat = event.lat, let lon = event.lon else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        updateMapRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05), animated: true)
    }

    // MARK: - BTCMap Areas (v3 bridge)

    func loadAreaBrowserAreas() {
        areaBrowserIsLoading = true
        areaBrowserError = nil
        loadAreaBrowserAreasPaginated(anchor: "1970-01-01T00:00:00Z", page: 1, accumulated: [:])
    }

    private func loadAreaBrowserAreasPaginated(anchor: String, page: Int, accumulated: [Int: V3AreaRecord]) {
        let pageLimit = 5000
        let maxPages = 12
        btcMapRepository.fetchV3Areas(updatedSince: anchor, limit: pageLimit) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .failure(let error):
                    self.areaBrowserIsLoading = false
                    Debug.logAPI("loadAreaBrowserAreas failed (page \(page)): \(error.localizedDescription)")
                    self.areaBrowserAreas = []
                    self.areaBrowserError = error.localizedDescription

                case .success(let areas):
                    var merged = accumulated
                    for area in areas {
                        merged[area.id] = area
                    }

                    let nextAnchor = areas.compactMap(\.updatedAt).max()
                    let shouldContinue = areas.count >= pageLimit &&
                        page < maxPages &&
                        nextAnchor != nil &&
                        nextAnchor != anchor

                    if shouldContinue, let nextAnchor {
                        self.loadAreaBrowserAreasPaginated(anchor: nextAnchor, page: page + 1, accumulated: merged)
                        return
                    }

                    self.areaBrowserIsLoading = false
                    let finalAreas = Array(merged.values)
                    self.areaBrowserAreas = finalAreas
                        .filter { $0.bounds != nil || $0.geoJSON != nil }
                        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

                    self.hydrateMissingCommunityAreaGeoJSONIfNeeded()
                }
            }
        }
    }

    private func hydrateMissingCommunityAreaGeoJSONIfNeeded() {
        guard !communityGeoJSONHydrationInFlight else { return }

        let missingCommunityIDs = areaBrowserAreas
            .filter { $0.tags?["type"] == "community" && $0.geoJSON == nil }
            .map(\.id)
            .filter { !requestedCommunityAreaDetailIDs.contains($0) }

        guard !missingCommunityIDs.isEmpty else { return }

        communityGeoJSONHydrationInFlight = true
        let batchIDs = Array(missingCommunityIDs.prefix(100))
        batchIDs.forEach { requestedCommunityAreaDetailIDs.insert($0) }

        let group = DispatchGroup()
        let resultQueue = DispatchQueue(label: "bitlocal.community-geojson-hydration")
        let semaphore = DispatchSemaphore(value: 8)
        var hydrated: [V3AreaRecord] = []

        for areaID in batchIDs {
            group.enter()
            semaphore.wait()
            btcMapRepository.fetchV3Area(id: areaID) { [weak self] result in
                defer {
                    semaphore.signal()
                    group.leave()
                }
                guard self != nil else { return }
                switch result {
                case .success(let area):
                    if area.geoJSON != nil {
                        resultQueue.sync { hydrated.append(area) }
                    }
                case .failure:
                    break
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.communityGeoJSONHydrationInFlight = false

            if !hydrated.isEmpty {
                var byID = IdentifiableIndex.byID(self.areaBrowserAreas)
                for area in hydrated {
                    byID[area.id] = area
                }
                self.areaBrowserAreas = Array(byID.values)
                    .filter { $0.bounds != nil || $0.geoJSON != nil }
                    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                self.forceMapRefresh = true
            }

            // Continue in batches until we exhaust missing community polygons.
            self.hydrateMissingCommunityAreaGeoJSONIfNeeded()
        }
    }

    func selectArea(_ area: V3AreaRecord) {
        selectedAreaID = area.id
        selectedAreaElementCount = nil

        if let region = mapRegion(for: area) {
            updateMapRegion(center: region.center, span: region.span, animated: true)
        }

        btcMapRepository.fetchV3AreaElements(areaID: area.id, updatedSince: "1970-01-01T00:00:00Z", limit: 5000) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let rows):
                    let activeCount = rows.filter { ($0.deletedAt?.isEmpty ?? true) }.count
                    self.selectedAreaElementCount = activeCount
                case .failure:
                    self.selectedAreaElementCount = nil
                }
            }
        }
    }

    private func mapRegion(for area: V3AreaRecord) -> MKCoordinateRegion? {
        guard let bounds = area.bounds,
              let minLat = bounds.minLat,
              let maxLat = bounds.maxLat,
              let minLon = bounds.minLon,
              let maxLon = bounds.maxLon else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.2, 0.05)
        let lonDelta = max((maxLon - minLon) * 1.2, 0.05)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    private func performRemoteMerchantSearch() {
        let trimmedName = merchantSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 3 else {
            merchantSearchLoadingTimeoutTask?.cancel()
            merchantSearchIsLoading = false
            merchantSearchFreshResults = []
            merchantSearchResults = []
            return
        }
        let normalizedQuery = merchantSearchNormalizedQuery.isEmpty
            ? SearchTextNormalizer.normalize(trimmedName)
            : merchantSearchNormalizedQuery
        let plans = merchantRemoteSearchPlans(query: trimmedName, normalizedQuery: normalizedQuery)

        guard !plans.isEmpty else {
            merchantSearchLoadingTimeoutTask?.cancel()
            merchantSearchIsLoading = false
            merchantSearchFreshResults = []
            merchantSearchResults = []
            merchantSearchError = nil
            merchantSearchIsOfflineFallback = false
            return
        }

        let requestID = UUID()
        latestMerchantSearchRequestID = requestID
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchIsLoading = true
        merchantSearchError = nil
        merchantSearchIsOfflineFallback = false
        scheduleMerchantSearchLoadingTimeout(for: requestID)

        Debug.logAPI(
            "Merchant remote search START: scope=\(selectedMerchantSearchScope.rawValue), query='\(trimmedName)', plans=\(plans.map(\.source).joined(separator: ","))"
        )

        let group = DispatchGroup()
        let aggregationQueue = DispatchQueue(label: "bitlocal.merchant-search.remote-aggregation")
        var mergedByID: [String: V4PlaceRecord] = [:]
        var errors: [String] = []
        var hadSuccess = false

        for plan in plans {
            group.enter()
            btcMapRepository.searchPlaces(query: plan.query) { [weak self] result in
                guard let self else {
                    group.leave()
                    return
                }

                switch result {
                case .success(let records):
                    let filtered = self.filterRemoteSearchRecords(records, normalizedQuery: normalizedQuery)
                    aggregationQueue.async {
                        hadSuccess = true
                        for record in filtered {
                            mergedByID[record.idString] = mergedByID[record.idString] ?? record
                        }
                        group.leave()
                    }

                case .failure(let error):
                    aggregationQueue.async {
                        errors.append(error.localizedDescription)
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            guard self.latestMerchantSearchRequestID == requestID else { return }

            if hadSuccess {
                let rankedRecords = self.filterRemoteSearchRecords(
                    Array(mergedByID.values),
                    normalizedQuery: normalizedQuery
                )
                self.applyRemoteEnrichment(
                    records: rankedRecords,
                    requestID: requestID,
                    source: plans.map(\.source).joined(separator: "+")
                )
            } else {
                self.merchantSearchResults = []
                self.merchantSearchFreshResults = []
                self.merchantSearchError = errors.first ?? NSLocalizedString("Search unavailable", comment: "Fallback error when remote merchant search fails")
                self.merchantSearchLoadingTimeoutTask?.cancel()
                self.merchantSearchIsLoading = false
                self.merchantSearchIsOfflineFallback = true
                Debug.logAPI("Merchant remote search FAILURE: \(self.merchantSearchError ?? "unknown"). Local primary results retained: \(self.merchantSearchPrimaryResults.count)")
            }
        }
    }

    private func merchantRemoteSearchPlans(
        query: String,
        normalizedQuery: String
    ) -> [MerchantRemoteSearchPlan] {
        let trimmedProvider = merchantSearchProviderFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerTagName: String? = {
            guard !trimmedProvider.isEmpty else { return nil }
            return trimmedProvider.contains(":") ? trimmedProvider : "payment:\(trimmedProvider)"
        }()

        var plans: [MerchantRemoteSearchPlan] = []
        var seenQueries = Set<V4SearchQuery>()

        func appendPlan(_ query: V4SearchQuery, source: String) {
            guard !query.isEmpty else { return }
            guard seenQueries.insert(query).inserted else { return }
            plans.append(MerchantRemoteSearchPlan(query: query, source: source))
        }

        switch selectedMerchantSearchScope {
        case .onMap:
            return []

        case .worldwide:
            appendPlan(
                V4SearchQuery(
                    name: query,
                    lat: nil,
                    lon: nil,
                    radiusKM: nil,
                    tagName: providerTagName,
                    tagValue: providerTagName == nil ? nil : "yes"
                ),
                source: "name-worldwide"
            )

            guard providerTagName == nil,
                  let resolvedGroup = ElementCategorySymbols.resolvedCategoryGroup(forNormalizedQuery: normalizedQuery),
                  let filter = ElementCategorySymbols.preferredRemoteTagFilters(
                    for: resolvedGroup,
                    matchingNormalizedQuery: normalizedQuery,
                    limit: 1
                  ).first else {
                return plans
            }

            appendPlan(
                V4SearchQuery(
                    name: nil,
                    lat: nil,
                    lon: nil,
                    radiusKM: nil,
                    tagName: filter.tagKey,
                    tagValue: filter.tagValue
                ),
                source: "\(resolvedGroup.rawValue)-worldwide-\(filter.tagKey)=\(filter.tagValue)"
            )
        }

        return plans
    }

    private func filterRemoteSearchRecords(
        _ records: [V4PlaceRecord],
        normalizedQuery: String
    ) -> [V4PlaceRecord] {
        MerchantSearchEngine.filterRecords(records, normalizedQuery: normalizedQuery)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return merchantRecordSearchSortOrder(lhs.record, rhs.record)
            }
            .map(\.record)
    }

    private func applyRemoteEnrichment(
        records: [V4PlaceRecord],
        requestID: UUID,
        source: String
    ) {
        guard latestMerchantSearchRequestID == requestID else { return }

        merchantSearchResults = records
        let primaryIDs = Set(merchantSearchPrimaryResults.map(\.id))
        merchantSearchFreshResults = records.filter { !primaryIDs.contains($0.idString) }
        merchantSearchError = nil
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchIsLoading = false
        merchantSearchIsOfflineFallback = false

        if !merchantSearchPrimaryResults.isEmpty && records.isEmpty {
            Debug.logAPI("Merchant search diagnostic local_hit_remote_miss: query='\(merchantSearchText)', local=\(merchantSearchPrimaryResults.count), source=\(source)")
        }

        Debug.logAPI("Merchant remote search SUCCESS (\(source)): remote=\(records.count), fresh=\(merchantSearchFreshResults.count), local=\(merchantSearchPrimaryResults.count)")
    }

    private func scheduleMerchantSearchLoadingTimeout(for requestID: UUID) {
        merchantSearchLoadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.latestMerchantSearchRequestID == requestID else { return }
                guard self.merchantSearchIsLoading else { return }

                self.merchantSearchIsLoading = false
                self.merchantSearchError = self.merchantSearchError ?? NSLocalizedString("Search timed out", comment: "Error shown when merchant search takes too long")
                self.merchantSearchIsOfflineFallback = true
                Debug.logAPI("Merchant search timeout: requestID=\(requestID)")
            }
        }
    }

    private func remoteSearchGeometry(for scope: MerchantSearchScope) -> (lat: Double?, lon: Double?, radiusKM: Double?) {
        switch scope {
        case .onMap:
            return (region.center.latitude, region.center.longitude, merchantSearchRadiusKM)
        case .worldwide:
            return (nil, nil, nil)
        }
    }

    private func effectiveMerchantSearchDebounceNanoseconds() -> UInt64 {
        switch selectedMerchantSearchScope {
        case .onMap:
            return unifiedSearchDebounceNanoseconds
        case .worldwide:
            return unifiedSearchWorldwideDebounceNanoseconds
        }
    }

    private func effectiveLocalMerchantSearchDebounceNanoseconds() -> UInt64 {
        switch selectedMerchantSearchScope {
        case .onMap:
            return unifiedSearchDebounceNanoseconds
        case .worldwide:
            return localSearchWorldwideDebounceNanoseconds
        }
    }

    func hydrateMerchantSearchPreviewIfNeeded(_ record: V4PlaceRecord) {
        let id = record.idString
        guard shouldHydrateSearchResult(record) else { return }
        guard !merchantSearchPreviewHydrationInFlight.contains(id) else { return }
        merchantSearchPreviewHydrationInFlight.insert(id)

        btcMapRepository.fetchPlace(id: id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.merchantSearchPreviewHydrationInFlight.remove(id)
                guard case .success(let hydratedRecord) = result else { return }

                if let index = self.merchantSearchFreshResults.firstIndex(where: { $0.idString == id }) {
                    self.merchantSearchFreshResults[index] = hydratedRecord
                }
                if let index = self.merchantSearchResults.firstIndex(where: { $0.idString == id }) {
                    self.merchantSearchResults[index] = hydratedRecord
                }
                self.upsertElementIntoStore(V4PlaceToElementMapper.placeRecordToElement(hydratedRecord))
            }
        }
    }

    func selectMerchantSearchResult(_ record: V4PlaceRecord, allowCameraMovement: Bool = true) {
        let fallbackElement = V4PlaceToElementMapper.placeRecordToElement(record)
        if let existing = allElements.first(where: { $0.id == fallbackElement.id }) {
            presentMerchantSearchSelection(existing, allowCameraMovement: allowCameraMovement)
            return
        }

        if record.lat != nil, record.lon != nil, shouldHydrateSearchResult(record) {
            btcMapRepository.fetchPlace(id: record.idString) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let fullRecord):
                        let fullElement = V4PlaceToElementMapper.placeRecordToElement(fullRecord)
                        self.presentMerchantSearchSelection(
                            fullElement,
                            allowCameraMovement: allowCameraMovement
                        )
                    case .failure:
                        self.presentMerchantSearchSelection(
                            fallbackElement,
                            allowCameraMovement: allowCameraMovement
                        )
                    }
                }
            }
        } else {
            presentMerchantSearchSelection(fallbackElement, allowCameraMovement: allowCameraMovement)
        }
    }

    private func shouldHydrateSearchResult(_ record: V4PlaceRecord) -> Bool {
        // Search may return partial fields; hydrate when key detail fields are absent.
        (record.description == nil && record.openingHours == nil) || (record.phone == nil && record.website == nil)
    }

    private func presentMerchantSearchSelection(_ element: Element, allowCameraMovement: Bool) {
        upsertElementIntoStore(element)

        setSelectionSource(.list)
        selectAnnotationForListSelection(
            element,
            animated: true,
            allowCameraMovement: allowCameraMovement
        )
        selectedElement = element
        path = [element]
    }

    private func upsertElementIntoStore(_ element: Element) {
        replaceOrUpsertMerchant(element, forceMapRefresh: true)
    }

    // MARK: - Merchant catalog (MerchantElementStore)

    private func replaceMerchantCatalog(_ elements: [Element], forceMapRefresh: Bool) {
        merchantStoreRevision = merchantElementStore.replaceAll(elements)
        allElements = merchantElementStore.snapshot()
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    private func replaceOrUpsertMerchant(_ element: Element, forceMapRefresh: Bool) {
        let isNew = merchantElementStore.element(id: element.id) == nil
        merchantStoreRevision = merchantElementStore.upsert(element)
        // Avoid re-materializing the full catalog on single-element updates.
        if isNew {
            allElements.append(element)
        } else if let index = allElements.firstIndex(where: { $0.id == element.id }) {
            allElements[index] = element
        } else {
            allElements = merchantElementStore.snapshot()
        }
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    private func upsertMerchants(_ elements: [Element], forceMapRefresh: Bool) {
        guard !elements.isEmpty else { return }
        merchantStoreRevision = merchantElementStore.upsertMany(elements)
        // Small batches patch the published array in place; large ones snapshot once.
        if elements.count <= 32 {
            for element in elements {
                if let index = allElements.firstIndex(where: { $0.id == element.id }) {
                    allElements[index] = element
                } else {
                    allElements.append(element)
                }
            }
        } else {
            allElements = merchantElementStore.snapshot()
        }
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    private func merchantElementSearchSortOrder(_ lhs: Element, _ rhs: Element) -> Bool {
        let lhsScore = merchantSearchLocalMatchScoreByID[lhs.id] ?? 0
        let rhsScore = merchantSearchLocalMatchScoreByID[rhs.id] ?? 0
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        let lhsBoosted = lhs.isCurrentlyBoosted()
        let rhsBoosted = rhs.isCurrentlyBoosted()
        if lhsBoosted != rhsBoosted {
            return lhsBoosted && !rhsBoosted
        }

        let lhsDistance = merchantSearchDistance(for: lhs)
        let rhsDistance = merchantSearchDistance(for: rhs)

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsName = normalizedMerchantName(lhs.displayName ?? "")
        let rhsName = normalizedMerchantName(rhs.displayName ?? "")
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id < rhs.id
    }

    private func merchantRecordSearchSortOrder(_ lhs: V4PlaceRecord, _ rhs: V4PlaceRecord) -> Bool {
        let lhsBoosted = lhs.isCurrentlyBoosted()
        let rhsBoosted = rhs.isCurrentlyBoosted()
        if lhsBoosted != rhsBoosted {
            return lhsBoosted && !rhsBoosted
        }

        let lhsDistance = merchantSearchDistance(for: lhs)
        let rhsDistance = merchantSearchDistance(for: rhs)

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsName = normalizedMerchantName(lhs.displayName)
        let rhsName = normalizedMerchantName(rhs.displayName)
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id < rhs.id
    }

    private func merchantSearchDistance(for element: Element) -> CLLocationDistance {
        guard let coordinate = element.mapCoordinate else { return .greatestFiniteMagnitude }
        return merchantSearchDistance(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func merchantSearchDistance(for record: V4PlaceRecord) -> CLLocationDistance {
        guard let lat = record.lat, let lon = record.lon else { return .greatestFiniteMagnitude }
        return merchantSearchDistance(latitude: lat, longitude: lon)
    }

    private func merchantSearchDistance(latitude: Double, longitude: Double) -> CLLocationDistance {
        let target = CLLocation(latitude: latitude, longitude: longitude)

        if let user = userLocation {
            return user.distance(from: target)
        }

        let mapCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return mapCenter.distance(from: target)
    }

    private func normalizedMerchantName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    /// User-initiated merchant refresh (pull-to-refresh / empty-state retry).
    /// Reuses repository in-flight coalescing.
    func refreshMerchantData(userInitiated: Bool = true, completion: (() -> Void)? = nil) {
        if userInitiated {
            merchantSyncFailed = false
            merchantSyncStatusMessage = nil
        }
        fetchElements(warmupOnly: false, forceNetworkRefresh: userInitiated, completion: completion)
    }

    @MainActor
    func refreshMerchantData() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refreshMerchantData(userInitiated: true) {
                continuation.resume()
            }
        }
    }

    var lastSuccessfulSyncRelativeDescription: String? {
        guard let lastSuccessfulSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSuccessfulSyncAt, relativeTo: Date())
    }

    // Fetch elements using the APIManager and update the published elements property.
    // `warmupOnly` preloads merchant data without triggering onboarding-hostile side effects.
    // `forceNetworkRefresh` always joins a repository network refresh (pull-to-refresh /
    // retry) and never takes the "warm cache only" early return.
    func fetchElements(warmupOnly: Bool = false, forceNetworkRefresh: Bool = false, completion: (() -> Void)? = nil) {
        Debug.log("fetchElements() called - current state: isLoading=\(isLoading), appState=\(appState), isInitialStartup=\(isInitialStartup), warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh)")
        Debug.logTiming("data", "fetchElements invoked (warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh), allElements=\(allElements.count), isLoading=\(isLoading))")
        
        // Prevent concurrent calls - use main queue for thread safety
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // User-initiated pull joins any in-flight repository refresh via coalescing
            // instead of dismissing the spinner immediately.
            if self.isLoading {
                if forceNetworkRefresh {
                    Debug.log("Already loading; joining in-flight repository refresh for user pull")
                    self.btcMapRepository.refreshElements { [weak self] elements in
                        DispatchQueue.main.async {
                            guard let self else {
                                completion?()
                                return
                            }
                            self.applyRepositoryRefreshResult(
                                elements: elements,
                                hadAnyCache: self.btcMapRepository.hasCachedData() || !self.allElements.isEmpty,
                                currentElementsEmpty: self.allElements.isEmpty
                            )
                            // Do not clear isLoading here — the original owner owns that flag.
                            completion?()
                        }
                    }
                } else {
                    Debug.log("Already loading, skipping duplicate call")
                    completion?()
                }
                return
            }
            
            self.isLoading = true

            // Prefer showing cache immediately when memory is empty, even on forced
            // network refresh, so pull-to-refresh does not blank the list.
            if self.allElements.isEmpty,
               let cachedElements = self.btcMapRepository.loadCachedElements(),
               !cachedElements.isEmpty {
                Debug.logCache("Loading \(cachedElements.count) elements from cache into memory")
                Debug.logTiming("data", "loaded \(cachedElements.count) cached elements into memory")
                self.replaceMerchantCatalog(cachedElements, forceMapRefresh: false)
                self.hasLoadedInitialData = true
                self.merchantSyncFailed = false
                self.refreshLastSuccessfulSyncAtFromRepository()
                let cachedHasPlaceholders = self.hasPlaceholderNames(in: cachedElements)

                // Warm cache without placeholders: only skip the network when this is
                // NOT a user-forced refresh (launch / warmup path).
                if !forceNetworkRefresh, !cachedHasPlaceholders {
                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    completion?()

                    guard !warmupOnly else {
                        Debug.log("Warmup fetch loaded cached data; skipping map centering and location prompt")
                        return
                    }

                    if let userLoc = self.userLocation {
                        Debug.logMap("Centering map to user location for returning user")
                        self.centerMap(to: userLoc.coordinate)
                    } else {
                        Debug.logMap("No user location yet - requesting location for returning user")
                        self.requestWhenInUseLocationPermission()
                    }

                    if self.isInitialStartup {
                        Debug.log("Initial startup - delaying background updates by 5 seconds")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.checkForUpdatesInBackground()
                        }
                    } else {
                        self.checkForUpdatesInBackground()
                    }
                    return
                }

                if cachedHasPlaceholders {
                    Debug.logAPI("Cached elements include incomplete names; performing immediate refresh")
                    Debug.logTiming("data", "cached elements contain incomplete names; starting immediate refresh")
                } else {
                    Debug.logAPI("User-forced refresh with warm cache; hitting repository network path")
                }
            }

            let hadAnyCache = self.btcMapRepository.hasCachedData() || !self.allElements.isEmpty
            let currentElementsEmpty = self.allElements.isEmpty
            Debug.logCache("Repository cache available before refresh: \(hadAnyCache)")
            Debug.logCache("Current allElements empty: \(currentElementsEmpty)")
            Debug.logTiming("data", "starting repository refresh (hadCache=\(hadAnyCache), currentEmpty=\(currentElementsEmpty), warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh))")

            self.btcMapRepository.refreshElements { [weak self] elements in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.applyRepositoryRefreshResult(
                        elements: elements,
                        hadAnyCache: hadAnyCache,
                        currentElementsEmpty: currentElementsEmpty
                    )
                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    completion?()
                    
                    if self.isInitialStartup {
                        self.isInitialStartup = false
                    }
                }
            }
        }
    }

    private func applyRepositoryRefreshResult(
        elements: [Element]?,
        hadAnyCache: Bool,
        currentElementsEmpty: Bool
    ) {
        let refreshedElements = elements ?? []
        Debug.logAPI("Repository refresh returned \(refreshedElements.count) elements")
        Debug.logTiming("data", "repository refresh completed with \(refreshedElements.count) elements")

        if !refreshedElements.isEmpty {
            Debug.logMap("Setting allElements to repository snapshot (\(refreshedElements.count) elements)")
            replaceMerchantCatalog(refreshedElements, forceMapRefresh: true)
            hasLoadedInitialData = true
            noteMerchantSyncSucceeded()
        } else if currentElementsEmpty && !hadAnyCache {
            Debug.log("Repository returned no data and no cache was available")
            hasLoadedInitialData = true
            noteMerchantSyncOutcome(receivedCount: 0, hadCache: false, storeEmpty: true)
        } else {
            Debug.log("Repository returned no updates - keeping existing \(allElements.count) elements")
            // Empty payload with existing cache usually means "no changes", not failure.
            noteMerchantSyncOutcome(
                receivedCount: 0,
                hadCache: hadAnyCache,
                storeEmpty: allElements.isEmpty
            )
            if !allElements.isEmpty {
                refreshLastSuccessfulSyncAtFromRepository()
            }
        }
    }

    private func noteMerchantSyncSucceeded() {
        merchantSyncFailed = false
        merchantSyncStatusMessage = nil
        // Prefer the repository's just-written sync timestamp when present; fall
        // back to wall-clock so the footer never rewinds to a stale cached value.
        if let iso = btcMapRepository.lastSuccessfulSyncAtISO8601(),
           let parsed = BTCMapDateParser.parse(iso) {
            lastSuccessfulSyncAt = parsed
        } else {
            lastSuccessfulSyncAt = Date()
        }
    }

    private func noteMerchantSyncOutcome(receivedCount: Int, hadCache: Bool, storeEmpty: Bool) {
        if storeEmpty && receivedCount == 0 && !hadCache {
            merchantSyncFailed = true
            merchantSyncStatusMessage = NSLocalizedString(
                "Couldn’t update merchants. Check your connection and try again.",
                comment: "Empty-state message when merchant sync fails with no cache"
            )
        } else {
            merchantSyncFailed = false
            if storeEmpty {
                merchantSyncStatusMessage = nil
            }
        }
    }

    private func refreshLastSuccessfulSyncAtFromRepository() {
        guard let iso = btcMapRepository.lastSuccessfulSyncAtISO8601() else { return }
        if let parsed = BTCMapDateParser.parse(iso) {
            lastSuccessfulSyncAt = parsed
        }
    }

    private func hasPlaceholderNames(in elements: [Element]) -> Bool {
        elements.contains { element in
            let rawName = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Element.isInvalidPrimaryName(rawName)
        }
    }

    private func scheduleCommunityPrefetchIfNeeded() {
        guard !hasScheduledCommunityPrefetch else { return }
        hasScheduledCommunityPrefetch = true

        communityPrefetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Debug.logAPI("Prefetching community datasets in background")
            self.ensureCommunityMapAreasLoaded()
        }
        communityPrefetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // Background update check that doesn't block UI
    private func checkForUpdatesInBackground() {
        Debug.log("Starting background update check")

        btcMapRepository.refreshElements { [weak self] elements in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let refreshedElements = elements ?? []

                if !refreshedElements.isEmpty {
                    Debug.logMap("Background update: Repository returned \(refreshedElements.count) elements")
                    self.replaceMerchantCatalog(refreshedElements, forceMapRefresh: true)
                } else {
                    Debug.log("Background update: No new data available")
                    self.refreshLastSuccessfulSyncAtFromRepository()
                }
            }
        }
    }
}
