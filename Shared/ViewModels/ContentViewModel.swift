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
    // @Published var elements: [Element]? = nil
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
    
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?
    weak var mapView: MKMapView?
    
    override init() {
        super.init()
        locationManager.delegate = self
        mapView?.delegate = self
        setupCenterMapSubscription()
        visibleElementsSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] elements in
                self?.visibleElements = elements
            }
            .store(in: &cancellables)
    }
    
    // Request location
    func requestWhenInUseLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // Get latest location
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            // TODO: Show an error
            return
        }
        // Update map view to show user location
        DispatchQueue.main.async {
            self.updateMapRegion(center: latestLocation.coordinate)
            self.userLocation = latestLocation
            self.userLocationSubject.send(latestLocation)
            
            // 🔧 ADD THIS: Center map for returning users when location finally comes in
            if !self.allElements.isEmpty {
                Debug.logMap("Centering map for returning user (location received after cache load)")
                self.centerMap(to: latestLocation.coordinate)
            }
        }
        manager.stopUpdatingLocation() // Stop updating location once we have the user's location
        isUpdatingLocation = false    // Set isUpdatingLocation to false so the progress view disappears
    }
    
    // locationManager failure scenario (could not get user location)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: Need better error handling
        Debug.log("LocationManager error: \(error.localizedDescription)")
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
              let targetCoordinate = element.mapCoordinate else { return }

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
    
    private func setupCenterMapSubscription() {
        centerMapToCoordinateSubject
            .sink { [weak self] coordinate in
                guard let self = self, let mapView = self.mapView else { return }
                let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                let region = MKCoordinateRegion(center: coordinate, span: newZoomLevel)
                let edgePadding = UIEdgeInsets(
                    top: topPadding + 10,
                    left: 20,
                    bottom: bottomPadding + 100,
                    right: 20
                )
                mapView.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: region), animated: true)
                mapView.setVisibleMapRect(region.mapRect, edgePadding: edgePadding, animated: true)
            }
            .store(in: &cancellables)
    }

    func centerMap(to coordinate: CLLocationCoordinate2D) {
        guard let mapView = mapView else { return }

        // Build a small MKMapRect around the user location:
        let mapPoint = MKMapPoint(coordinate)
        let metersPerPoint = MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let mapSize = MKMapSize(width: 10000 * metersPerPoint, height: 10000 * metersPerPoint)
        let mapRect = MKMapRect(
            origin: MKMapPoint(x: mapPoint.x - mapSize.width / 2,
                               y: mapPoint.y - mapSize.height / 2),
            size: mapSize
        )

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
    
    // Update map region
    func updateMapRegion(center: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        let updatedSpan = span ?? region.span
        self.region = MKCoordinateRegion(center: center, span: updatedSpan)
        mapView?.setRegion(self.region, animated: animated)
    }
    
    // Deselect the currently selected annotation
    func deselectAnnotation() {
        selectedElement = nil
        DispatchQueue.main.async {
            self.mapView?.selectedAnnotations.forEach { annotation in
                self.mapView?.deselectAnnotation(annotation, animated: true)
            }
        }
    }

    // Fetch elements using the APIManager and update the published elements property
    func fetchElements() {
        Debug.log("fetchElements() called!")
        Debug.log("fetchElements() called - isLoading: \(isLoading)")
        
        // Prevent concurrent calls
        guard !isLoading else {
            Debug.log("Already loading, skipping duplicate call")
            return
        }
        
        isLoading = true
        
        // IMPORTANT: Load from cache into memory first if allElements is empty
        if allElements.isEmpty {
            if let cachedElements = APIManager.shared.loadElementsFromFile(), !cachedElements.isEmpty {
                Debug.logCache("Loading \(cachedElements.count) elements from cache into memory")
                allElements = cachedElements
                // Set loading to false since we have data now
                isLoading = false
                
                // 🔧 Center map for returning users who have cached data
                if let userLoc = userLocation {
                    Debug.logMap("Centering map to user location for returning user")
                    centerMap(to: userLoc.coordinate)
                } else {
                    Debug.logMap("No user location yet - requesting location for returning user")
                    // Start location updates if we don't have location yet
                    locationManager.requestWhenInUseAuthorization()
                    locationManager.startUpdatingLocation()
                }
                
                // Still check for updates, but don't block UI
                checkForUpdatesInBackground()
                return
            }
        }
        
        // Check if this is a fresh start after cache clear
        let wasCacheEmpty = !APIManager.shared.hasCachedData()
        let currentElementsEmpty = allElements.isEmpty
        Debug.logCache("Cache empty before fetch: \(wasCacheEmpty)")
        Debug.logCache("Current allElements empty: \(currentElementsEmpty)")
        
        APIManager.shared.getElements { [weak self] elements in
            DispatchQueue.main.async {
                let processedElements = elements ?? []
                Debug.logAPI("Processed \(processedElements.count) elements")
                
                // Update allElements if:
                // 1. We got new data, OR
                // 2. Cache was empty (fresh start), OR
                // 3. Current data is empty (recovery scenario)
                let shouldUpdate = !processedElements.isEmpty || wasCacheEmpty || currentElementsEmpty
                
                if shouldUpdate {
                    Debug.logMap("Updating allElements with \(processedElements.count) elements")
                    self?.allElements = processedElements
                    
                    // Force map refresh if cache was empty (indicating fresh data load)
                    if wasCacheEmpty && !processedElements.isEmpty {
                        Debug.logMap("Setting forceMapRefresh = true (cache was empty, got \(processedElements.count) elements)")
                        self?.forceMapRefresh = true
                    } else if currentElementsEmpty && !processedElements.isEmpty {
                        Debug.logMap("Setting forceMapRefresh = true (recovery from empty state)")
                        self?.forceMapRefresh = true
                    } else {
                        Debug.logMap("NOT setting forceMapRefresh - wasCacheEmpty: \(wasCacheEmpty), currentEmpty: \(currentElementsEmpty), elements.count: \(processedElements.count)")
                    }
                } else {
                    Debug.log("Skipping allElements update - got 0 elements, cache wasn't empty, and current data exists")
                }
                
                self?.isLoading = false
                Debug.logMap("Current forceMapRefresh state: \(self?.forceMapRefresh ?? false)")
            }
        }
    }

    // Background update check that doesn't block UI
    private func checkForUpdatesInBackground() {
        APIManager.shared.getElements { [weak self] elements in
            DispatchQueue.main.async {
                let processedElements = elements ?? []
                
                // Only update if we got new data
                if !processedElements.isEmpty {
                    Debug.logMap("Background update: Got \(processedElements.count) new elements, merging with existing \(self?.allElements.count ?? 0)")
                    
                    // 🔧 FIX: Merge new elements with existing ones
                    let existingElements = self?.allElements ?? []
                    var elementsDictionary = Dictionary(uniqueKeysWithValues: existingElements.map { ($0.id, $0) })
                    
                    // Update/add new elements
                    processedElements.forEach { element in
                        elementsDictionary[element.id] = element
                    }
                    
                    let mergedElements = Array(elementsDictionary.values)
                    self?.allElements = mergedElements
                    self?.forceMapRefresh = true
                    
                    Debug.logMap("After merge: Total elements = \(mergedElements.count)")
                } else {
                    Debug.log("Background update: No new data available")
                }
            }
        }
    }
}
