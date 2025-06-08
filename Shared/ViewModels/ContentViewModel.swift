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

@available(iOS 17.0, *)
final class ContentViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, MKMapViewDelegate {
    // Sets the initial state of the map before getting user location. Coordinates are for Nashville, TN.
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.13, longitude: -86.775), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    @Published var userLocation: CLLocation?
    @Published var isUpdatingLocation = false
    @Published var geocodingCache = LRUCache<String, Address>(maxSize: 100)
    @Published var path: [Element] = []
    @Published var selectedElement: Element?
    @Published var cellViewModels: [String: ElementCellViewModel] = [:]
    @Published private(set) var allElements: [Element] = []
    @Published var visibleElements: [Element] = []
    @Published var isLoading: Bool = false
    @Published var topPadding: CGFloat = 0
    @Published var bottomPadding: CGFloat = 0
    @Published var initialRegionSet = false // Track if initial region has been set
    @Published var forceMapRefresh = false // Flag to force map annotation refresh
    
    let locationManager = CLLocationManager()
    let userLocationSubject = PassthroughSubject<CLLocation?, Never>()
    let visibleElementsSubject = PassthroughSubject<[Element], Never>()
    let mapStoppedMovingSubject = PassthroughSubject<Void, Never>()
    let geocoder = Geocoder(maxConcurrentRequests: 5)
    let centerMapToCoordinateSubject = PassthroughSubject<CLLocationCoordinate2D, Never>()     // Publisher to center map to a coordinate
    
    // Startup state tracking
    @Published var isInitialStartup = true
    @Published var hasLoadedInitialData = false
    
    // App state tracking
    @Published var appState: AppState = .active
    private var hasBeenInactive = false
    
    private var lastCenteredCoordinate: CLLocationCoordinate2D?
    
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?
    
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
    
    override init() {
        super.init()
        locationManager.delegate = self
        setupCenterMapSubscription()
        visibleElementsSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] elements in
                self?.visibleElements = elements
            }
            .store(in: &cancellables)
    }
    
    func handleAppBecameActive() {
        Debug.log("App became active - previous state: \(appState)")
        let wasInactive = hasBeenInactive
        
        // Batch state changes to minimize UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.appState = .active
            self.hasBeenInactive = false
            
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
        
        // Update map view to show user location
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Always center with padding to account for UI insets
            self.centerMap(to: latestLocation.coordinate)
            // Manually keep `region` in sync for SwiftUI bindings
            let currentSpan = self.region.span
            self.region = MKCoordinateRegion(center: latestLocation.coordinate, span: currentSpan)
            // Mark initial region as set on first update
            if !self.initialRegionSet {
                self.initialRegionSet = true
            }
            self.userLocation = latestLocation
            self.userLocationSubject.send(latestLocation)
        }
        manager.stopUpdatingLocation() // Stop updating location once we have the user's location
        isUpdatingLocation = false    // Set isUpdatingLocation to false so the progress view disappears
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
    
    // Zoom to element
    func zoomToElement(_ element: Element) {
        guard let mapView = mapView,
              let targetCoordinate = element.mapCoordinate else {
            Debug.log("Cannot zoom to element - mapView or coordinate missing")
            return
        }

        Debug.log("Zooming to element: \(element.id)")

        let targetCamera = MKMapCamera(
            lookingAtCenter: targetCoordinate,
            fromDistance: 500,
            pitch: 0,
            heading: 0
        )

        let inCluster = mapView.annotations
            .compactMap { $0 as? MKClusterAnnotation }
            .contains { cluster in
                cluster.memberAnnotations.contains { member in
                    (member as? Annotation)?.element?.id == element.id
                }
            }

        let duration: TimeInterval = 0.5
        let selectionDelay: TimeInterval = inCluster ? 0.8 : 0.1

        DispatchQueue.main.async {
            UIView.animate(
                withDuration: duration,
                animations: {
                    mapView.setCamera(targetCamera, animated: false)
                },
                completion: { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                        if let annotation = mapView.annotations.first(where: {
                            ($0 as? Annotation)?.element?.id == element.id
                        }) {
                            mapView.selectAnnotation(annotation, animated: true)
                        }
                    }
                }
            )
        }
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
    
    // Deselect the currently selected annotation
    func deselectAnnotation() {
        selectedElement = nil
        DispatchQueue.main.async { [weak self] in
            self?.mapView?.selectedAnnotations.forEach { annotation in
                self?.mapView?.deselectAnnotation(annotation, animated: true)
            }
        }
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
                if let cachedElements = APIManager.shared.loadElementsFromFile(), !cachedElements.isEmpty {
                    Debug.logCache("Loading \(cachedElements.count) elements from cache into memory")
                    self.allElements = cachedElements
                    self.hasLoadedInitialData = true
                    self.isLoading = false
                    
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
            
            // Check if this is a fresh start after cache clear
            let wasCacheEmpty = !APIManager.shared.hasCachedData()
            let currentElementsEmpty = self.allElements.isEmpty
            Debug.logCache("Cache empty before fetch: \(wasCacheEmpty)")
            Debug.logCache("Current allElements empty: \(currentElementsEmpty)")
            
            APIManager.shared.getElements { [weak self] elements in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    let processedElements = elements ?? []
                    Debug.logAPI("Processed \(processedElements.count) elements from API")
                    
                    // CRITICAL FIX: Handle different scenarios properly
                    if currentElementsEmpty || wasCacheEmpty {
                        // Fresh start - use the fetched elements directly
                        if !processedElements.isEmpty {
                            Debug.logMap("Fresh start - setting allElements to \(processedElements.count) elements")
                            self.allElements = processedElements
                            self.hasLoadedInitialData = true
                            self.forceMapRefresh = true
                        }
                    } else {
                        // Incremental update - merge with existing elements
                        if !processedElements.isEmpty {
                            Debug.logMap("Incremental update - merging \(processedElements.count) new elements with existing \(self.allElements.count)")
                            
                            // Merge logic: update existing elements or add new ones
                            var elementsDictionary = Dictionary(uniqueKeysWithValues: self.allElements.map { ($0.id, $0) })
                            
                            // Update/add new elements
                            processedElements.forEach { element in
                                elementsDictionary[element.id] = element
                            }
                            
                            let mergedElements = Array(elementsDictionary.values)
                            self.allElements = mergedElements
                            self.forceMapRefresh = true
                            
                            Debug.logMap("After merge: Total elements = \(mergedElements.count)")
                        } else {
                            Debug.log("No new elements from API - keeping existing \(self.allElements.count) elements")
                        }
                    }
                    
                    self.isLoading = false
                    
                    // Mark initial startup as complete
                    if self.isInitialStartup {
                        self.isInitialStartup = false
                    }
                }
            }
        }
    }

    // Background update check that doesn't block UI
    private func checkForUpdatesInBackground() {
        Debug.log("Starting background update check")
        
        APIManager.shared.getElements { [weak self] elements in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let processedElements = elements ?? []
                
                // Only update if we got new data
                if !processedElements.isEmpty {
                    Debug.logMap("Background update: Got \(processedElements.count) new elements, merging with existing \(self.allElements.count)")
                    
                    // CRITICAL FIX: Always merge, never replace
                    let existingElements = self.allElements
                    var elementsDictionary = Dictionary(uniqueKeysWithValues: existingElements.map { ($0.id, $0) })
                    
                    // Update/add new elements
                    processedElements.forEach { element in
                        elementsDictionary[element.id] = element
                    }
                    
                    let mergedElements = Array(elementsDictionary.values)
                    self.allElements = mergedElements
                    self.forceMapRefresh = true
                    
                    Debug.logMap("After background merge: Total elements = \(mergedElements.count)")
                } else {
                    Debug.log("Background update: No new data available")
                }
            }
        }
    }
}
