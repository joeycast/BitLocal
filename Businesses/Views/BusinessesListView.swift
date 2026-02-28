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
    @FocusState private var isSearchFieldFocused: Bool

    private var sortedElements: [Element] {
        elements.sorted { (element1, element2) -> Bool in
            let distance1 = viewModel.distanceFromListFocus(element: element1) ?? .greatestFiniteMagnitude
            let distance2 = viewModel.distanceFromListFocus(element: element2) ?? .greatestFiniteMagnitude
            return distance1 < distance2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible search bar
            searchBar
                .padding(.top, 20)
                .padding(.bottom, 2)

            Group {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        LoadingScreenView()
                        Spacer()
                    }
                } else if viewModel.isSearchActive {
                    searchResultsView
                } else if elements.isEmpty {
                    Text(NSLocalizedString("no_locations_found", comment: "Empty state for no locations found"))
                        .foregroundStyle(.gray)
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    normalListView
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .onChange(of: viewModel.userLocation) { _, newLocation in
            handleUserLocationChange(newLocation)
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused && !viewModel.isSearchActive {
                viewModel.isSearchActive = true
            }
        }
        .onAppear {
            viewModel.ensureEventsLoaded()
            viewModel.ensureAreasLoaded()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            TextField("Search merchants or regions…", text: $viewModel.unifiedSearchText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
            if !viewModel.unifiedSearchText.isEmpty {
                Button {
                    viewModel.unifiedSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
            }
            if viewModel.isSearchActive {
                Button("Cancel") {
                    isSearchFieldFocused = false
                    viewModel.isSearchActive = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 18.5))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearchActive)
    }

    // MARK: - Normal Mode (discovery hub)

    private var normalListView: some View {
        List {
            // Events carousel (only renders if events exist)
            EventsDiscoverySection()
                .environmentObject(viewModel)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .clearListRowBackground(if: shouldUseGlassyRows)

            // Merchant list
            Section {
                ForEach(sortedElements.prefix(maxListResults), id: \.id) { element in
                    let cellVM = cellViewModel(for: element)
                    Button {
                        viewModel.setSelectionSource(.list)
                        viewModel.selectAnnotation(for: element, animated: true)
                        viewModel.path = [element]
                    } label: {
                        ZStack(alignment: .trailing) {
                            ElementCell(viewModel: cellVM)
                                .padding(.trailing, 18)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.gray.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        viewModel.requestPlaceholderNameHydration(for: [element])
                    }
                    .clearListRowBackground(if: shouldUseGlassyRows)
                }

                footerView
                    .clearListRowBackground(if: shouldUseGlassyRows)
            }
            .clearListRowBackground(if: shouldUseGlassyRows)

            // Browse All Regions
            Section {
                NavigationLink {
                    AllRegionsListView()
                        .environmentObject(viewModel)
                } label: {
                    Label("Browse All Regions", systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                }
                .clearListRowBackground(if: shouldUseGlassyRows)
            }
            .clearListRowBackground(if: shouldUseGlassyRows)
        }
        .listStyle(.plain)
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: Array(sortedElements.prefix(maxListResults)))
        }
    }

    // MARK: - Search Mode

    private var searchResultsView: some View {
        List {
            // Matching regions
            if !viewModel.searchMatchingAreas.isEmpty {
                Section("Regions") {
                    ForEach(viewModel.searchMatchingAreas.prefix(3)) { area in
                        Button {
                            viewModel.selectArea(area)
                            viewModel.isSearchActive = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .foregroundStyle(.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(area.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let subtitle = areaSubtitle(area) {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Local merchant matches
            if !viewModel.localFilteredMerchants.isEmpty {
                Section("Nearby") {
                    ForEach(viewModel.localFilteredMerchants.prefix(10), id: \.id) { element in
                        let cellVM = cellViewModel(for: element)
                        Button {
                            viewModel.setSelectionSource(.list)
                            viewModel.selectAnnotation(for: element, animated: true)
                            viewModel.path = [element]
                        } label: {
                            ElementCell(viewModel: cellVM)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            viewModel.requestPlaceholderNameHydration(for: [element])
                        }
                    }
                }
            }

            // Remote API results
            if viewModel.merchantSearchIsLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !viewModel.merchantSearchResults.isEmpty {
                let localIDs = Set(viewModel.localFilteredMerchants.map(\.id))
                let deduped = viewModel.merchantSearchResults.filter { !localIDs.contains($0.idString) }
                if !deduped.isEmpty {
                    Section("More Results") {
                        ForEach(deduped) { result in
                            Button {
                                viewModel.selectMerchantSearchResult(result)
                            } label: {
                                MerchantSearchResultRow(
                                    result: result,
                                    referenceLocation: searchReferenceLocation
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Empty state
            if viewModel.localFilteredMerchants.isEmpty &&
                viewModel.searchMatchingAreas.isEmpty &&
                viewModel.merchantSearchResults.isEmpty &&
                !viewModel.merchantSearchIsLoading &&
                !viewModel.unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text("No results found")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: Array(viewModel.localFilteredMerchants.prefix(20)))
        }
    }

    // MARK: - Helpers

    private var searchReferenceLocation: CLLocation? {
        if let userLocation = viewModel.userLocation { return userLocation }
        let center = viewModel.region.center
        return CLLocation(latitude: center.latitude, longitude: center.longitude)
    }

    private func areaSubtitle(_ area: V3AreaRecord) -> String? {
        if let place = area.tags?["place"], !place.isEmpty { return place.capitalized }
        if let boundary = area.tags?["boundary"], !boundary.isEmpty { return boundary.capitalized }
        return area.urlAlias
    }

    private func handleUserLocationChange(_ newLocation: CLLocation?) {
        guard let newLocation = newLocation else { return }
        if let lastCoord = lastLoggedLocation {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let currentLoc = CLLocation(latitude: newLocation.coordinate.latitude, longitude: newLocation.coordinate.longitude)
            if lastLoc.distance(from: currentLoc) < 10 { return }
        }
        lastLoggedLocation = newLocation.coordinate
        Debug.log("User location updated in BusinessesListView: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
        for cellVM in cellViewModels.values {
            cellVM.updateUserLocationIfNeeded(newLocation)
        }
    }

    private func cellViewModel(for element: Element) -> ElementCellViewModel {
        if let vm = viewModel.cellViewModels[element.id] {
            let currentName = vm.element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nextName = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let currentUpdated = vm.element.updatedAt ?? ""
            let nextUpdated = element.updatedAt ?? ""
            if currentName != nextName || currentUpdated != nextUpdated {
                let refreshed = ElementCellViewModel(
                    element: element,
                    userLocation: viewModel.userLocation,
                    viewModel: viewModel
                )
                DispatchQueue.main.async {
                    viewModel.cellViewModels[element.id] = refreshed
                }
                return refreshed
            }
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
        .foregroundStyle(.secondary)
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
                    viewModel.element.displayName ??
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
        .contentShape(Rectangle())
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
                postalCode: Address.normalizedPostalCode(
                    self.normalized(placemark.postalCode),
                    countryName: self.normalized(placemark.country)
                ),
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
            postalCode: Address.normalizedPostalCode(
                pick(preferred?.postalCode, fallback?.postalCode),
                countryName: pick(preferred?.countryName, fallback?.countryName)
            ),
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
