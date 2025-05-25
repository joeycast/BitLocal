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
    @Published var elements: [Element]? = []
    @Published var topPadding: CGFloat = 0
    @Published var bottomPadding: CGFloat = 0
    @Published var initialRegionSet = false // Track if initial region has been set
    
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
        }
        manager.stopUpdatingLocation() // Stop updating location once we have the user's location
        isUpdatingLocation = false    // Set isUpdatingLocation to false so the progress view disappears
    }
    
    // locationManager failure scenario (could not get user location)
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // TODO: Need better error handling
        print(error.localizedDescription)
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
    
    func centerMap(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        guard let mapView = mapView else { return }
        
        if !initialRegionSet {
            // Set an initial zoom level only once
            print("Setting initial region -> Coordinate: \(coordinate.latitude), \(coordinate.longitude)")
            let initialRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3) // Default zoom level
            )
            mapView.setRegion(initialRegion, animated: animated)
            initialRegionSet = true
        } else {
            // Preserve zoom level and only center the map
            print("Centering Map -> Coordinate: \(coordinate.latitude), \(coordinate.longitude)")
            mapView.setCenter(coordinate, animated: animated)
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
}
