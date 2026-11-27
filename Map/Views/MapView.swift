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

struct MapView: UIViewRepresentable {
    var elements: [Element]?
    @Environment(ContentViewModel.self) var viewModel
    
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
            context.coordinator.installCommunityOverlayTapRecognizer(on: existingMap)
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
        context.coordinator.installCommunityOverlayTapRecognizer(on: mapView)
        
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
        let updateStart = CFAbsoluteTimeGetCurrent()
        // CRITICAL: Don't update UI when app is not active
        guard viewModel.appState == .active else {
            Debug.logMap("MapView.updateUIView() - SKIPPED (app state: \(viewModel.appState))")
            return
        }
        
        // Skip updates during initial startup until data is loaded
        guard viewModel.hasLoadedInitialData else {
            Debug.logTiming(
                "data",
                "MapView.updateUIView skipped -> waiting for initial data (ready=\(viewModel.isReadyForPostOnboardingPresentation), allElements=\(viewModel.allElements.count))"
            )
            return
        }

        guard viewModel.isReadyForPostOnboardingPresentation else {
            let currentAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
            if !currentAnnotations.isEmpty {
                mapView.removeAnnotations(currentAnnotations)
            }
            Debug.logTiming(
                "onboarding",
                "MapView.updateUIView skipped -> waiting for post-onboarding settle (existingAnnotations=\(currentAnnotations.count), allElements=\(viewModel.mapElementsForCurrentDisplay.count))"
            )
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
        let paddingChanged = currentPadding != newPadding
        if paddingChanged {
            context.coordinator.updatePadding(top: topPadding, bottom: bottomPadding)
            needsUpdate = true
        }
        
        // Check map type changes
        let mapTypeChanged = mapView.mapType != mapType
        if mapTypeChanged {
            mapView.mapType = mapType
            needsUpdate = true
        }

        let shouldForceUpdate = viewModel.forceMapRefresh
        let currentMode = viewModel.mapDisplayMode
        let modeChanged = context.coordinator.lastDisplayMode != currentMode
        let annotationInputSignature = currentMode == .merchants
            ? viewModel.merchantMapAnnotationInputSignature
            : nil

        // Fast path: unrelated parent updates must not re-hash every merchant.
        // A detent selection re-enters updateUIView even though map content is
        // unchanged; hashing ~29k merchants here causes a visible release hitch.
        let canSkipAnnotationHash =
            !shouldForceUpdate &&
            !modeChanged &&
            annotationInputSignature == context.coordinator.lastAnnotationInputSignature &&
            currentMode != .communities

        if canSkipAnnotationHash {
            let elapsed = (CFAbsoluteTimeGetCurrent() - updateStart) * 1000
            if needsUpdate {
                Debug.logMap("⏱ updateUIView: padding/mapType-only in \(elapsed.formatted(.number.precision(.fractionLength(1))))ms")
            }
            return
        }
        
        // Handle elements updates (most important)
        var shouldRefreshAnnotations = false
        var refreshElementsHash: Int?
        var refreshForce = false
        if let elements = elements, !elements.isEmpty {
            // Content-aware hash so name/boost/icon updates invalidate pins even when IDs are unchanged.
            let elementsHash = elements.mapAnnotationsContentHash
            let hashChanged = context.coordinator.lastElementsHash != elementsHash
            context.coordinator.lastAnnotationInputSignature = annotationInputSignature
            
            // Only log details if we're actually going to update
            if hashChanged || shouldForceUpdate {
                Debug.logMap("MapView.updateUIView - Elements update needed:")
                Debug.logMap("   - Elements count: \(elements.count)")
                Debug.logMap("   - Hash changed: \(hashChanged)")
                Debug.logMap("   - Force refresh: \(shouldForceUpdate)")
                
                context.coordinator.lastElementsHash = elementsHash
                shouldRefreshAnnotations = true
                refreshElementsHash = elementsHash
                refreshForce = refreshForce || shouldForceUpdate
                Debug.logMap("Annotations marked for update")
                
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
            context.coordinator.lastAnnotationInputSignature = annotationInputSignature
            if context.coordinator.clearMerchantAnnotations(on: mapView) {
                needsUpdate = true
            }
        }
        
        // Handle community/merchant display mode overlay sync
        if modeChanged || currentMode == .communities {
            context.coordinator.lastDisplayMode = currentMode

            if currentMode == .communities {
                var areaHasher = Hasher()
                if viewModel.communityMapAreas.isEmpty {
                    areaHasher.combine(viewModel.areaBrowserAreas.count)
                    for area in viewModel.areaBrowserAreas {
                        areaHasher.combine(area.id)
                        areaHasher.combine(area.geoJSON?.features.count ?? 0)
                    }
                } else {
                    areaHasher.combine(viewModel.communityMapAreas.count)
                    for area in viewModel.communityMapAreas {
                        areaHasher.combine(area.id)
                        areaHasher.combine(area.geoJSON?.features.count ?? 0)
                    }
                }
                let currentAreaDataHash = areaHasher.finalize()
                let desiredOverlays = viewModel.communityOverlays
                let overlaysChanged =
                    modeChanged ||
                    context.coordinator.lastCommunityAreasHash != currentAreaDataHash ||
                    mapView.overlays.count != desiredOverlays.count
                if overlaysChanged {
                    context.coordinator.lastCommunityAreasHash = currentAreaDataHash
                    // On iPad we reuse the same MKMapView instance, so community overlays
                    // need to be reconciled whenever mode, area data, or overlay count changes.
                    let existingOverlays = Set(mapView.overlays.compactMap { $0 as? MKPolygon })
                    let desiredOverlaySet = Set(desiredOverlays)
                    let toRemove = existingOverlays.subtracting(desiredOverlaySet)
                    let toAdd = desiredOverlaySet.subtracting(existingOverlays)
                    if !toRemove.isEmpty { mapView.removeOverlays(Array(toRemove)) }
                    if !toAdd.isEmpty { mapView.addOverlays(Array(toAdd)) }
                }

                // Only show pins for selected community members.
                if viewModel.isShowingCommunityMembersOnMap {
                    if let elements = elements {
                        shouldRefreshAnnotations = true
                        refreshElementsHash = context.coordinator.lastElementsHash ?? elements.hashValue
                        refreshForce = true
                    }
                } else {
                    let merchantAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
                    if !merchantAnnotations.isEmpty {
                        mapView.removeAnnotations(merchantAnnotations)
                    }
                }
            } else {
                context.coordinator.lastCommunityAreasHash = nil
                // Remove all overlays
                if !mapView.overlays.isEmpty {
                    mapView.removeOverlays(mapView.overlays)
                }
                // Force annotation refresh
                if let elements = elements, !elements.isEmpty {
                    shouldRefreshAnnotations = true
                    refreshElementsHash = context.coordinator.lastElementsHash ?? elements.hashValue
                    refreshForce = true
                }
            }
            needsUpdate = true
        }

        if shouldRefreshAnnotations, let elements = elements, !elements.isEmpty {
            context.coordinator.updateAnnotations(
                mapView: mapView,
                elements: elements,
                elementsHash: refreshElementsHash ?? elements.hashValue,
                force: refreshForce
            )
            Debug.logMap("Annotations updated!")
            needsUpdate = true
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - updateStart) * 1000
        if needsUpdate {
            Debug.logMap("⏱ updateUIView: COMPLETED with changes in \(elapsed.formatted(.number.precision(.fractionLength(1))))ms")
        } else if elapsed > 1.0 {
            Debug.logMap("⏱ updateUIView: no-op but took \(elapsed.formatted(.number.precision(.fractionLength(1))))ms")
        }
    }
    
    // Set up clustering for map annotations
    private func setupCluster(mapView: MKMapView) {
        let clusteringIdentifier = "Cluster"
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: clusteringIdentifier)
    }
    
    // Coordinator class to handle MKMapViewDelegate methods and annotations management
    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private struct AnnotationPassKey: Equatable {
            let elementsHash: Int
            let mapMode: MapDisplayMode
            let showingCommunityMembers: Bool
            let selectedCommunityID: String?
            let viewportMinXBucket: Int
            let viewportMinYBucket: Int
            let viewportMaxXBucket: Int
            let viewportMaxYBucket: Int
        }

        var viewModel: ContentViewModel
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var mapRegionChangeCompletion: (() -> Void)?
        
        // Keep track of previously displayed elements to manage annotations efficiently
        var previousElements: Set<Element> = []
        var currentAnnotations: [String: Annotation] = [:] // Keep track of current annotations
        private var debounceTimer: AnyCancellable?
        private struct SpatialCellKey: Hashable {
            let x: Int
            let y: Int
        }

        private struct SpatialEntry {
            let element: Element
            let latitude: Double
            let longitude: Double
            let mapPoint: MKMapPoint
        }

        private static let spatialCellDegrees: Double = 0.5
        private static let markerTintColor: UIColor? = UIColor(named: "MarkerColor")

        var lastElementsHash: Int?
        var lastAnnotationInputSignature: Int?
        var lastDisplayMode: MapDisplayMode = .merchants
        var lastCommunityAreasHash: Int?
        private var lastAnnotationPassKey: AnnotationPassKey?
        private var hasLoggedInitialAnnotationPass = false
        var lastVisibleElementIDs: [String] = []
        weak var overlayTapRecognizer: UITapGestureRecognizer?
        private var spatialIndexHash: Int?
        private var spatialIndexCount: Int = 0
        private var spatialCells: [SpatialCellKey: [SpatialEntry]] = [:]
        private var spatialAllRenderable: [SpatialEntry] = []
        private var glyphImageCache: [String: UIImage] = [:]

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

        func installCommunityOverlayTapRecognizer(on mapView: MKMapView) {
            if let existing = mapView.gestureRecognizers?.first(where: { $0.name == "communityOverlayTap" }) as? UITapGestureRecognizer {
                existing.removeTarget(nil, action: nil)
                existing.addTarget(self, action: #selector(handleCommunityOverlayTap(_:)))
                existing.delegate = self
                overlayTapRecognizer = existing
                return
            }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleCommunityOverlayTap(_:)))
            recognizer.name = "communityOverlayTap"
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            mapView.addGestureRecognizer(recognizer)
            overlayTapRecognizer = recognizer
        }

        @objc private func handleCommunityOverlayTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView = recognizer.view as? MKMapView,
                  viewModel.mapDisplayMode == .communities else { return }

            let tapPoint = recognizer.location(in: mapView)
            let coordinate = mapView.convert(tapPoint, toCoordinateFrom: mapView)
            let mapPoint = MKMapPoint(coordinate)

            for overlay in mapView.overlays.reversed() {
                guard let polygon = overlay as? MKPolygon else { continue }
                guard let renderer = mapView.renderer(for: polygon) as? MKPolygonRenderer else { continue }
                if renderer.path == nil {
                    renderer.invalidatePath()
                }
                let rendererPoint = renderer.point(for: mapPoint)
                guard let path = renderer.path, path.contains(rendererPoint) else { continue }
                if let areaID = polygon.subtitle, let area = viewModel.communityArea(withID: areaID) {
                    viewModel.selectCommunity(area)
                }
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
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
            
            // Edge padding for header and sheet in compact-sheet mode
            let edgePadding: UIEdgeInsets
            if viewModel.layoutMode == .splitSidebar {
                edgePadding = UIEdgeInsets(top: 10, left: 20, bottom: 20, right: 20)
            } else if viewModel.leadingSheetInset > 1 {
                edgePadding = UIEdgeInsets(
                    top: viewModel.topPadding + 10,
                    left: viewModel.leadingSheetInset + 20,
                    bottom: 20,
                    right: 20
                )
            } else {
                edgePadding = UIEdgeInsets(
                    top: viewModel.topPadding + 10,
                    left: 20,
                    bottom: viewModel.bottomPadding + 100,
                    right: 20
                )
            }
            
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
        
        private func ensureSpatialIndex(for elements: [Element], elementsHash: Int) {
            guard spatialIndexHash != elementsHash || spatialIndexCount != elements.count else {
                return
            }
            spatialIndexHash = elementsHash
            spatialIndexCount = elements.count
            spatialCells.removeAll(keepingCapacity: true)
            spatialAllRenderable.removeAll(keepingCapacity: true)
            spatialAllRenderable.reserveCapacity(elements.count)

            let invCell = 1.0 / Self.spatialCellDegrees
            for element in elements {
                guard (element.deletedAt == nil || element.deletedAt == ""),
                      element.hasMapRenderableIdentity,
                      let coordinate = element.mapCoordinate else { continue }
                let entry = SpatialEntry(
                    element: element,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mapPoint: MKMapPoint(coordinate)
                )
                spatialAllRenderable.append(entry)
                let key = SpatialCellKey(
                    x: Int(floor(coordinate.longitude * invCell)),
                    y: Int(floor(coordinate.latitude * invCell))
                )
                spatialCells[key, default: []].append(entry)
            }
        }

        private func querySpatialCandidates(
            centerLat: Double,
            centerLon: Double,
            cosLat: Double
        ) -> [SpatialEntry] {
            // Near the poles, fall back to the pre-filtered renderable list.
            guard abs(centerLat) < 85.0, cosLat > 0.05 else {
                return spatialAllRenderable
            }

            // 25 miles ≈ 40.23 km ≈ 0.362° latitude; use 0.38° for safe margin.
            let latDelta = 0.38
            let lonDelta = min(180.0, latDelta / cosLat)
            let minLat = max(-90.0, centerLat - latDelta)
            let maxLat = min(90.0, centerLat + latDelta)
            let rawMinLon = centerLon - lonDelta
            let rawMaxLon = centerLon + lonDelta

            let invCell = 1.0 / Self.spatialCellDegrees
            let minY = Int(floor(minLat * invCell))
            let maxY = Int(floor(maxLat * invCell))

            var results: [SpatialEntry] = []
            results.reserveCapacity(128)

            func collect(lonStart: Double, lonEnd: Double) {
                let minX = Int(floor(lonStart * invCell))
                let maxX = Int(floor(lonEnd * invCell))
                guard minX <= maxX, minY <= maxY else { return }
                for x in minX...maxX {
                    for y in minY...maxY {
                        if let bucket = spatialCells[SpatialCellKey(x: x, y: y)] {
                            results.append(contentsOf: bucket)
                        }
                    }
                }
            }

            if rawMinLon < -180.0 {
                collect(lonStart: rawMinLon + 360.0, lonEnd: 180.0)
                collect(lonStart: -180.0, lonEnd: rawMaxLon)
            } else if rawMaxLon > 180.0 {
                collect(lonStart: rawMinLon, lonEnd: 180.0)
                collect(lonStart: -180.0, lonEnd: rawMaxLon - 360.0)
            } else {
                collect(lonStart: rawMinLon, lonEnd: rawMaxLon)
            }

            return results
        }
        
        // Efficiently update annotations by only adding/removing what's changed
        func updateAnnotations(mapView: MKMapView, elements: [Element]?, elementsHash: Int, force: Bool = false) {
            let annStart = CFAbsoluteTimeGetCurrent()
            guard let elements = elements else { return }

            if !hasLoggedInitialAnnotationPass {
                hasLoggedInitialAnnotationPass = true
                Debug.logTiming("map", "initial annotation pass started (elements=\(elements.count), force=\(force))")
            }

            let allowedCommunityIDs: Set<String>?
            if viewModel.mapDisplayMode == .communities,
               viewModel.selectedCommunityArea != nil,
               !viewModel.communityMemberElementIDs.isEmpty {
                allowedCommunityIDs = viewModel.communityMemberElementIDs
            } else {
                allowedCommunityIDs = nil
            }

            let viewportRect = effectiveViewportRect(for: mapView)
            let centerPoint = CGPoint(x: viewportRect.midX, y: viewportRect.midY)
            let centerCoordinate = mapView.convert(centerPoint, toCoordinateFrom: mapView)

            let visibleRect = effectiveVisibleMapRect(for: mapView, viewportRect: viewportRect)
            let maxDistanceMeters = 25.0 * 1609.344
            let centerLat = centerCoordinate.latitude
            let centerLon = centerCoordinate.longitude
            let viewportBucketScale = 1_000.0
            let currentKey = AnnotationPassKey(
                elementsHash: elementsHash,
                mapMode: viewModel.mapDisplayMode,
                showingCommunityMembers: viewModel.isShowingCommunityMembersOnMap,
                selectedCommunityID: viewModel.selectedCommunityArea?.id,
                viewportMinXBucket: Int((visibleRect.minX / viewportBucketScale).rounded()),
                viewportMinYBucket: Int((visibleRect.minY / viewportBucketScale).rounded()),
                viewportMaxXBucket: Int((visibleRect.maxX / viewportBucketScale).rounded()),
                viewportMaxYBucket: Int((visibleRect.maxY / viewportBucketScale).rounded())
            )
            if !force, lastAnnotationPassKey == currentKey {
                return
            }
            lastAnnotationPassKey = currentKey

            ensureSpatialIndex(for: elements, elementsHash: elementsHash)

            let degToRad = Double.pi / 180.0
            let cosLat = cos(centerLat * degToRad)
            let maxDistanceRatio = maxDistanceMeters / 6_371_000.0
            let maxDistanceSq = maxDistanceRatio * maxDistanceRatio
            let candidates = querySpatialCandidates(centerLat: centerLat, centerLon: centerLon, cosLat: cosLat)

            var visibleElements: [Element] = []
            visibleElements.reserveCapacity(min(candidates.count, 128))
            var newByID: [String: Element] = [:]
            newByID.reserveCapacity(min(candidates.count, 128))

            for entry in candidates {
                if let allowedCommunityIDs, !allowedCommunityIDs.contains(entry.element.id) {
                    continue
                }
                guard visibleRect.contains(entry.mapPoint) else { continue }

                let dLat = (entry.latitude - centerLat) * degToRad
                var rawDLon = entry.longitude - centerLon
                if rawDLon > 180.0 { rawDLon -= 360.0 }
                else if rawDLon < -180.0 { rawDLon += 360.0 }
                let dLon = rawDLon * degToRad * cosLat
                guard (dLat * dLat + dLon * dLon) <= maxDistanceSq else { continue }

                let id = entry.element.id
                if newByID[id] == nil {
                    visibleElements.append(entry.element)
                }
                // Keep latest record for duplicate IDs (last-wins, matching IdentifiableIndex.byID).
                newByID[id] = entry.element
            }

            let existingAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
            var existingByID: [String: Annotation] = [:]
            existingByID.reserveCapacity(existingAnnotations.count)
            for annotation in existingAnnotations {
                if let elementID = annotation.element?.id {
                    existingByID[elementID] = annotation
                }
            }

            let referenceDate = Date.now

            // Drop pins that left the viewport, and pins whose map-facing content changed
            // (name, boost, icon) so marker tint/title stay current.
            let annotationsToRemove = existingByID.compactMap { id, annotation -> Annotation? in
                guard let latest = newByID[id] else { return annotation }
                let existingSignature = annotation.element?.mapAnnotationContentSignature
                let latestSignature = latest.mapAnnotationContentSignature
                let boostChanged = (annotation.element?.isCurrentlyBoosted(referenceDate: referenceDate) ?? false)
                    != latest.isCurrentlyBoosted(referenceDate: referenceDate)
                if existingSignature != latestSignature || boostChanged {
                    return annotation
                }
                return nil
            }
            let removedIDs = Set(annotationsToRemove.compactMap { $0.element?.id })
            let elementsToAdd = newByID.compactMap { id, element -> Element? in
                if existingByID[id] == nil || removedIDs.contains(id) {
                    return element
                }
                return nil
            }

            if !annotationsToRemove.isEmpty {
                mapView.removeAnnotations(annotationsToRemove)
            }
            if !elementsToAdd.isEmpty {
                let newAnnotations = elementsToAdd.map { Annotation(element: $0) }
                mapView.addAnnotations(newAnnotations)
            }

            let visibleIDs = visibleElements.map(\.id)
            if visibleIDs != lastVisibleElementIDs {
                lastVisibleElementIDs = visibleIDs
                let refreshedVisibleElements = visibleIDs.compactMap { newByID[$0] }
                Debug.logTiming(
                    "map",
                    "publishing visible elements -> count=\(refreshedVisibleElements.count), annotations=\(mapView.annotations.compactMap { $0 as? Annotation }.count)"
                )
                self.viewModel.visibleElementsSubject.send(refreshedVisibleElements)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - annStart) * 1000
            Debug.logMap("⏱ updateAnnotations: \(elements.count) source (\(candidates.count) candidates) → \(visibleElements.count) visible, removed \(annotationsToRemove.count), added \(elementsToAdd.count) in \(elapsed.formatted(.number.precision(.fractionLength(1))))ms")
        }

        @discardableResult
        func clearMerchantAnnotations(on mapView: MKMapView) -> Bool {
            let currentAnnotations = mapView.annotations.compactMap { $0 as? Annotation }
            guard !currentAnnotations.isEmpty || lastElementsHash != nil || !lastVisibleElementIDs.isEmpty else {
                return false
            }

            if !currentAnnotations.isEmpty {
                Debug.logMap("MapView.updateUIView: Clearing \(currentAnnotations.count) annotations")
                mapView.removeAnnotations(currentAnnotations)
            }

            // Reset annotation caches so the same search result IDs can be re-added
            // after transient empty states during search refinement.
            lastElementsHash = nil
            lastVisibleElementIDs = []
            lastAnnotationPassKey = nil
            return true
        }

        // MARK: - MKMapViewDelegate Methods
        
        private func cachedGlyphImage(for symbolName: String) -> UIImage? {
            if let cached = glyphImageCache[symbolName] {
                return cached
            }
            guard let rendered = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
                return nil
            }
            glyphImageCache[symbolName] = rendered
            return rendered
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let reuseIdentifier = "AnnotationView"
            var view: MKMarkerAnnotationView?
            
            if let cluster = annotation as? MKClusterAnnotation {
                // Handle cluster annotations
                view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                view?.markerTintColor = Self.markerTintColor
                let count = cluster.memberAnnotations.count
                view?.glyphText = "\(count)"
                view?.accessibilityLabel = String(
                    AttributedString(
                        localized: "^[\(count) Bitcoin merchant](inflect: true)",
                        comment: "VoiceOver label for a map cluster of merchants"
                    ).characters
                )
                view?.accessibilityTraits = .button
                view?.accessibilityHint = NSLocalizedString(
                    "Double tap to zoom into this cluster",
                    comment: "VoiceOver hint for merchant map clusters"
                )
            } else if let annotation = annotation as? Annotation {
                // Handle individual annotations — never crash on missing element.
                guard let element = annotation.element else {
                    Debug.logMap("Skipping annotation view: element is nil")
                    return nil
                }
                view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                view?.clusteringIdentifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                view?.canShowCallout = true
                view?.glyphText = nil
                view?.glyphTintColor = .white
                let isBoosted = element.isCurrentlyBoosted()
                view?.markerTintColor = isBoosted ? .systemOrange : Self.markerTintColor
                let symbolName = ElementCategorySymbols.symbolName(for: element)
                Debug.logMap("Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                view?.glyphImage = cachedGlyphImage(for: symbolName)
                view?.accessibilityLabel = Self.accessibilityLabel(for: element, isBoosted: isBoosted)
                view?.accessibilityTraits = .button
                view?.accessibilityHint = NSLocalizedString(
                    "Double tap to open merchant details",
                    comment: "VoiceOver hint for individual merchant map pins"
                )
                view?.displayPriority = .required
            }
            return view
        }

        private static func accessibilityLabel(for element: Element, isBoosted: Bool) -> String {
            let name = element.displayNameForUI
                ?? element.displayName
                ?? NSLocalizedString("Bitcoin merchant", comment: "Fallback VoiceOver name for unnamed merchant pin")
            var parts = [name]
            if isBoosted {
                parts.append(NSLocalizedString("Featured", comment: "VoiceOver flag for boosted merchants"))
            }
            var methods: [String] = []
            if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
                methods.append(NSLocalizedString("On-chain Bitcoin", comment: "VoiceOver payment method"))
            }
            if acceptsLightning(element: element) {
                methods.append(NSLocalizedString("Lightning", comment: "VoiceOver payment method"))
            }
            if acceptsContactlessLightning(element: element) {
                methods.append(NSLocalizedString("Contactless Lightning", comment: "VoiceOver payment method"))
            }
            if !methods.isEmpty {
                parts.append(methods.formatted())
            }
            return parts.joined(separator: ". ")
        }
        
        // Handle annotation selection to update navigation path
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if viewModel.selectionSource == .list {
                viewModel.setSelectionSource(.unknown)
                return
            }
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
                
                // Edge padding to respect header and sheet in compact-sheet mode
                let edgePadding: UIEdgeInsets
                if viewModel.layoutMode == .splitSidebar {
                    edgePadding = UIEdgeInsets(top: 10, left: 20, bottom: 20, right: 20)
                } else if viewModel.leadingSheetInset > 1 {
                    edgePadding = UIEdgeInsets(
                        top: viewModel.topPadding + 10,
                        left: viewModel.leadingSheetInset + 20,
                        bottom: 20,
                        right: 20
                    )
                } else {
                    edgePadding = UIEdgeInsets(
                        top: viewModel.topPadding + 10,
                        left: 20,
                        bottom: viewModel.bottomPadding + 100,
                        right: 20
                    )
                }
                
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
                    self.viewModel.setSelectionSource(.mapAnnotation)
                    self.viewModel.path = [.place(element)] // Update path for NavigationStack
                    self.viewModel.selectedElement = element // Update the selected element
                    
                    Debug.logMap("Annotation tapped: \(element)")
                }
            }
        }
        
        
        // Detect when the map region changes
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            Debug.logTiming(
                "onboarding",
                "regionDidChangeAnimated(animated=\(animated), ready=\(viewModel.isReadyForPostOnboardingPresentation), settle=\(viewModel.isReadyForPostOnboardingPresentation ? "n/a" : "pending"))"
            )
            if animated || !viewModel.isReadyForPostOnboardingPresentation {
                Debug.logTiming(
                    "map",
                    "regionDidChangeAnimated(animated=\(animated), ready=\(viewModel.isReadyForPostOnboardingPresentation))"
                )
            }

            // Update the view model's region to match the map's region
            if viewModel.initialRegionSet {
                self.viewModel.syncRegionFromMap(center: mapView.region.center, span: mapView.region.span)
            }
            
            // Debounce the call to update annotations
            debounceTimer?.cancel()
            debounceTimer = Just(())
                .delay(for: .seconds(0.5), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    guard self.viewModel.isReadyForPostOnboardingPresentation else {
                        self.viewModel.mapStoppedMovingSubject.send(())
                        return
                    }
                    let all = self.viewModel.mapElementsForCurrentDisplay
                    self.updateAnnotations(
                        mapView: mapView,
                        elements: all,
                        elementsHash: all.mapAnnotationsContentHash,
                        force: false
                    )
                }
            
            if animated, let completion = mapRegionChangeCompletion {
                // Trigger completion handler
                mapRegionChangeCompletion = nil // Reset to avoid repeated calls
                completion()
            }
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered else { return }
            Debug.logTiming("map", "mapViewDidFinishRenderingMap fullyRendered=true")
            viewModel.notifyPostOnboardingMapRenderFinished()
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = UIColor(named: "MarkerColor") ?? .systemOrange
                renderer.lineWidth = 2
                renderer.fillColor = (UIColor(named: "MarkerColor") ?? .systemOrange).withAlphaComponent(0.15)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // Update visible elements based on annotations in the visible map rect
        func updateVisibleElements(for mapView: MKMapView) {
            let viewportRect = effectiveViewportRect(for: mapView)
            let visibleRect = effectiveVisibleMapRect(for: mapView, viewportRect: viewportRect)
            let visibleAnnotations = mapView.annotations(in: visibleRect)
            let visibleElements = visibleAnnotations.compactMap { ($0 as? Annotation)?.element }
            let latestByID = IdentifiableIndex.byID(self.viewModel.allElements)
            let refreshed = visibleElements.compactMap { latestByID[$0.id] ?? $0 }

            self.viewModel.visibleElementsSubject.send(refreshed)
            self.viewModel.mapStoppedMovingSubject.send(())
        }

        private func effectiveViewportRect(for mapView: MKMapView) -> CGRect {
            if viewModel.mapDisplayMode == .merchants {
                return mapView.bounds
            }
            return viewModel.mapListViewportRect(for: mapView)
        }

        private func effectiveVisibleMapRect(for mapView: MKMapView, viewportRect: CGRect) -> MKMapRect {
            viewModel.mapRect(for: viewportRect, in: mapView)
        }
    }
}
