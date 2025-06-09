//
//  MapView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import MapKit
import Combine
import Foundation // for Debug logging

@available(iOS 17.0, *)
struct MapView: UIViewRepresentable {
    var elements: [Element]?
    @EnvironmentObject var viewModel: ContentViewModel
    
    // Properties for Dynamic Padding
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    
    // Propery for map type selection
    var mapType: MKMapType
    
    // Initializer
    init(elements: [Element]?, topPadding: CGFloat, bottomPadding: CGFloat, mapType: MKMapType) {
        self.elements = elements
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.mapType = mapType
    }
    
    // Create the Coordinator, which will act as the MKMapViewDelegate
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, topPadding: topPadding, bottomPadding: bottomPadding)
    }
    
    // Create and configure the MKMapView
    func makeUIView(context: Context) -> MKMapView {
        // Reuse existing MKMapView on iPad to preserve region
        if let existingMap = viewModel.mapView {
            Debug.log("MapView.makeUIView() - reusing existing MKMapView")
            // Reattach delegate and config
            existingMap.delegate = context.coordinator
            setupCluster(mapView: existingMap)
            existingMap.showsUserLocation = true
            existingMap.mapType = mapType
            return existingMap
        }
        let mapView = MKMapView()
        
        Debug.log("MapView.makeUIView() called - creating new MKMapView")
        
        // Store reference to mapView in viewModel - ensure main queue
        DispatchQueue.main.async {
            self.viewModel.mapView = mapView
        }
        
        // Set the delegate to the Coordinator
        mapView.delegate = context.coordinator
        
        // Set up clustering
        setupCluster(mapView: mapView)
        
        // Show user location on the map
        mapView.showsUserLocation = true
        
        // Set initial map type
        mapView.mapType = mapType
        
        // FIXED: Only auto-request location if onboarding is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let didCompleteOnboarding = UserDefaults.standard.bool(forKey: "didCompleteOnboarding")
            guard !self.viewModel.initialRegionSet else {
                Debug.log("MapView.makeUIView - initial region already set, skipping auto-centering")
                return
            }
            if let userLocation = self.viewModel.locationManager.location {
                Debug.log("MapView.makeUIView - centering to existing location: \(userLocation.coordinate)")
                // Center the map and mark initial region as set
                self.viewModel.centerMap(to: userLocation.coordinate, force: true)
                self.viewModel.initialRegionSet = true
                // Update the viewModel.region to match the visible map rect
                let center = userLocation.coordinate
                let spanLatitude = mapView.region.span.latitudeDelta
                let spanLongitude = mapView.region.span.longitudeDelta
                self.viewModel.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: spanLatitude, longitudeDelta: spanLongitude))
            } else if didCompleteOnboarding {
                // Only request location automatically if onboarding is complete
                Debug.log("MapView.makeUIView - no user location, requesting location updates (onboarding complete)")
                self.viewModel.requestWhenInUseLocationPermission()
            } else {
                // During onboarding - don't request location automatically
                Debug.log("MapView.makeUIView - onboarding not complete, skipping automatic location request")
            }
        }

        return mapView
    }

    // Update the MKMapView when the SwiftUI view updates
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // CRITICAL: Don't update UI when app is not active
        guard viewModel.appState == .active else {
            Debug.logMap("MapView.updateUIView() - SKIPPED (app state: \(viewModel.appState))")
            return
        }
        
        // Skip updates during initial startup until data is loaded
        guard viewModel.hasLoadedInitialData else {
            Debug.logMap("MapView.updateUIView() - SKIPPED (waiting for initial data)")
            return
        }
        
        Debug.logMap("MapView.updateUIView() called!")

        // Ensure mapView reference is current (only update if different)
        if viewModel.mapView !== mapView {
            Debug.log("MapView.updateUIView - updating mapView reference")
            viewModel.mapView = mapView
        }

        // Batch property updates to minimize individual triggers
        var needsUpdate = false
        
        // Check padding changes
        let currentPadding = (context.coordinator.topPadding, context.coordinator.bottomPadding)
        let newPadding = (topPadding, bottomPadding)
        if currentPadding != newPadding {
            context.coordinator.updatePadding(top: topPadding, bottom: bottomPadding)
            needsUpdate = true
        }
        
        // Check map type changes
        if mapView.mapType != mapType {
            mapView.mapType = mapType
            needsUpdate = true
        }
        
        // Handle elements updates (most important)
        if let elements = elements, !elements.isEmpty {
            let elementsHash = elements.hashValue
            let shouldForceUpdate = viewModel.forceMapRefresh
            let hashChanged = context.coordinator.lastElementsHash != elementsHash
            
            // Only log details if we're actually going to update
            if hashChanged || shouldForceUpdate {
                Debug.logMap("MapView.updateUIView - Elements update needed:")
                Debug.logMap("   - Elements count: \(elements.count)")
                Debug.logMap("   - Hash changed: \(hashChanged)")
                Debug.logMap("   - Force refresh: \(shouldForceUpdate)")
                
                context.coordinator.lastElementsHash = elementsHash
                context.coordinator.updateAnnotations(mapView: mapView, elements: elements)
                Debug.logMap("Annotations updated!")
                
                // Reset the force refresh flag after using it
                if shouldForceUpdate {
                    DispatchQueue.main.async {
                        self.viewModel.forceMapRefresh = false
                        Debug.logMap("Reset forceMapRefresh to false")
                    }
                }
                needsUpdate = true
            }
        } else if elements?.isEmpty == true {
            // Only clear if we actually have annotations to clear
            let currentAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
            if !currentAnnotations.isEmpty {
                Debug.logMap("MapView.updateUIView: Clearing \(currentAnnotations.count) annotations")
                mapView.removeAnnotations(currentAnnotations)
                needsUpdate = true
            }
        }
        
        // Only log if we actually did something
        if !needsUpdate {
            // Silent skip - don't log unless debugging
            // Debug.logMap("MapView.updateUIView: No changes needed")
        }
    }
    
    // Set up clustering for map annotations
    private func setupCluster(mapView: MKMapView) {
        let clusteringIdentifier = "Cluster"
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: clusteringIdentifier)
    }
    
    // Coordinator class to handle MKMapViewDelegate methods and annotations management
    class Coordinator: NSObject, MKMapViewDelegate {
        var viewModel: ContentViewModel
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var mapRegionChangeCompletion: (() -> Void)?
        
        // Keep track of previously displayed elements to manage annotations efficiently
        var previousElements: Set<Element> = []
        var currentAnnotations: [String: Annotation] = [:] // Keep track of current annotations
        private var cancellable: AnyCancellable?
        private var debounceTimer: AnyCancellable?
        var lastElementsHash: Int?
        
        init(viewModel: ContentViewModel, topPadding: CGFloat, bottomPadding: CGFloat) {
            self.viewModel = viewModel
            self.topPadding = topPadding
            self.bottomPadding = bottomPadding
        }
        
        // Update padding method
        func updatePadding(top: CGFloat, bottom: CGFloat) {
            self.topPadding = top
            self.bottomPadding = bottom
        }
        
        // Smoothly expand the cluster and zoom to a specific annotation
        private func expandClusterAndZoomToAnnotation(_ cluster: MKClusterAnnotation, targetAnnotation: MKAnnotation, mapView: MKMapView) {
            // Calculate the bounding rect for the cluster's member annotations
            var rect = MKMapRect.null
            for annotation in cluster.memberAnnotations {
                let point = MKMapPoint(annotation.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            
            // Apply a slight zoom-out scale for better visual feedback
            let zoomOutScale: Double = 1.3
            rect = rect.insetBy(dx: -rect.size.width * (zoomOutScale - 1), dy: -rect.size.height * (zoomOutScale - 1))
            
            // Edge padding for header and bottom sheet
            let edgePadding = UIEdgeInsets(
                top: viewModel.topPadding + 10,
                left: 20,
                bottom: viewModel.bottomPadding + 100,
                right: 20
            )
            
            // Smoothly animate to the expanded cluster region
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseInOut], animations: {
                    mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
                }, completion: { _ in
                    // After cluster expansion, smoothly center and zoom into the target annotation
                    self.centerAnnotationSmoothly(mapView: mapView, annotation: targetAnnotation)
                })
            }
        }
        
        // Smoothly center and zoom into an annotation
        private func centerAnnotationSmoothly(mapView: MKMapView, annotation: MKAnnotation) {
            let targetCoordinate = annotation.coordinate
            
            // Desired camera altitude for zoom (adjust this value for more/less zoom)
            let altitude: CLLocationDistance = 500 // A lower value zooms in more
            
            // Create an MKMapCamera with the target coordinate and altitude
            let camera = MKMapCamera(lookingAtCenter: targetCoordinate, fromDistance: altitude, pitch: 0, heading: 0)
            
            // Perform a smooth camera animation
            UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut], animations: {
                mapView.setCamera(camera, animated: true)
            }, completion: { _ in
                // Select the annotation after the animation completes
                DispatchQueue.main.async {
                    mapView.selectAnnotation(annotation, animated: true)
                }
            })
        }
        
        // Ensure to cancel the subscription when the Coordinator is deinitialized
        deinit {
            cancellable?.cancel()
        }
        
        // Efficiently update annotations by only adding/removing what's changed
        func updateAnnotations(mapView: MKMapView, elements: [Element]?) {
            guard let elements = elements else { return }
            
            let visibleRect = mapView.visibleMapRect
            let centerCoordinate = mapView.centerCoordinate
            let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
            
            let visibleElements = elements.filter { element in
                guard let coordinate = element.mapCoordinate else { return false }
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let distance = location.distance(from: centerLocation)
                
                let mapPoint = MKMapPoint(coordinate)
                return visibleRect.contains(mapPoint) &&
                distance <= 25 * 1609.344 && // 25 miles in meters
                (element.deletedAt == nil || element.deletedAt == "") &&
                (element.osmJSON?.tags?.name != nil || element.osmJSON?.tags?.operator != nil)
            }
            
            let existingAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
            let existingElements = Set(existingAnnotations.compactMap { $0.element })
            let newElements = Set(visibleElements)
            
            let annotationsToRemove = existingAnnotations.filter { !newElements.contains($0.element!) }
            let elementsToAdd = newElements.subtracting(existingElements)
            
            mapView.removeAnnotations(annotationsToRemove)
            
            let newAnnotations = elementsToAdd.map { Annotation(element: $0) }
            mapView.addAnnotations(newAnnotations)
            
            self.viewModel.visibleElementsSubject.send(Array(newElements))
        }
        
        // MARK: - MKMapViewDelegate Methods
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let reuseIdentifier = "AnnotationView"
            var view: MKMarkerAnnotationView?
            
            if let cluster = annotation as? MKClusterAnnotation {
                // Handle cluster annotations
                view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                view?.markerTintColor = UIColor(named: "MarkerColor")
                view?.glyphText = "\(cluster.memberAnnotations.count)"
            } else if let annotation = annotation as? Annotation {
                // Handle individual annotations
                if annotation.element == nil {
                    fatalError("Failed to get element from annotation.")
                }
                view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                view?.canShowCallout = true
                view?.markerTintColor = UIColor(named: "MarkerColor")
                view?.glyphText = nil
                view?.glyphTintColor = .white
                if let element = annotation.element {
                    let symbolName = ElementCategorySymbols.symbolName(for: element)
                    Debug.logMap("Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                    view?.glyphImage = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                }
                view?.displayPriority = .required
            }
            return view
        }
        
        // Handle annotation selection to update navigation path
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let annotations = cluster.memberAnnotations
                
                // Calculate the bounding map rect for the cluster annotations
                var rect = MKMapRect.null
                for annotation in annotations {
                    let point = MKMapPoint(annotation.coordinate)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }
                
                // Apply a scale factor to control zoom level
                let zoomOutScale: Double = 1.3 // Adjust this value for better zoom
                rect = rect.insetBy(dx: -rect.size.width * (zoomOutScale - 1),
                                    dy: -rect.size.height * (zoomOutScale - 1))
                
                // Edge padding to respect header and bottom sheet
                let topInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 10 : viewModel.topPadding + 10
                let edgePadding = UIEdgeInsets(
                    top: topInset,
                    left: 20,
                    bottom: viewModel.bottomPadding + 100,
                    right: 20
                )
                
                // Set the visible map rect with padding and zoom adjustments
                mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: true)
                
                Debug.logMap("""
                Cluster Selected -> 
                Edge Padding (Top: \(edgePadding.top), Bottom: \(edgePadding.bottom)),
                Zoom Scale: \(zoomOutScale)
                """)
            }
            else if let annotation = view.annotation as? Annotation, let element = annotation.element {
                // Restore the logic to display BusinessDetailView
                DispatchQueue.main.async {
                    self.viewModel.path = [element] // Update path for NavigationStack
                    self.viewModel.selectedElement = element // Update the selected element
                    
                    Debug.logMap("Annotation tapped: \(element)")
                }
            }
        }
        
        
        // Detect when the map region changes
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update the view model's region to match the map's region
            if viewModel.initialRegionSet {
                self.viewModel.updateMapRegion(center: mapView.region.center, span: mapView.region.span)
            }
            
            // Debounce the call to update annotations
            debounceTimer?.cancel()
            debounceTimer = Just(())
                .delay(for: .seconds(0.5), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.updateAnnotations(mapView: mapView, elements: self.viewModel.allElements)
                }
            
            if animated, let completion = mapRegionChangeCompletion {
                // Trigger completion handler
                mapRegionChangeCompletion = nil // Reset to avoid repeated calls
                completion()
            }
        }
        
        // Update visible elements based on annotations in the visible map rect
        func updateVisibleElements(for mapView: MKMapView) {
            let visibleAnnotations = mapView.annotations(in: mapView.visibleMapRect)
            let visibleElements = visibleAnnotations.compactMap { ($0 as? Annotation)?.element }
            
            self.viewModel.visibleElementsSubject.send(visibleElements)
            self.viewModel.mapStoppedMovingSubject.send(())
        }
    }
}
