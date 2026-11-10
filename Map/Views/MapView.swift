//
//  MapView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import MapKit
import Foundation // for Debug logging
import BitLocalDomain
import BitLocalMap

struct MapView: UIViewRepresentable {
    @EnvironmentObject var viewModel: ContentViewModel
    
    // Properties for Dynamic Padding
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    
    // Propery for map type selection
    var mapType: MKMapType

    /// Redesign phase 4: changes when the store-backed map pass has new pins.
    var storeRenderToken: Int

    // Initializer
    init(topPadding: CGFloat, bottomPadding: CGFloat, mapType: MKMapType, storeRenderToken: Int = -1) {
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.mapType = mapType
        self.storeRenderToken = storeRenderToken
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
            context.coordinator.installPlacesRotor(on: existingMap)
            existingMap.showsUserLocation = true
            existingMap.tintColor = MapView.userLocationTint
            existingMap.mapType = mapType
            return existingMap
        }
        let mapView = MKMapView()
        
        Debug.log("MapView.makeUIView() called - creating new MKMapView")
        
        // Store the reference right away (it isn't published, so this doesn't touch
        // SwiftUI state). Deferring it let a second makeUIView in the same pass (the
        // first layout switch on iPad) build a second map; the first-launch center then
        // landed on the map that was thrown away.
        viewModel.mapView = mapView
        
        // Set the delegate to the Coordinator
        mapView.delegate = context.coordinator
        context.coordinator.installCommunityOverlayTapRecognizer(on: mapView)
        context.coordinator.installPlacesRotor(on: mapView)
        
        // Show user location on the map, in blue: an orange dot read as one more pin.
        mapView.showsUserLocation = true
        mapView.tintColor = MapView.userLocationTint
        
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
                if self.viewModel.centerMap(to: userLocation.coordinate, force: true) {
                    self.viewModel.initialRegionSet = true
                }
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
            let currentAnnotations = mapView.annotations.filter { $0 is Annotation || $0 is StoreClusterAnnotation }
            if !currentAnnotations.isEmpty {
                mapView.removeAnnotations(currentAnnotations)
            }
            context.coordinator.isInStoreMode = false
            Debug.logTiming(
                "onboarding",
                "MapView.updateUIView skipped -> waiting for post-onboarding settle (existingAnnotations=\(currentAnnotations.count))"
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

        // Every map mode draws from the store pass (phases 4, 8i, 8j). Until the
        // store holds merchants on a first launch, the map shows no pins.
        if context.coordinator.storeModeActive {
            context.coordinator.syncStoreMode(on: mapView)
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - updateStart) * 1000
        if needsUpdate {
            Debug.logMap("⏱ updateUIView: padding/mapType changed in \(String(format: "%.1f", elapsed))ms")
        }
    }

    // Coordinator class to handle MKMapViewDelegate methods and annotations management
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var viewModel: ContentViewModel
        var topPadding: CGFloat
        var bottomPadding: CGFloat

        weak var overlayTapRecognizer: UITapGestureRecognizer?

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

        // MARK: - Store-backed map (redesign phase 4)

        var isInStoreMode = false
        private var renderedStoreRevision = -1
        private var lastStoreVisibleIDs: [String] = []
        /// Store rows need a legacy `Element` to become pins (DECISIONS 33). On a fresh
        /// install the element cache fills after the store, so a store pass made before
        /// that drew nothing; redraw whenever the element cache grows or its elements
        /// change (`mapPinRevision`).
        private var renderedElementState: (count: Int, revision: Int) = (-1, -1)

        /// Every map mode draws pins from the store pass once the store has data.
        /// Search, digests and community members narrow it with `MapModel.restriction`;
        /// community area outlines are overlays reconciled alongside (phase 8j).
        var storeModeActive: Bool {
            MainActor.assumeIsolated {
                StoreMap.shared.isReady && StoreMap.shared.model != nil
            }
        }

        /// Community outlines in Communities mode, none otherwise.
        private func syncStoreOverlays(on mapView: MKMapView) {
            let existing = Set(mapView.overlays.compactMap { $0 as? MKPolygon })
            let desired: Set<MKPolygon> = viewModel.mapDisplayMode == .communities
                ? Set(viewModel.communityOverlays)
                : []
            let toRemove = existing.subtracting(desired)
            let toAdd = desired.subtracting(existing)
            if !toRemove.isEmpty { mapView.removeOverlays(Array(toRemove)) }
            if !toAdd.isEmpty { mapView.addOverlays(Array(toAdd)) }
            let stray = mapView.overlays.filter { !($0 is MKPolygon) }
            if !stray.isEmpty { mapView.removeOverlays(stray) }
        }

        func syncStoreMode(on mapView: MKMapView) {
            MainActor.assumeIsolated {
                guard let model = StoreMap.shared.model else { return }
                let restriction = viewModel.storeMapRestriction
                if model.restriction != restriction { model.restriction = restriction }
                syncStoreOverlays(on: mapView)
                if !isInStoreMode {
                    isInStoreMode = true
                    renderedStoreRevision = -1
                    lastStoreVisibleIDs = []
                    if let viewport = storeViewport(for: mapView) {
                        model.cameraDidChange(viewport)
                        model.refresh()
                    }
                }
                let elementState = (count: viewModel.allElements.count, revision: viewModel.mapPinRevision)
                if elementState != renderedElementState {
                    renderedElementState = elementState
                    renderedStoreRevision = -1
                    lastStoreVisibleIDs = []
                }
                if model.revision != renderedStoreRevision {
                    applyStoreItems(model, on: mapView)
                }
            }
        }

        /// The camera as the store pass needs it. The list sorts from the center of the
        /// unobscured map (above the sheet), matching what the user sees.
        func storeViewport(for mapView: MKMapView) -> MapViewport? {
            let visible = mapView.visibleMapRect
            guard mapView.bounds.width > 0, visible.size.width > 0 else { return nil }
            let region = mapView.region
            let rect = GeoRect(
                center: Coordinate(latitude: region.center.latitude, longitude: region.center.longitude),
                latitudeDelta: region.span.latitudeDelta,
                longitudeDelta: region.span.longitudeDelta
            )
            let focusRect = viewModel.mapListViewportRect(for: mapView)
            let focus = mapView.convert(CGPoint(x: focusRect.midX, y: focusRect.midY), toCoordinateFrom: mapView)
            let worldSize = Double(mapView.bounds.width) * MKMapSize.world.width / visible.size.width
            return MapViewport(
                rect: rect,
                center: Coordinate(latitude: focus.latitude, longitude: focus.longitude),
                worldSize: worldSize
            )
        }

        private func applyStoreItems(_ model: MapModel, on mapView: MKMapView) {
            let start = CFAbsoluteTimeGetCurrent()
            renderedStoreRevision = model.revision

            var desiredPins: [String: (Element, String)] = [:]
            var desiredClusters: [String: StoreClusterAnnotation] = [:]
            for item in model.items {
                switch item {
                case .merchant(let summary):
                    let id = String(summary.id.rawValue)
                    // Pins need the legacy element for detail until phase 5 reads from the store.
                    guard let element = viewModel.cachedElement(id: id) else { continue }
                    let key = "m\(id)|\(element.mapAnnotationContentSignature)|\(element.isCurrentlyBoosted())"
                    desiredPins[key] = (element, key)
                case let .cluster(clusterID, coordinate, count, memberIDs, _):
                    let key = "c\(clusterID.zoomBucket)|\(clusterID.cellX)|\(clusterID.cellY)|\(count)"
                    desiredClusters[key] = StoreClusterAnnotation(
                        storeKey: key,
                        coordinate: coordinate,
                        count: count,
                        memberIDs: memberIDs,
                        isColocated: clusterID.zoomBucket >= MerchantClusterer.colocatedOnlyBucket
                    )
                }
            }

            var toRemove: [MKAnnotation] = []
            var existingKeys = Set<String>()
            for annotation in mapView.annotations {
                if let pin = annotation as? StoreMerchantAnnotation {
                    if desiredPins[pin.storeKey] == nil { toRemove.append(pin) } else { existingKeys.insert(pin.storeKey) }
                } else if let cluster = annotation as? StoreClusterAnnotation {
                    if desiredClusters[cluster.storeKey] == nil { toRemove.append(cluster) } else { existingKeys.insert(cluster.storeKey) }
                }
            }
            var toAdd: [MKAnnotation] = []
            for (key, pin) in desiredPins where !existingKeys.contains(key) {
                toAdd.append(StoreMerchantAnnotation(element: pin.0, storeKey: pin.1))
            }
            for (key, cluster) in desiredClusters where !existingKeys.contains(key) {
                toAdd.append(cluster)
            }
            if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
            if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }

            let visibleIDs = model.visibleSummaries.map { String($0.id.rawValue) }
            if visibleIDs != lastStoreVisibleIDs {
                lastStoreVisibleIDs = visibleIDs
                let elements = visibleIDs.compactMap { viewModel.cachedElement(id: $0) }
                viewModel.visibleElementsSubject.send(elements)
            }
            viewModel.mapStoppedMovingSubject.send(())
            Debug.logMap("⏱ store pass: \(model.items.count) items (+\(toAdd.count) −\(toRemove.count)), list \(visibleIDs.count)/\(model.visibleCount) in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
        }

        private func zoomInto(_ cluster: StoreClusterAnnotation, on mapView: MKMapView) {
            mapView.deselectAnnotation(cluster, animated: false)
            if cluster.isColocated {
                // "N places here": phase 5 shows a card; for now open the first one.
                if let first = cluster.memberIDs.first, let element = viewModel.cachedElement(id: String(first.rawValue)) {
                    viewModel.setSelectionSource(.mapAnnotation)
                    viewModel.path = [element]
                    viewModel.selectedElement = element
                }
                return
            }
            let span = mapView.region.span
            let region = MKCoordinateRegion(
                center: cluster.coordinate,
                span: MKCoordinateSpan(latitudeDelta: span.latitudeDelta / 4, longitudeDelta: span.longitudeDelta / 4)
            )
            mapView.setRegion(mapView.regionThatFits(region), animated: true)
        }

        /// VoiceOver "Places" rotor (ui-redesign 7): steps through the pins and
        /// clusters on screen in reading order, top to bottom, then left to right.
        func installPlacesRotor(on mapView: MKMapView) {
            let rotor = UIAccessibilityCustomRotor(name: String(localized: "Places")) { [weak mapView] predicate in
                guard let mapView else { return nil }
                let views = mapView.annotations(in: mapView.visibleMapRect)
                    .compactMap { $0.base as? MKAnnotation }
                    .filter { !($0 is MKUserLocation) }
                    .sorted { lhs, rhs in
                        if lhs.coordinate.latitude != rhs.coordinate.latitude {
                            return lhs.coordinate.latitude > rhs.coordinate.latitude
                        }
                        return lhs.coordinate.longitude < rhs.coordinate.longitude
                    }
                    .compactMap { mapView.view(for: $0) }
                    .filter { !$0.isHidden }
                guard !views.isEmpty else { return nil }

                let currentIndex = (predicate.currentItem.targetElement as? UIView)
                    .flatMap { current in views.firstIndex { $0 === current } }
                let nextIndex: Int
                switch predicate.searchDirection {
                case .next:
                    nextIndex = currentIndex.map { $0 + 1 } ?? 0
                case .previous:
                    nextIndex = currentIndex.map { $0 - 1 } ?? views.count - 1
                @unknown default:
                    return nil
                }
                guard views.indices.contains(nextIndex) else { return nil }
                return UIAccessibilityCustomRotorItemResult(targetElement: views[nextIndex], targetRange: nil)
            }
            mapView.accessibilityCustomRotors = [rotor]
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
        
        // MARK: - MKMapViewDelegate Methods
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let reuseIdentifier = "AnnotationView"
            var view: MKMarkerAnnotationView?
            
            if let cluster = annotation as? StoreClusterAnnotation {
                let clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: StoreClusterBubbleView.reuseIdentifier) as? StoreClusterBubbleView
                    ?? StoreClusterBubbleView(annotation: cluster, reuseIdentifier: StoreClusterBubbleView.reuseIdentifier)
                clusterView.annotation = cluster
                clusterView.accessibilityHint = NSLocalizedString(
                    "Double tap to zoom into this cluster",
                    comment: "VoiceOver hint for merchant map clusters"
                )
                return clusterView
            } else if let annotation = annotation as? Annotation {
                // Handle individual annotations — never crash on missing element.
                guard let element = annotation.element else {
                    Debug.logMap("Skipping annotation view: element is nil")
                    return nil
                }
                view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                view?.annotation = annotation
                // Pins are clustered by BitLocal already; MapKit must not regroup them.
                view?.clusteringIdentifier = nil
                view?.canShowCallout = true
                view?.glyphText = nil
                view?.glyphTintColor = .white
                view?.markerTintColor = element.isCurrentlyBoosted() ? .systemOrange : UIColor(named: "MarkerColor")
                // The name shows once there's room; the subtitle (address) never does.
                view?.titleVisibility = .adaptive
                view?.subtitleVisibility = .hidden
                let symbolName = ElementCategorySymbols.badgeSymbolName(for: element)
                Debug.logMap("Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                view?.glyphImage = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                view?.accessibilityLabel = accessibilityLabel(for: element)
                view?.accessibilityTraits = .button
                view?.accessibilityHint = NSLocalizedString(
                    "Double tap to open merchant details",
                    comment: "VoiceOver hint for individual merchant map pins"
                )
                view?.displayPriority = .required
            }
            return view
        }

        /// "Prickly Pear Coffee Co., Featured, Coffee shop, 0.3 mi, Lightning, Open" (ui-redesign 7).
        private func accessibilityLabel(for element: Element) -> String {
            let name = element.displayNameForUI
                ?? element.displayName
                ?? NSLocalizedString("Bitcoin merchant", comment: "Fallback VoiceOver name for unnamed merchant pin")
            var parts = [name]
            if element.isCurrentlyBoosted() {
                parts.append(NSLocalizedString("Featured", comment: "VoiceOver flag for boosted merchants"))
            }
            let summary = element.merchant?.summary
            if let summary,
               let category = ElementCategorySymbols.friendlyCategoryLabel(forIcon: summary.category.rawValue) {
                parts.append(category)
            }
            if let userLocation = viewModel.userLocation, let coordinate = element.mapCoordinate {
                let distance = userLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                let formatter = MKDistanceFormatter()
                formatter.unitStyle = .full
                parts.append(formatter.string(fromDistance: distance))
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
                parts.append(methods.joined(separator: ", "))
            }
            if let hours = OpeningHours.parse(summary?.openingHours) {
                parts.append(OpeningHoursText.status(hours.status(at: .now)).state)
            }
            return parts.joined(separator: ", ")
        }
        
        // Handle annotation selection to update navigation path
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if viewModel.selectionSource == .list {
                viewModel.setSelectionSource(.unknown)
                return
            }
            if let cluster = view.annotation as? StoreClusterAnnotation {
                zoomInto(cluster, on: mapView)
                return
            }
            if let annotation = view.annotation as? Annotation, let element = annotation.element {
                // Restore the logic to display BusinessDetailView
                DispatchQueue.main.async {
                    self.viewModel.setSelectionSource(.mapAnnotation)
                    self.viewModel.path = [element] // Update path for NavigationStack
                    self.viewModel.selectedElement = element // Update the selected element
                    
                    Debug.logMap("Annotation tapped: \(element)")
                }
            }
        }
        
        
        /// MapKit's own location fix. On a fresh iPad install with location already
        /// allowed, Core Location's delegate never delivered a fix to the view model, so
        /// the map showed the blue dot in the right place while staying zoomed out on the
        /// continent and sorting the list from the map's center. Adopt MapKit's fix then.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location else { return }
            MainActor.assumeIsolated {
                viewModel.adoptMapUserLocationIfNeeded(location)
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
            
            // MapModel debounces and cancels on its own.
            if viewModel.isReadyForPostOnboardingPresentation, storeModeActive, isInStoreMode,
               let viewport = storeViewport(for: mapView) {
                MainActor.assumeIsolated { StoreMap.shared.model?.cameraDidChange(viewport) }
            } else {
                viewModel.mapStoppedMovingSubject.send(())
            }
        }

        /// New pins and clusters settle in instead of popping: a short fade with a
        /// small scale (never from zero). Reduce Motion keeps only the fade.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            for view in views where !(view.annotation is MKUserLocation) {
                view.alpha = 0
                if !reduceMotion { view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85) }
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
                ) {
                    view.alpha = 1
                    view.transform = .identity
                }
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
    }
}

extension MapView {
    /// The user's own location: system blue, so it never reads as a merchant pin.
    static let userLocationTint = UIColor.systemBlue
}

/// A cluster from `MerchantClusterer`: a round count bubble with a soft outer halo, so
/// it reads as "several places" at a glance and never as one more pin. It grows a
/// little with the count. Drawn once per count/size/appearance and cached.
final class StoreClusterBubbleView: MKAnnotationView {
    static let reuseIdentifier = "StoreClusterBubble"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StoreClusterBubbleView, _: UITraitCollection) in
            view.render()
        }
        render()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { nil }

    override var annotation: MKAnnotation? {
        didSet { render() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
        transform = .identity
    }

    private func render() {
        guard let cluster = annotation as? StoreClusterAnnotation else { return }
        image = Self.bubble(text: cluster.glyphText, diameter: Self.diameter(for: cluster.count), traits: traitCollection)
        accessibilityLabel = cluster.title
    }

    static func diameter(for count: Int) -> CGFloat {
        switch count {
        case ..<10: 32
        case ..<100: 38
        case ..<1_000: 44
        default: 50
        }
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    private static func bubble(text: String, diameter: CGFloat, traits: UITraitCollection) -> UIImage {
        let isDark = traits.userInterfaceStyle == .dark
        let key = "\(text)|\(diameter)|\(isDark)"
        if let cached = cache[key] { return cached }

        let halo: CGFloat = 5
        let side = diameter + halo * 2
        let brand = UIColor(named: "MarkerColor") ?? .systemOrange
        let format = UIGraphicsImageRendererFormat.preferred()
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let outer = CGRect(x: 0, y: 0, width: side, height: side)
            brand.withAlphaComponent(isDark ? 0.32 : 0.24).setFill()
            UIBezierPath(ovalIn: outer).fill()

            let disc = outer.insetBy(dx: halo, dy: halo)
            brand.setFill()
            UIBezierPath(ovalIn: disc).fill()
            let stroke = UIBezierPath(ovalIn: disc.insetBy(dx: 1, dy: 1))
            stroke.lineWidth = 2
            UIColor.white.setStroke()
            stroke.stroke()

            let size = diameter * (text.count > 2 ? 0.34 : 0.42)
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font.withMonospacedDigits(),
                .foregroundColor: UIColor.white
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: disc.midX - textSize.width / 2, y: disc.midY - textSize.height / 2),
                withAttributes: attributes
            )
        }
        cache[key] = image
        return image
    }
}

private extension UIFont {
    func withMonospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
