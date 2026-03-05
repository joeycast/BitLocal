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
    case onMap = "On Map"
    case worldwide = "Worldwide"

    var id: String { rawValue }
}

enum MerchantSearchSectionKind: String, Identifiable {
    case primaryResults
    case freshFromNetwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryResults:
            return "Primary Results"
        case .freshFromNetwork:
            return "Fresh from Network"
        }
    }
}

struct MerchantSearchSection: Identifiable {
    let kind: MerchantSearchSectionKind
    let localResults: [Element]
    let remoteResults: [V4PlaceRecord]

    var id: String { kind.id }
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

struct DeepLinkUnavailableState: Identifiable {
    let id = UUID()
    let placeID: String
    let title: String
    let message: String
}

@available(iOS 17.0, *)
final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    @Published var userLocation: CLLocation?
    @Published var isUpdatingLocation = false
    @Published var geocodingCache = LRUCache<String, Address>(maxSize: 100)
    @Published var path: [Element] = []
    @Published var selectedElement: Element?
    @Published var deepLinkUnavailableState: DeepLinkUnavailableState?
    @Published var cellViewModels: [String: ElementCellViewModel] = [:]
    @Published private(set) var allElements: [Element] = []
    @Published var visibleElements: [Element] = []
    @Published var isLoading: Bool = false
    @Published var topPadding: CGFloat = 0
    @Published var bottomPadding: CGFloat = 0
    @Published var initialRegionSet = false // Track if initial region has been set
    @Published var forceMapRefresh = false // Flag to force map annotation refresh
    @Published var selectionSource: SelectionSource = .unknown
    // Unified search state
    @Published var unifiedSearchText = ""
    @Published var isSearchActive = false
    @Published private(set) var localFilteredMerchants: [Element] = []
    @Published var selectedMerchantSearchScope: MerchantSearchScope = .onMap
    @Published private(set) var merchantSearchPrimaryResults: [Element] = []
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
    private var communityGeoJSONHydrationInFlight = false
    private var requestedCommunityAreaDetailIDs = Set<Int>()

    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder(maxConcurrentRequests: 1)
    let centerMapToCoordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()     // Publisher to center map to a coordinate
    private let btcMapRepository: BTCMapRepositoryProtocol
    
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
    private var placeholderNameHydrationInFlight = Set<String>()
    private var placeholderNameHydrationAttempted = Set<String>()
    private var normalizedMerchantSearchBlobByID: [String: String] = [:]
    private var normalizedMerchantSearchSignatureByID: [String: String] = [:]
    private var merchantSearchPreviewHydrationInFlight = Set<String>()
    private var merchantSearchLoadingTimeoutTask: Task<Void, Never>?
    private let merchantSearchV2HybridFlagKey = "search_v2_hybrid"
    
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
        locationManager.delegate = self
        setupCenterMapSubscription()
        visibleElementsSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] elements in
                self?.visibleElements = elements
                self?.hydratePlaceholderNamesIfNeeded(in: elements)
                self?.refreshMerchantSearchFromVisibleElementsIfNeeded()
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

                    guard case .success(let record) = result else { return }
                    let hydrated = V4PlaceToElementMapper.placeRecordToElement(record)

                    var byID = Dictionary(uniqueKeysWithValues: self.allElements.map { ($0.id, $0) })
                    byID[id] = hydrated
                    self.allElements = Array(byID.values)
                    if self.selectedElement?.id == id {
                        self.selectedElement = hydrated
                    }
                    self.forceMapRefresh = true
                }
            }
        }
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
            
            // Only fetch if we were previously inactive/background and don't have data
            if wasInactive && (self.allElements.isEmpty || self.shouldRefreshAfterInactive()) {
                Debug.log("App returning from inactive state - refreshing data")
                self.refreshAfterInactive()
            }
        }
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
        guard PlaceShareLinkBuilder.isValidPlaceID(placeID) else {
            presentDeepLinkUnavailable(placeID: placeID, reason: "Invalid place identifier.")
            return
        }

        mapDisplayMode = .merchants
        isSearchActive = false

        btcMapRepository.fetchPlace(id: placeID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let record):
                    if let deletedAt = record.deletedAt, !deletedAt.isEmpty {
                        self.presentDeepLinkUnavailable(
                            placeID: placeID,
                            reason: "This place is no longer available."
                        )
                        return
                    }

                    let element = V4PlaceToElementMapper.placeRecordToElement(record)
                    self.upsertElementIntoStore(element)
                    if let coordinate = element.mapCoordinate {
                        self.centerMap(to: coordinate, force: true)
                    }
                    self.setSelectionSource(.unknown)
                    self.selectedElement = element
                    self.path = [element]
                    self.deepLinkUnavailableState = nil

                case .failure(let error):
                    self.presentDeepLinkUnavailable(placeID: placeID, reason: error.localizedDescription)
                }
            }
        }
    }

    private func presentDeepLinkUnavailable(placeID: String, reason: String) {
        Debug.log("Deep link place unavailable: id=\(placeID), reason=\(reason)")
        deepLinkUnavailableState = DeepLinkUnavailableState(
            placeID: placeID,
            title: "Place unavailable",
            message: "We could not open this BitLocal place. It may have been removed or is temporarily unavailable."
        )
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
            let decoded = try JSONDecoder().decode([String: Address].self, from: data)
            geocodingCache.setValues(decoded)
            Debug.log("Loaded geocoding cache: \(decoded.count) entries")
        } catch {
            Debug.log("Failed to load geocoding cache: \(error.localizedDescription)")
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
            let hasDirectView = mapView.view(for: annotation) != nil
            if !isClustered && hasDirectView {
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
        allowCameraMovement: Bool = true
    ) {
        guard let mapView = mapView else { return }

        if let coordinate = element.mapCoordinate,
           let annotation = mapView.annotations.first(where: {
               ($0 as? Annotation)?.element?.id == element.id
           }) {
            let isClustered = isAnnotationClustered(annotation, on: mapView)
            let hasDirectView = mapView.view(for: annotation) != nil
            if !isClustered && hasDirectView {
                if allowCameraMovement {
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

    func centerMap(to coordinate: CLLocationCoordinate2D, force: Bool = false) {
        guard let mapView = mapView else {
            Debug.log("Cannot center map - mapView is nil")
            return
        }

        // Allow centering if:
        // 1. Force is true (user explicitly requested it)
        // 2. Never centered before
        // 3. Coordinate is significantly different
        // 4. Map's current center is far from target (user moved map)
        
        let shouldCenter: Bool
        
        if force {
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
                return
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
        if merchantSearchV2HybridEnabled {
            performUnifiedSearchHybrid(query: query)
        } else {
            performUnifiedSearchLegacyRemotePrimary(query: query)
        }
    }

    private func refreshMerchantSearchFromVisibleElementsIfNeeded() {
        guard mapDisplayMode == .merchants else { return }
        guard merchantSearchV2HybridEnabled else { return }
        guard selectedMerchantSearchScope == .onMap else { return }
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
        guard !normalizedQuery.isEmpty else { return [] }
        let filtered = source.filter { element in
            let normalizedBlob = normalizedSearchBlob(for: element)
            return SearchTextNormalizer.matches(
                normalizedQuery: normalizedQuery,
                normalizedCandidate: normalizedBlob
            )
        }
        return filtered.sorted(by: merchantElementSearchSortOrder)
    }

    private func performUnifiedSearchHybrid(query: String) {
        unifiedSearchDebounceTask?.cancel()
        localMerchantSearchTask?.cancel()

        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchNormalizedQuery = ""
            searchMatchingAreas = []
            clearMerchantSearchResults()
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        guard query.count >= 2 else {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchNormalizedQuery = ""
            clearMerchantSearchResults()
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        let normalizedQuery = SearchTextNormalizer.normalize(query)
        merchantSearchNormalizedQuery = normalizedQuery
        searchMatchingAreas = []

        merchantSearchFreshResults = []
        merchantSearchResults = []
        merchantSearchError = nil
        merchantSearchIsOfflineFallback = false
        merchantSearchIsLoading = query.count >= 3
        scheduleLocalMerchantSearch(query: query, normalizedQuery: normalizedQuery)

        merchantSearchAnchorCenter = region.center
        merchantSearchAnchorQuery = query

        Debug.logAPI(
            "Merchant search queued (hybrid): query='\(query)', normalized='\(normalizedQuery)', scope=\(selectedMerchantSearchScope.rawValue), local=\(localFilteredMerchants.count)"
        )

        guard query.count >= 3 else { return }

        unifiedSearchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: effectiveMerchantSearchDebounceNanoseconds())
            guard !Task.isCancelled else { return }
            await MainActor.run {
                merchantSearchText = query
                performRemoteMerchantSearch()
            }
        }
    }

    private func scheduleLocalMerchantSearch(query: String, normalizedQuery: String) {
        let source = localMerchantSearchSource(for: selectedMerchantSearchScope)
        let debounce: UInt64 = selectedMerchantSearchScope == .worldwide
            ? localSearchWorldwideDebounceNanoseconds
            : 0
        merchantSearchIsWaitingForLocalDebounce = debounce > 0

        localMerchantSearchTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: debounce)
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
                self.pruneFreshResultsAgainstPrimary()
                self.hydratePlaceholderNamesIfNeeded(in: Array(filtered.prefix(20)))
            }
        }
    }

    private func performUnifiedSearchLegacyRemotePrimary(query: String) {
        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
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
            return allElements
        }
    }

    private func normalizedSearchBlob(for element: Element) -> String {
        let rawFields = merchantSearchableTextFields(for: element)
        let signature = rawFields.joined(separator: "|")
        if normalizedMerchantSearchSignatureByID[element.id] == signature,
           let cached = normalizedMerchantSearchBlobByID[element.id] {
            return cached
        }

        let normalizedBlob = rawFields
            .map { SearchTextNormalizer.normalize($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        normalizedMerchantSearchSignatureByID[element.id] = signature
        normalizedMerchantSearchBlobByID[element.id] = normalizedBlob
        return normalizedBlob
    }

    private func merchantSearchableTextFields(for element: Element) -> [String] {
        [
            element.osmJSON?.tags?.name,
            element.osmJSON?.tags?.brand,
            element.osmJSON?.tags?.operator,
            element.displayName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func pruneFreshResultsAgainstPrimary() {
        let primaryIDs = Set(merchantSearchPrimaryResults.map(\.id))
        merchantSearchFreshResults = merchantSearchFreshResults.filter { !primaryIDs.contains($0.idString) }
    }

    func handleMerchantSearchMapRegionChange() {
        guard mapDisplayMode == .merchants else { return }
        guard selectedMerchantSearchScope == .onMap else { return }
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
        loadCommunityMapAreasV2Paginated(anchor: "2022-01-01T00:00:00.000Z", page: 1, accumulated: [:])
    }

    var mapElementsForCurrentDisplay: [Element] {
        switch mapDisplayMode {
        case .merchants:
            return allElements
        case .communities:
            return selectedCommunityArea == nil ? [] : communityMemberElements
        }
    }

    var isShowingCommunityMembersOnMap: Bool {
        mapDisplayMode == .communities && selectedCommunityArea != nil
    }

    var communityListAreas: [V2AreaRecord] {
        effectiveCommunityAreasForDisplay
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var visibleCommunityListAreas: [V2AreaRecord] {
        let allAreas = communityListAreas
        guard mapDisplayMode == .communities,
              selectedCommunityArea == nil,
              let mapView = mapView else {
            return allAreas
        }

        let viewportRect = mapListViewportRect(for: mapView)
        let visibleRect = mapRect(for: viewportRect, in: mapView)
        let focusCoordinate = mapView.convert(
            CGPoint(x: viewportRect.midX, y: viewportRect.midY),
            toCoordinateFrom: mapView
        )
        let focusLocation = CLLocation(latitude: focusCoordinate.latitude, longitude: focusCoordinate.longitude)

        var visibleIDs = Set<String>()
        var mergedBoundsByAreaID: [String: MKMapRect] = [:]

        for polygon in communityOverlays {
            let areaID = (polygon.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !areaID.isEmpty, polygon.boundingMapRect.intersects(visibleRect) else { continue }
            visibleIDs.insert(areaID)
            if let existing = mergedBoundsByAreaID[areaID] {
                mergedBoundsByAreaID[areaID] = existing.union(polygon.boundingMapRect)
            } else {
                mergedBoundsByAreaID[areaID] = polygon.boundingMapRect
            }
        }

        let filtered = allAreas.filter { visibleIDs.contains($0.id) }
        return filtered.sorted { lhs, rhs in
            let lhsDistance = communityDistanceFromFocus(areaID: lhs.id, focus: focusLocation, boundsByAreaID: mergedBoundsByAreaID)
            let rhsDistance = communityDistanceFromFocus(areaID: rhs.id, focus: focusLocation, boundsByAreaID: mergedBoundsByAreaID)
            if lhsDistance == rhsDistance {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return lhsDistance < rhsDistance
        }
    }

    private func communityDistanceFromFocus(
        areaID: String,
        focus: CLLocation,
        boundsByAreaID: [String: MKMapRect]
    ) -> CLLocationDistance {
        guard let rect = boundsByAreaID[areaID], !rect.isNull, !rect.isEmpty else {
            return .greatestFiniteMagnitude
        }
        let midpoint = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let center = CLLocation(latitude: midpoint.latitude, longitude: midpoint.longitude)
        return focus.distance(from: center)
    }

    func communityArea(withID id: String) -> V2AreaRecord? {
        communityMapAreas.first { $0.id == id }
    }

    private func loadCommunityMapAreasV2Paginated(anchor: String, page: Int, accumulated: [String: V2AreaRecord]) {
        let pageLimit = 500
        let maxPages = 20
        btcMapRepository.fetchV2Areas(updatedSince: anchor, limit: pageLimit) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.communityMapAreasIsLoading = false
                    self.hasLoadedCommunityMapAreas = false
                    Debug.logAPI("loadCommunityMapAreasV2 page \(page) failed: \(error.localizedDescription)")

                case .success(let areas):
                    var merged = accumulated
                    for area in areas {
                        if area.isDeleted {
                            merged.removeValue(forKey: area.id)
                        } else {
                            merged[area.id] = area
                        }
                    }

                    // Publish progressively so visible communities can appear immediately.
                    self.communityMapAreas = Array(merged.values)
                    self.forceMapRefresh = true

                    let nextAnchor = areas.last?.updatedAt
                    let shouldContinue = areas.count == pageLimit &&
                        page < maxPages &&
                        nextAnchor != nil &&
                        nextAnchor != anchor

                    if shouldContinue, let nextAnchor {
                        self.loadCommunityMapAreasV2Paginated(anchor: nextAnchor, page: page + 1, accumulated: merged)
                        return
                    }

                    self.communityMapAreasIsLoading = false
                }
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
            var merged = Dictionary(uniqueKeysWithValues: fallbackAreas.map { ($0.id, $0) })
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
        if let polygonMembers = communityMembersFromPolygon(for: area) {
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

        return allElements.filter { element in
            guard let coordinate = element.mapCoordinate else { return false }
            return polygons.contains { polygon in
                coordinateInPolygon(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    rings: polygon
                )
            }
        }
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

            var byID = Dictionary(uniqueKeysWithValues: seedMembers.map { ($0.id, $0) })
            for member in hydratedMembers {
                byID[member.id] = member
            }
            self.communityMemberElements = Array(byID.values)

            if !hydratedMembers.isEmpty {
                var allByID = Dictionary(uniqueKeysWithValues: self.allElements.map { ($0.id, $0) })
                for member in hydratedMembers {
                    allByID[member.id] = member
                }
                self.allElements = Array(allByID.values)
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

    var merchantSearchSections: [MerchantSearchSection] {
        var sections: [MerchantSearchSection] = []
        if !merchantSearchPrimaryResults.isEmpty {
            sections.append(
                MerchantSearchSection(
                    kind: .primaryResults,
                    localResults: merchantSearchPrimaryResults,
                    remoteResults: []
                )
            )
        }
        if !merchantSearchFreshResults.isEmpty {
            sections.append(
                MerchantSearchSection(
                    kind: .freshFromNetwork,
                    localResults: [],
                    remoteResults: merchantSearchFreshResults
                )
            )
        }
        return sections
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
                var byID = Dictionary(uniqueKeysWithValues: self.areaBrowserAreas.map { ($0.id, $0) })
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
        let trimmedProvider = merchantSearchProviderFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        let tagName: String?
        let tagValue: String?
        if trimmedProvider.isEmpty {
            tagName = nil
            tagValue = nil
        } else {
            tagName = trimmedProvider.contains(":") ? trimmedProvider : "payment:\(trimmedProvider)"
            tagValue = "yes"
        }

        let geometry = remoteSearchGeometry(for: selectedMerchantSearchScope)
        let namedQuery = V4SearchQuery(
            name: trimmedName.isEmpty ? nil : trimmedName,
            lat: geometry.lat,
            lon: geometry.lon,
            radiusKM: geometry.radiusKM,
            tagName: tagName,
            tagValue: tagValue
        )

        if namedQuery.isEmpty {
            clearMerchantSearchResults()
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
            "Merchant remote search START: scope=\(selectedMerchantSearchScope.rawValue), name='\(trimmedName)', provider='\(trimmedProvider)', lat=\(geometry.lat?.description ?? "nil"), lon=\(geometry.lon?.description ?? "nil"), radiusKM=\(geometry.radiusKM?.description ?? "nil")"
        )

        btcMapRepository.searchPlaces(query: namedQuery) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.latestMerchantSearchRequestID == requestID else { return }
                switch result {
                case .success(let records):
                    let filteredRecords = self.filterRemoteSearchRecords(
                        records,
                        normalizedQuery: self.merchantSearchNormalizedQuery
                    )
                    if filteredRecords.isEmpty {
                        if self.selectedMerchantSearchScope == .onMap {
                            Debug.logAPI("Merchant remote search named query produced 0 filtered result(s); trying bounded radius enrichment")
                            self.performSecondaryRemoteMerchantEnrichment(
                                requestID: requestID,
                                normalizedQuery: self.merchantSearchNormalizedQuery,
                                tagName: tagName,
                                tagValue: tagValue
                            )
                        } else {
                            self.applyRemoteEnrichment(records: [], requestID: requestID, source: "named-worldwide-empty")
                        }
                        return
                    }
                    self.applyRemoteEnrichment(records: filteredRecords, requestID: requestID, source: "named")
                case .failure(let error):
                    self.merchantSearchResults = []
                    self.merchantSearchFreshResults = []
                    self.merchantSearchError = error.localizedDescription
                    self.merchantSearchLoadingTimeoutTask?.cancel()
                    self.merchantSearchIsLoading = false
                    self.merchantSearchIsOfflineFallback = true
                    Debug.logAPI("Merchant remote search FAILURE: \(error.localizedDescription). Local primary results retained: \(self.merchantSearchPrimaryResults.count)")
                }
            }
        }
    }

    private func performSecondaryRemoteMerchantEnrichment(
        requestID: UUID,
        normalizedQuery: String,
        tagName: String?,
        tagValue: String?
    ) {
        guard selectedMerchantSearchScope == .onMap else {
            applyRemoteEnrichment(records: [], requestID: requestID, source: "secondary-skipped-scope")
            return
        }

        let secondaryQuery = V4SearchQuery(
            name: nil,
            lat: region.center.latitude,
            lon: region.center.longitude,
            radiusKM: merchantSearchRadiusKM,
            tagName: tagName,
            tagValue: tagValue
        )

        guard !secondaryQuery.isEmpty else {
            applyRemoteEnrichment(records: [], requestID: requestID, source: "secondary-empty")
            return
        }

        btcMapRepository.searchPlaces(query: secondaryQuery) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.latestMerchantSearchRequestID == requestID else { return }

                switch result {
                case .success(let records):
                    let filtered = self.filterRemoteSearchRecords(records, normalizedQuery: normalizedQuery)
                    self.applyRemoteEnrichment(records: filtered, requestID: requestID, source: "secondary-radius")
                case .failure(let error):
                    self.merchantSearchResults = []
                    self.merchantSearchFreshResults = []
                    self.merchantSearchError = error.localizedDescription
                    self.merchantSearchLoadingTimeoutTask?.cancel()
                    self.merchantSearchIsLoading = false
                    self.merchantSearchIsOfflineFallback = true
                    Debug.logAPI("Merchant secondary enrichment FAILURE: \(error.localizedDescription)")
                }
            }
        }
    }

    private func filterRemoteSearchRecords(
        _ records: [V4PlaceRecord],
        normalizedQuery: String
    ) -> [V4PlaceRecord] {
        guard !normalizedQuery.isEmpty else {
            return records.sorted(by: merchantRecordSearchSortOrder)
        }

        var deduplicatedByID: [String: V4PlaceRecord] = [:]
        for record in records where deduplicatedByID[record.idString] == nil {
            deduplicatedByID[record.idString] = record
        }

        return deduplicatedByID.values
            .filter { record in
                let normalizedBlob = normalizedSearchBlob(for: record)
                return SearchTextNormalizer.matches(
                    normalizedQuery: normalizedQuery,
                    normalizedCandidate: normalizedBlob
                )
            }
            .sorted(by: merchantRecordSearchSortOrder)
    }

    private func normalizedSearchBlob(for record: V4PlaceRecord) -> String {
        let rawFields: [String] = [
            record.displayName,
            record.osmBrand ?? "",
            record.osmOperator ?? "",
            record.address ?? ""
        ]
        return rawFields
            .map { SearchTextNormalizer.normalize($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
                self.merchantSearchError = self.merchantSearchError ?? "Search timed out"
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
        var dictionary = Dictionary(uniqueKeysWithValues: allElements.map { ($0.id, $0) })
        dictionary[element.id] = element
        allElements = Array(dictionary.values)
        forceMapRefresh = true
    }

    private func merchantElementSearchSortOrder(_ lhs: Element, _ rhs: Element) -> Bool {
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

    // Fetch elements using the APIManager and update the published elements property
    // Optimized to reduce startup calls
    func fetchElements() {
        Debug.log("fetchElements() called - current state: isLoading=\(isLoading), appState=\(appState), isInitialStartup=\(isInitialStartup)")
        
        // Prevent concurrent calls - use main queue for thread safety
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isLoading else {
                Debug.log("Already loading, skipping duplicate call")
                return
            }
            
            self.isLoading = true
            
            // IMPORTANT: Load from cache into memory first if allElements is empty
            if self.allElements.isEmpty {
                if let cachedElements = self.btcMapRepository.loadCachedElements(), !cachedElements.isEmpty {
                    Debug.logCache("Loading \(cachedElements.count) elements from cache into memory")
                    self.allElements = cachedElements
                    self.hasLoadedInitialData = true
                    let cachedHasPlaceholders = self.hasPlaceholderNames(in: cachedElements)

                    if cachedHasPlaceholders {
                        Debug.logAPI("Cached elements include placeholder names; performing immediate refresh")
                        self.btcMapRepository.refreshElements { [weak self] elements in
                            DispatchQueue.main.async {
                                guard let self else { return }
                                let refreshedElements = elements ?? []
                                if !refreshedElements.isEmpty {
                                    self.allElements = refreshedElements
                                    self.forceMapRefresh = true
                                }
                                self.isLoading = false
                                self.scheduleCommunityPrefetchIfNeeded()
                                if self.isInitialStartup {
                                    self.isInitialStartup = false
                                }
                            }
                        }
                        return
                    }

                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    
                    // Center map for returning users who have cached data
                    if let userLoc = self.userLocation {
                        Debug.logMap("Centering map to user location for returning user")
                        self.centerMap(to: userLoc.coordinate)
                    } else {
                        Debug.logMap("No user location yet - requesting location for returning user")
                        self.requestWhenInUseLocationPermission()
                    }
                    
                    // For initial startup, delay background updates to avoid immediate API call
                    if self.isInitialStartup {
                        Debug.log("Initial startup - delaying background updates by 5 seconds")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            self.checkForUpdatesInBackground()
                        }
                    } else {
                        // Still check for updates, but don't block UI
                        self.checkForUpdatesInBackground()
                    }
                    return
                }
            }

            let hadAnyCache = self.btcMapRepository.hasCachedData()
            let currentElementsEmpty = self.allElements.isEmpty
            Debug.logCache("Repository cache available before refresh: \(hadAnyCache)")
            Debug.logCache("Current allElements empty: \(currentElementsEmpty)")

            self.btcMapRepository.refreshElements { [weak self] elements in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    let refreshedElements = elements ?? []
                    Debug.logAPI("Repository refresh returned \(refreshedElements.count) elements")

                    if !refreshedElements.isEmpty {
                        Debug.logMap("Setting allElements to repository snapshot (\(refreshedElements.count) elements)")
                        self.allElements = refreshedElements
                        self.hasLoadedInitialData = true
                        self.forceMapRefresh = true
                    } else if currentElementsEmpty && !hadAnyCache {
                        Debug.log("Repository returned no data and no cache was available")
                    } else {
                        Debug.log("Repository returned no updates - keeping existing \(self.allElements.count) elements")
                    }
                    
                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    
                    // Mark initial startup as complete
                    if self.isInitialStartup {
                        self.isInitialStartup = false
                    }
                }
            }
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
                    self.allElements = refreshedElements
                    self.forceMapRefresh = true
                } else {
                    Debug.log("Background update: No new data available")
                }
            }
        }
    }
}
