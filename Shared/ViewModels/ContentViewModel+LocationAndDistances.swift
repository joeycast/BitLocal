import SwiftUI
import CoreLocation
import MapKit
import Foundation

extension ContentViewModel {
    func requestWhenInUseLocationPermission() {
        Task { @MainActor [weak self] in
            guard let self else { return }

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
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else {
            Debug.log("No location in didUpdateLocations")
            return
        }

        Debug.log("Location updated: \(latestLocation.coordinate)")
        manager.stopUpdatingLocation()

        Task { @MainActor [weak self] in
            guard let self else { return }

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
            self.isUpdatingLocation = false
        }
    }
    
    // locationManager failure scenario (could not get user location)
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Debug.log("LocationManager error: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.isUpdatingLocation = false
            self?.cancelPendingPostOnboardingMapPresentation()
        }
    }
    
    // Handle authorization changes
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Debug.log("Location authorization changed to: \(status.rawValue)")
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.userLocation == nil {
                    self.isUpdatingLocation = true
                    self.locationManager.startUpdatingLocation()
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
        let unit: UnitLength
        switch distanceUnit {
        case .auto:
            unit = Locale.current.measurementSystem == .metric ? .kilometers : .miles
        case .miles:
            unit = .miles
        case .kilometers:
            unit = .kilometers
        }
        return Measurement(value: distanceInMeters, unit: UnitLength.meters)
            .converted(to: unit)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(1))
                )
            )
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

    /// Precomputes boost state, distance, and normalized name once per element (O(N))
    /// instead of allocating CLLocation / parsing boost dates on every O(N log N) comparison.
    func sortedElementsForMerchantBrowse(_ source: [Element], limit: Int? = nil) -> [Element] {
        guard !source.isEmpty else { return [] }
        let originLocation = userLocation ?? CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let referenceDate = Date.now

        struct SortEntry {
            let element: Element
            let isBoosted: Bool
            let distance: CLLocationDistance
            let normalizedName: String
        }

        var entries: [SortEntry] = []
        entries.reserveCapacity(source.count)
        for element in source {
            let distance: CLLocationDistance
            if let coord = element.mapCoordinate {
                distance = originLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            } else {
                distance = .greatestFiniteMagnitude
            }
            entries.append(
                SortEntry(
                    element: element,
                    isBoosted: element.isCurrentlyBoosted(referenceDate: referenceDate),
                    distance: distance,
                    normalizedName: normalizedMerchantName(element.displayName ?? "")
                )
            )
        }

        entries.sort { lhs, rhs in
            if lhs.isBoosted != rhs.isBoosted {
                return lhs.isBoosted && !rhs.isBoosted
            }
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.normalizedName != rhs.normalizedName {
                return lhs.normalizedName < rhs.normalizedName
            }
            return lhs.element.id < rhs.element.id
        }

        if let limit, limit < entries.count {
            return entries.prefix(limit).map(\.element)
        }
        return entries.map(\.element)
    }

    private func listFocusCoordinate() -> CLLocationCoordinate2D? {
        guard layoutMode == .compactSheet,
              let mapView = mapView else { return nil }

        let focusRect = mapListViewportRect(for: mapView)

        let centerPoint = CGPoint(x: focusRect.midX, y: focusRect.midY)
        return mapView.convert(centerPoint, toCoordinateFrom: mapView)
    }
}
