import SwiftUI
import Combine
import CoreLocation
import MapKit
import Foundation

extension ContentViewModel {
    func updateLayoutMode(_ newMode: AppLayoutMode) {
        guard layoutMode != newMode else { return }
        layoutMode = newMode
        pendingSheetDetentHeight = nil
        if newMode == .splitSidebar {
            leadingSheetInset = 0
            if topPadding != 0 {
                topPadding = 0
            }
            if bottomPadding != 0 {
                bottomPadding = 0
            }
        }
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

    /// Continuous sheet height while the bottom sheet is dragged.
    /// Publishes only through `sheetGeometry`, never through this object.
    func reportSheetHeight(_ height: CGFloat) {
        sheetGeometry.reportMeasuredHeight(height)
    }

    /// Snap settled map padding when a presentation detent selection settles.
    /// `estimatedHeight` is only used when no live sheet measurement exists yet.
    func reportSheetDetentSettled(estimatedHeight: CGFloat) {
        pendingSheetDetentHeight = nil
        sheetGeometry.reportDetentSettledHeight(estimatedHeight)
        syncBottomPaddingFromSettledGeometry()
    }

    /// Records the selected target without publishing through this view model.
    /// SwiftUI updates the detent binding at the start of the snap animation.
    func prepareForSheetDetentTransition(estimatedHeight: CGFloat) {
        guard estimatedHeight > 1 else { return }
        pendingSheetDetentHeight = estimatedHeight
    }

    /// Commits map padding only after the measured sheet edge stops moving.
    func reportSheetMotionSettled(_ measuredHeight: CGFloat) {
        guard let estimatedHeight = pendingSheetDetentHeight else { return }
        pendingSheetDetentHeight = nil

        let resolvedHeight = measuredHeight > 1 ? measuredHeight : estimatedHeight
        sheetGeometry.reportMeasuredHeight(resolvedHeight)
        sheetGeometry.reportDetentSettledHeight(resolvedHeight)
        syncBottomPaddingFromSettledGeometry()
    }

    private func syncBottomPaddingFromSettledGeometry() {
        let settled = sheetGeometry.settledHeight
        guard settled > 1, abs(bottomPadding - settled) >= 0.5 else { return }
        bottomPadding = settled
    }

    func mapListViewportInsets(for mapView: MKMapView) -> UIEdgeInsets {
        guard layoutMode == .compactSheet else {
            return .zero
        }
        let topInset = max(topPadding, 0)
        if leadingSheetInset > 1 {
            let clampedLeft = min(leadingSheetInset, max(mapView.bounds.width - 1, 0))
            return UIEdgeInsets(top: topInset, left: clampedLeft, bottom: 0, right: 0)
        }
        let bottomInset = effectiveIPhoneViewportBottomInset(mapHeight: mapView.bounds.height)
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

    func merchantAlertElements(for digest: CityDigest) -> [Element] {
        let ids = digest.merchantIDs
        guard !ids.isEmpty else { return [] }

        return merchantElementStore.elements(ids: ids)
    }

    func merchantAlertMissingIDs(for digest: CityDigest) -> [String] {
        let currentIDs = Set(allElements.map(\.id))
        return digest.merchantIDs.filter { !currentIDs.contains($0) }
    }

    func fitMapToMerchantAlertElements(_ elements: [Element], animated: Bool) {
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
            guard let minLat = latitudes.min(),
                  let maxLat = latitudes.max(),
                  let minLon = longitudes.min(),
                  let maxLon = longitudes.max() else {
                return
            }
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
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
        self.region = adjustedRegion
        mapView.setRegion(adjustedRegion, animated: animated)
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
    
    func setupCenterMapSubscription() {
        centerMapToCoordinateSubject
            .sink { [weak self] coordinate in
                guard let self = self, let mapView = self.mapView else {
                    Debug.log("Cannot center map - mapView missing")
                    return
                }
                let newZoomLevel = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                let region = MKCoordinateRegion(center: coordinate, span: newZoomLevel)
                let edgePadding: UIEdgeInsets
                if layoutMode == .splitSidebar {
                    edgePadding = UIEdgeInsets(top: 10, left: 20, bottom: 20, right: 20)
                } else if leadingSheetInset > 1 {
                    edgePadding = UIEdgeInsets(
                        top: topPadding + 10,
                        left: leadingSheetInset + 20,
                        bottom: 20,
                        right: 20
                    )
                } else {
                    edgePadding = UIEdgeInsets(
                        top: topPadding + 10,
                        left: 20,
                        bottom: bottomPadding + 100,
                        right: 20
                    )
                }
                
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
                // In split sidebar mode, center with no sheet inset so the map pane centers the user dot visually.
                if self.layoutMode == .splitSidebar {
                    let edgePadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
                    mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: true)
                } else if self.leadingSheetInset > 1 {
                    let edgePadding = UIEdgeInsets(top: 0, left: self.leadingSheetInset, bottom: 0, right: 0)
                    mapView.setVisibleMapRect(mapRect, edgePadding: edgePadding, animated: true)
                } else {
                    // Compact bottom-sheet mode: size the sheet inset from the map/window bounds
                    // rather than UIScreen.main so iPhone Duo and Split View center accurately.
                    let containerHeight = mapView.bounds.height > 1
                        ? mapView.bounds.height
                        : (mapView.window?.bounds.height ?? 0)
                    let bottomSheetHeight: CGFloat
                    if self.bottomPadding > 1, containerHeight > 1 {
                        bottomSheetHeight = min(self.bottomPadding, containerHeight - 1)
                    } else {
                        bottomSheetHeight = containerHeight * (0.8 / 3.0)
                    }
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

    func cancelPendingPostOnboardingMapPresentation() {
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
}
