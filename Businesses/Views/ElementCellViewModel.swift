import SwiftUI
import CoreLocation
import Combine

class ElementCellViewModel: ObservableObject {

    static let regionCountryCodeDidChange = Notification.Name("regionCountryCodeDidChange")

    let element: Element
    let viewModel: ContentViewModel
    @Published var address: Address?

    // OPTIMIZED: Remove the excessive logging from userLocation didSet
    @Published var userLocation: CLLocation?

    private var userLocationCancellable: AnyCancellable?
    private var regionCodeCancellable: AnyCancellable?
    private var lastLocationUpdate: CLLocationCoordinate2D?
    private var isAddressLookupInFlight = false
    
    init(element: Element, userLocation: CLLocation?, viewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self.viewModel = viewModel
        
        // OPTIMIZED: Subscribe to location changes but with deduplication
        self.userLocationCancellable = viewModel.$userLocation
            .removeDuplicates { oldLocation, newLocation in
                // Only update if location changed significantly
                guard let old = oldLocation, let new = newLocation else {
                    return oldLocation == nil && newLocation == nil
                }
                return old.distance(from: new) < 10 // Less than 10 meters
            }
            .sink { [weak self] newLocation in
                self?.userLocation = newLocation
            }
        
        // Attempt to retrieve cached address, but prefer OSM-tagged fields when present
        if let cachedEntry = getCachedAddressEntry() {
            self.address = enrichWithRegionCountryCode(
                mergedAddress(preferred: element.address, fallback: cachedEntry.address)
            )
        } else {
            self.address = enrichWithRegionCountryCode(element.address)
        }

        if let address = self.address,
           address.hasAnyGeocodingFields,
           !needsSeedAddressEnrichment(address),
           shouldPersistInitialAddress(address) {
            setCachedAddressEntry(.forAddress(address))
            viewModel.scheduleGeocodingCacheSave()
        }

        // When a nearby geocode discovers the country code, re-enrich this cell
        regionCodeCancellable = NotificationCenter.default
            .publisher(for: Self.regionCountryCodeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self,
                      normalized(self.address?.isoCountryCode) == nil,
                      let enriched = enrichWithRegionCountryCode(self.address) else { return }
                self.setAddressIfChanged(enriched)
                if enriched.hasAnyGeocodingFields {
                    self.setCachedAddressEntry(.forAddress(enriched))
                    self.viewModel.scheduleGeocodingCacheSave()
                }
            }
    }

    deinit {
        userLocationCancellable?.cancel()
        regionCodeCancellable?.cancel()
    }
    
    // OPTIMIZED: Add method for manual location updates with deduplication
    func updateUserLocationIfNeeded(_ newLocation: CLLocation) {
        // Only update if location changed significantly
        if let lastCoord = lastLocationUpdate {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if lastLoc.distance(from: newLocation) < 10 {
                return // Skip if location hasn't changed significantly
            }
        }
        
        lastLocationUpdate = newLocation.coordinate
        self.userLocation = newLocation
    }
    
    func onCellAppear() {
        if shouldAttemptReverseGeocode() {
            updateAddress()
        }
    }
    
    private var addressCacheKey: String {
        guard let coord = element.mapCoordinate else {
            return ""
        }
        return ReverseGeocodingSpatialKey.key(for: coord)
    }

    /// Coarse key (~111 km) used for the region-level country code cache.
    /// Countries don't change within this distance except at borders.
    private var coarseRegionKey: String? {
        guard let coord = element.mapCoordinate else { return nil }
        return ReverseGeocodingSpatialKey.key(for: coord, precision: 0)
    }

    /// Look up the country code from the coarse regional cache (no network).
    private func regionCountryCode() -> String? {
        guard let key = coarseRegionKey else { return nil }
        return viewModel.countryCodeByRegion[key]
    }

    /// Store a country code in the coarse regional cache after geocoding.
    private func setRegionCountryCode(_ code: String) {
        guard let key = coarseRegionKey else { return }
        let isNew = viewModel.countryCodeByRegion[key] == nil
        viewModel.countryCodeByRegion[key] = code
        if isNew {
            NotificationCenter.default.post(name: Self.regionCountryCodeDidChange, object: nil)
        }
    }

    /// Fire exactly one geocode per ~11 km region to discover the country code.
    /// Does nothing if the region already has a code or a lookup is in flight.
    private func requestRegionCountryCodeIfNeeded() {
        guard normalized(address?.isoCountryCode) == nil,
              let key = coarseRegionKey,
              viewModel.countryCodeByRegion[key] == nil,
              !viewModel.pendingRegionCodeLookups.contains(key),
              let coord = element.mapCoordinate else { return }

        viewModel.pendingRegionCodeLookups.insert(key)
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let requestKey = "region-code:\(key)"

        viewModel.geocoder.reverseGeocode(location: location, requestKey: requestKey) { [weak self] response in
            guard let self else { return }
            self.viewModel.pendingRegionCodeLookups.remove(key)
            if let code = self.normalized(response.placemark?.isoCountryCode) {
                self.setRegionCountryCode(code)
            }
        }
    }

    private func getCachedAddressEntry() -> ReverseGeocodingCacheEntry? {
        guard !addressCacheKey.isEmpty else { return nil }
        return viewModel.geocodingCache.getValue(forKey: addressCacheKey)
    }

    private func setCachedAddressEntry(_ entry: ReverseGeocodingCacheEntry) {
        guard !addressCacheKey.isEmpty else { return }
        viewModel.geocodingCache.setValue(entry, forKey: addressCacheKey)
    }

    /// Only publish a new address when it actually differs from the current one,
    /// preventing unnecessary SwiftUI redraws.
    private func setAddressIfChanged(_ newAddress: Address?) {
        guard !addressesMatch(address, newAddress) else { return }
        address = newAddress
    }

    /// If the address is missing an `isoCountryCode`, try to fill it in from
    /// the coarse regional cache (populated by geocoding of nearby merchants).
    /// This avoids a network geocode just to determine the country.
    private func enrichWithRegionCountryCode(_ address: Address?) -> Address? {
        guard let address else { return nil }
        guard normalized(address.isoCountryCode) == nil,
              let code = regionCountryCode() else {
            return address
        }
        return Address(
            streetNumber: address.streetNumber,
            streetName: address.streetName,
            cityOrTownName: address.cityOrTownName,
            postalCode: address.postalCode,
            regionOrStateName: address.regionOrStateName,
            countryName: address.countryName,
            isoCountryCode: code
        )
    }

    func updateAddress() {
        if let cachedEntry = getCachedAddressEntry() {
            let merged = mergedAddress(preferred: element.address, fallback: cachedEntry.address)
            let enriched = enrichWithRegionCountryCode(merged)
            setAddressIfChanged(enriched)
            // Persist regional country code into cache if we just enriched it
            if let enriched, normalized(cachedEntry.address?.isoCountryCode) == nil,
               normalized(enriched.isoCountryCode) != nil {
                setCachedAddressEntry(.forAddress(enriched))
                viewModel.scheduleGeocodingCacheSave()
            }
            if cachedEntry.status == .resolved || cachedEntry.status == .partial {
                requestRegionCountryCodeIfNeeded()
                return
            }
            if !cachedEntry.shouldRetry() {
                requestRegionCountryCodeIfNeeded()
                return
            }
        } else if let preferred = element.address {
            let enriched = enrichWithRegionCountryCode(preferred)
            setAddressIfChanged(enriched)
            if preferred.hasAnyGeocodingFields && !needsSeedAddressEnrichment(preferred) {
                setCachedAddressEntry(.forAddress(enriched ?? preferred))
                viewModel.scheduleGeocodingCacheSave()
                // Address is complete but may still need a country code
                requestRegionCountryCodeIfNeeded()
                return
            }
        }

        guard !isAddressLookupInFlight else { return }
        guard let coord = element.mapCoordinate else { return }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let cacheKey = addressCacheKey
        let staleFallback = getCachedAddressEntry()?.address

        isAddressLookupInFlight = true

        // Perform geocoding
        viewModel.geocoder.reverseGeocode(location: location, requestKey: cacheKey) { [weak self] response in
            guard let self else { return }

            self.isAddressLookupInFlight = false

            if let placemark = response.placemark {
                let geocodedAddress = Address(
                    streetNumber: self.normalized(placemark.subThoroughfare),
                    streetName: self.normalized(placemark.thoroughfare),
                    cityOrTownName: self.normalized(placemark.locality),
                    postalCode: Address.normalizedPostalCode(
                        self.normalized(placemark.postalCode),
                        countryName: self.normalized(placemark.country)
                    ),
                    regionOrStateName: self.normalized(placemark.administrativeArea),
                    countryName: self.normalized(placemark.country),
                    isoCountryCode: self.normalized(placemark.isoCountryCode)
                )
                // Store country code in coarse regional cache for nearby merchants
                if let code = self.normalized(placemark.isoCountryCode) {
                    self.setRegionCountryCode(code)
                }

                let merged = self.mergedAddress(preferred: self.element.address, fallback: geocodedAddress)
                self.setAddressIfChanged(merged)

                if let merged, merged.hasAnyGeocodingFields {
                    self.setCachedAddressEntry(.forAddress(merged))
                } else {
                    self.setCachedAddressEntry(
                        .noResult(retryAfter: Date.now.addingTimeInterval(24 * 60 * 60))
                    )
                }
            } else if let staleFallback, staleFallback.hasAnyGeocodingFields {
                self.setAddressIfChanged(self.mergedAddress(preferred: self.element.address, fallback: staleFallback))
                self.setCachedAddressEntry(.forAddress(staleFallback))
            } else if let retryAfter = response.retryAfter {
                self.setCachedAddressEntry(.failed(retryAfter: retryAfter))
            } else {
                self.setCachedAddressEntry(
                    .noResult(retryAfter: Date.now.addingTimeInterval(24 * 60 * 60))
                )
            }

            self.viewModel.scheduleGeocodingCacheSave()
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func shouldAttemptReverseGeocode() -> Bool {
        if isAddressLookupInFlight {
            return false
        }

        if let cachedEntry = getCachedAddressEntry() {
            switch cachedEntry.status {
            case .resolved:
                let merged = mergedAddress(preferred: element.address, fallback: cachedEntry.address)
                return isLikelyMalformedStreetLine(merged)
            case .partial:
                let merged = mergedAddress(preferred: element.address, fallback: cachedEntry.address)
                return isLikelyMalformedStreetLine(merged)
            case .noResult, .failed:
                return cachedEntry.shouldRetry()
            }
        }

        guard let currentAddress = address else {
            return true
        }

        return needsSeedAddressEnrichment(currentAddress)
    }

    private func shouldPersistInitialAddress(_ address: Address) -> Bool {
        guard let cachedEntry = getCachedAddressEntry() else {
            return true
        }

        let mergedCurrent = mergedAddress(preferred: element.address, fallback: address)
        let mergedCached = mergedAddress(preferred: element.address, fallback: cachedEntry.address)
        let currentStatus = ReverseGeocodingCacheEntry.forAddress(address).status
        return !addressesMatch(mergedCurrent, mergedCached) || cachedEntry.status != currentStatus
    }

    private func needsSeedAddressEnrichment(_ address: Address?) -> Bool {
        guard let address else { return true }
        return !isAddressComplete(address) || isLikelyMalformedStreetLine(address)
    }

    private func addressesMatch(_ lhs: Address?, _ rhs: Address?) -> Bool {
        normalized(lhs?.streetNumber) == normalized(rhs?.streetNumber) &&
        normalized(lhs?.streetName) == normalized(rhs?.streetName) &&
        normalized(lhs?.cityOrTownName) == normalized(rhs?.cityOrTownName) &&
        normalized(lhs?.postalCode) == normalized(rhs?.postalCode) &&
        normalized(lhs?.regionOrStateName) == normalized(rhs?.regionOrStateName) &&
        normalized(lhs?.countryName) == normalized(rhs?.countryName) &&
        normalized(lhs?.isoCountryCode) == normalized(rhs?.isoCountryCode)
    }

    private func isAddressComplete(_ address: Address?) -> Bool {
        guard let address else { return false }
        // Street name + city is sufficient — street number is optional (many
        // international addresses don't have one) and state/region is
        // supplementary. Only geocode when we're truly missing core fields.
        return normalized(address.streetName) != nil &&
            normalized(address.cityOrTownName) != nil
    }

    private func shouldEnrichMissingState(_ address: Address?) -> Bool {
        guard let address else { return false }
        return normalized(address.regionOrStateName) == nil
    }

    private func isLikelyMalformedStreetLine(_ address: Address?) -> Bool {
        guard let address else { return false }
        guard let streetName = normalized(address.streetName) else {
            return false
        }

        if !looksLikePostalCode(streetName) {
            return false
        }

        let postalCode = normalized(address.postalCode)
        let city = normalized(address.cityOrTownName)
        return postalCode == streetName || city == nil
    }

    private func mergedAddress(preferred: Address?, fallback: Address?) -> Address? {
        guard preferred != nil || fallback != nil else { return nil }
        func pick(_ preferredValue: String?, _ fallbackValue: String?) -> String? {
            return normalized(preferredValue) ?? normalized(fallbackValue)
        }
        let preferredStreetName = normalized(preferred?.streetName)
        let selectedStreetName: String?
        if let preferredStreetName,
           looksLikePostalCode(preferredStreetName),
           (preferredStreetName == normalized(preferred?.postalCode) ||
            preferredStreetName == normalized(fallback?.postalCode) ||
            normalized(preferred?.cityOrTownName) == nil) {
            selectedStreetName = normalized(fallback?.streetName)
        } else if let preferredStreetName,
                  looksLikeRawAddressString(preferredStreetName),
                  normalized(fallback?.streetName) != nil {
            selectedStreetName = normalized(fallback?.streetName)
        } else {
            selectedStreetName = preferredStreetName ?? normalized(fallback?.streetName)
        }

        return Address(
            streetNumber: pick(preferred?.streetNumber, fallback?.streetNumber),
            streetName: selectedStreetName,
            cityOrTownName: pick(preferred?.cityOrTownName, fallback?.cityOrTownName),
            postalCode: Address.normalizedPostalCode(
                pick(preferred?.postalCode, fallback?.postalCode),
                countryName: pick(preferred?.countryName, fallback?.countryName)
            ),
            regionOrStateName: pick(preferred?.regionOrStateName, fallback?.regionOrStateName),
            countryName: pick(preferred?.countryName, fallback?.countryName),
            isoCountryCode: normalized(fallback?.isoCountryCode) ?? normalized(preferred?.isoCountryCode)
        )
    }

    private func looksLikePostalCode(_ value: String) -> Bool {
        let zipPattern = #"^\d{5}(?:-\d{4})?$"#
        return value.range(of: zipPattern, options: .regularExpression) != nil
    }

    /// Detects when a raw full-address string (e.g. "Handelskade 24, Willemstad, Curacao")
    /// was stuffed into the streetName field. Real street names don't contain commas.
    private func looksLikeRawAddressString(_ value: String) -> Bool {
        value.contains(",")
    }
}

// Payment icons
