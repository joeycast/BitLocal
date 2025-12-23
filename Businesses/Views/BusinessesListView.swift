// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation

@available(iOS 17.0, *)
struct BusinessesListView: View {
    
    @EnvironmentObject var viewModel: ContentViewModel
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    let maxListResults = 25
    var elements: [Element]
    var userLocation: CLLocation?
    var currentDetent: PresentationDetent? = nil
    
    @State private var cellViewModels: [String: ElementCellViewModel] = [:] // Keyed by Element ID
    @State private var lastLoggedLocation: CLLocationCoordinate2D? // Track last logged location
    
    private var sortedElements: [Element] {
        elements.sorted { (element1, element2) -> Bool in
            guard let distance1 = viewModel.distanceInMiles(element: element1),
                  let distance2 = viewModel.distanceInMiles(element: element2) else {
                return false
            }
            return distance1 < distance2
        }
    }
    
    var body: some View {
        Group {
            // 1️⃣ Loading state
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    LoadingScreenView()
                    Spacer()
                }
            }
            // 2️⃣ No locations after loading finishes
            else if elements.isEmpty {
                Text(NSLocalizedString("no_locations_found", comment: "Empty state for no locations found"))
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            // 3️⃣ Show the list when we have elements
            else {
                List {
                    Section {
                        ForEach(sortedElements.prefix(maxListResults), id: \.id) { element in
                            let cellVM = cellViewModel(for: element)
                            NavigationLink(value: element) {
                                ElementCell(viewModel: cellVM)
                            }
                            .clearListRowBackground(if: shouldUseGlassyRows)
                        }
                        // Insert the footer as its own row:
                        footerView
                            .clearListRowBackground(if: shouldUseGlassyRows)
                    }
                    .clearListRowBackground(if: shouldUseGlassyRows)
                }
                .listStyle(.plain)
                .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
                .background(Color.clear)
                .environment(\.defaultMinListRowHeight, 0)
                .navigationBarTitleDisplayMode(.inline)
                .padding(.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: viewModel.path) { _, newPath in
                    if let element = newPath.last {
                        // Delay zoom until after navigation completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            viewModel.zoomToElement(element)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        // OPTIMIZED: Only log significant location changes at the list level
        .onChange(of: viewModel.userLocation) { _, newLocation in
            handleUserLocationChange(newLocation)
        }
    }
    
    // OPTIMIZED: Centralized location change handling with deduplication
    private func handleUserLocationChange(_ newLocation: CLLocation?) {
        guard let newLocation = newLocation else { return }
        
        // Only log/process if location actually changed significantly (>10 meters)
        if let lastCoord = lastLoggedLocation {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let currentLoc = CLLocation(latitude: newLocation.coordinate.latitude, longitude: newLocation.coordinate.longitude)
            
            if lastLoc.distance(from: currentLoc) < 10 {
                return // Skip if location hasn't changed significantly
            }
        }
        
        lastLoggedLocation = newLocation.coordinate
        Debug.log("User location updated in BusinessesListView: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
        
        // Update cell view models that need refresh
        for cellVM in cellViewModels.values {
            cellVM.updateUserLocationIfNeeded(newLocation)
        }
    }
    
    private func cellViewModel(for element: Element) -> ElementCellViewModel {
        if let vm = viewModel.cellViewModels[element.id] {
            return vm
        } else {
            let newVM = ElementCellViewModel(element: element,
                                             userLocation: viewModel.userLocation,
                                             viewModel: viewModel)
            DispatchQueue.main.async {
                viewModel.cellViewModels[element.id] = newVM
            }
            return newVM
        }
    }
    
    private var footerView: some View {
        Group {
            if sortedElements.count > maxListResults {
                Text(
                    String(
                        format: NSLocalizedString("locations_returned_footer", comment: "Footer: N locations returned, top M displayed"),
                        sortedElements.count,
                        min(sortedElements.count, maxListResults)
                    )
                )
            } else {
                Text(
                    String(
                        format: NSLocalizedString("showing_locations_footer", comment: "Footer: Showing N of N locations"),
                        sortedElements.count,
                        sortedElements.count
                    )
                )
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }
    
    private var shouldHideSheetBackground: Bool {
        guard let detent = currentDetent else { return false }
        return detent != .large
    }
    
    private var shouldUseGlassyRows: Bool {
        guard let detent = currentDetent else { return false }
        guard #available(iOS 26.0, *) else { return false }
        return detent != .large
    }
}

@available(iOS 17.0, *)
struct ElementCell: View {
    
    @ObservedObject var viewModel: ElementCellViewModel
    @State private var appeared = false
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            HStack {
                // Business Name
                Text(
                    viewModel.element.osmJSON?.tags?.name ??
                    viewModel.element.osmJSON?.tags?.operator ??
                    NSLocalizedString("name_not_available", comment: "Fallback name for unavailable business name")
                )
                    .foregroundColor(.primary)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Distance from location
                distanceText
                    .font(.subheadline)
            }
            
            // Street number and name
            if let streetNumber = viewModel.address?.streetNumber {
                Text("\(streetNumber) \(viewModel.address?.streetName ?? "")".trimmingCharacters(in: .whitespaces))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.address?.streetName ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(viewModel.address?.cityOrTownName ?? "")\(viewModel.address?.cityOrTownName != nil && viewModel.address?.cityOrTownName != "" ? ", " : "")\(viewModel.address?.regionOrStateName ?? "") \(viewModel.address?.postalCode ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                PaymentIcons(element: viewModel.element)
            }
        }
        // REMOVED: Redundant onChange that was causing excessive logging
        // .onChange(of: viewModel.viewModel.userLocation) { _, _ in
        //     viewModel.onCellAppear()
        // }
    }
    
    private var distanceText: some View {
        let formattedDistance: String? = {
            if let distance = localizedDistanceString(for: viewModel.element) {
                return distance
            } else {
                // fallback to miles for now
                if let distance = viewModel.viewModel.distanceInMiles(element: viewModel.element) {
                    if distance < 1 {
                        return String(format: "%.2f mi", distance)
                    } else {
                        return String(format: "%.1f mi", distance)
                    }
                }
                return nil
            }
        }()
        return Text(formattedDistance ?? "")
            .opacity(formattedDistance != nil ? 1 : 0)
            .padding(.trailing, 3)
    }
    
    private func localizedDistanceString(for element: Element) -> String? {
        guard let userLocation = viewModel.viewModel.userLocation, let coord = element.mapCoordinate else { return nil }
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
            if km < 1 {
                return String(format: "%.2f km", km)
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            let miles = distanceInMeters / 1609.344
            if miles < 1 {
                return String(format: "%.2f mi", miles)
            } else {
                return String(format: "%.1f mi", miles)
            }
        }
    }
}

@available(iOS 17.0, *)
class ElementCellViewModel: ObservableObject {
    
    let element: Element
    let viewModel: ContentViewModel
    @Published var address: Address?
    
    // OPTIMIZED: Remove the excessive logging from userLocation didSet
    @Published var userLocation: CLLocation?
    
    private var userLocationCancellable: AnyCancellable?
    private var lastLocationUpdate: CLLocationCoordinate2D?
    
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
        if let cachedAddress = getCachedAddress() {
            self.address = mergedAddress(preferred: element.address, fallback: cachedAddress)
        } else {
            self.address = element.address
        }
        // Start geocoding only if we don't already have a complete address
        if !isAddressComplete(self.address) {
            self.updateAddress()
        } else if let address = self.address {
            setCachedAddress(address)
            viewModel.scheduleGeocodingCacheSave()
        }
    }
    
    deinit {
        // Cancel the subscription when the view model is deallocated
        userLocationCancellable?.cancel()
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
        if address == nil {
            updateAddress()
        }
    }
    
    private var addressCacheKey: String {
        guard let coord = element.mapCoordinate else {
            return ""
        }
        return "\(coord.latitude),\(coord.longitude)"
    }

    private func getCachedAddress() -> Address? {
        guard let coord = element.mapCoordinate else {
            return nil
        }
        let cacheKey = "\(coord.latitude),\(coord.longitude)"
        return viewModel.geocodingCache.getValue(forKey: cacheKey)
    }

    private func setCachedAddress(_ address: Address) {
        guard let coord = element.mapCoordinate else {
            return
        }
        let cacheKey = "\(coord.latitude),\(coord.longitude)"
        viewModel.geocodingCache.setValue(address, forKey: cacheKey)
    }

    func updateAddress() {
        // Check if the address is already cached
        if let cachedAddress = getCachedAddress() {
            let merged = mergedAddress(preferred: element.address, fallback: cachedAddress)
            self.address = merged
            if isAddressComplete(merged) {
                return
            }
        } else if let preferred = element.address {
            self.address = preferred
            if isAddressComplete(preferred) {
                setCachedAddress(preferred)
                viewModel.scheduleGeocodingCacheSave()
                return
            }
        }

        guard let coord = element.mapCoordinate else { return }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        // Perform geocoding
        viewModel.geocoder.reverseGeocode(location: location) { [weak self] placemark in
            guard let self = self, let placemark = placemark else { return }
            let address = Address(
                streetNumber: self.normalized(placemark.subThoroughfare),
                streetName: self.normalized(placemark.thoroughfare),
                cityOrTownName: self.normalized(placemark.locality),
                postalCode: self.normalized(placemark.postalCode),
                regionOrStateName: self.normalized(placemark.administrativeArea),
                countryName: self.normalized(placemark.country)
            )
            DispatchQueue.main.async {
                let merged = self.mergedAddress(preferred: self.element.address, fallback: address)
                self.address = merged
                if let merged = merged {
                    self.setCachedAddress(merged)
                    self.viewModel.scheduleGeocodingCacheSave()
                }
            }
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func isAddressComplete(_ address: Address?) -> Bool {
        guard let address = address else { return false }
        return normalized(address.streetNumber) != nil &&
            normalized(address.streetName) != nil &&
            normalized(address.cityOrTownName) != nil
    }

    private func mergedAddress(preferred: Address?, fallback: Address?) -> Address? {
        guard preferred != nil || fallback != nil else { return nil }
        func pick(_ preferredValue: String?, _ fallbackValue: String?) -> String? {
            return normalized(preferredValue) ?? normalized(fallbackValue)
        }
        return Address(
            streetNumber: pick(preferred?.streetNumber, fallback?.streetNumber),
            streetName: pick(preferred?.streetName, fallback?.streetName),
            cityOrTownName: pick(preferred?.cityOrTownName, fallback?.cityOrTownName),
            postalCode: pick(preferred?.postalCode, fallback?.postalCode),
            regionOrStateName: pick(preferred?.regionOrStateName, fallback?.regionOrStateName),
            countryName: pick(preferred?.countryName, fallback?.countryName)
        )
    }
}

// Payment icons
struct PaymentIcons: View {
    let element: Element
    
    var body: some View {
        HStack {
            if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundColor(.accentColor)
            }
            
            if acceptsLightning(element: element) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.accentColor)
            }
            
            if acceptsContactlessLightning(element: element) {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

class Geocoder {
    private let geocoder = CLGeocoder()
    private let semaphore: DispatchSemaphore
    private let queue = DispatchQueue(label: "geocoder.queue", qos: .utility)
    
    init(maxConcurrentRequests: Int = 1) {
        semaphore = DispatchSemaphore(value: maxConcurrentRequests)
    }
    
    func reverseGeocode(location: CLLocation, completion: @escaping (CLPlacemark?) -> Void) {
        queue.async {
            self.semaphore.wait() // Wait for a free slot
            self.geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
                defer {
                    self.semaphore.signal() // Release the slot
                }
                
                guard let placemark = placemarks?.first else {
                    completion(nil)
                    return
                }
                
                completion(placemark)
            }
        }
    }
}
