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
    @State private var searchResultsLimit = 20
    @State private var cachedTopSortedElements: [Element] = []
    @State private var cachedVisibleCategoryChips: [MerchantCategoryChip] = []
    @FocusState private var isSearchFieldFocused: Bool

    private var topSortedElements: [Element] {
        cachedTopSortedElements
    }

    private var featuredTopSortedElements: [Element] {
        topSortedElements.filter { $0.isCurrentlyBoosted() }
    }

    private var regularTopSortedElements: [Element] {
        topSortedElements.filter { !$0.isCurrentlyBoosted() }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible search bar
            searchBar
                .padding(.top, 20)
                .padding(.bottom, 2)

            if !visibleCategoryChips.isEmpty {
                categoryChipsView
                    .padding(.bottom, 4)
            }

            Group {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        LoadingScreenView()
                        Spacer()
                    }
                } else if isFilteringMerchants {
                    searchResultsView
                } else if elements.isEmpty {
                    if shouldShowEmptyState {
                        Text(NSLocalizedString("no_locations_found", comment: "Empty state for no locations found"))
                            .foregroundStyle(.gray)
                            .font(.title3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    normalListView
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .onChange(of: viewModel.userLocation) { _, newLocation in
            handleUserLocationChange(newLocation)
            refreshDiscoveryCache()
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused && !viewModel.isSearchActive {
                viewModel.isSearchActive = true
            }
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            searchResultsLimit = 20
        }
        .onChange(of: viewModel.selectedMerchantSearchScope) { _, _ in
            searchResultsLimit = 20
            viewModel.performUnifiedSearch()
        }
        .onChange(of: viewModel.region.center.latitude) { _, _ in
            viewModel.handleMerchantSearchMapRegionChange()
        }
        .onChange(of: viewModel.region.center.longitude) { _, _ in
            viewModel.handleMerchantSearchMapRegionChange()
        }
        .onChange(of: elements.map(\.id)) { _, _ in
            refreshDiscoveryCache()
        }
        .onAppear {
            viewModel.ensureEventsLoaded()
            viewModel.ensureAreasLoaded() // Keep community/area data warming in background during merchant browsing.
            refreshDiscoveryCache()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            TextField("Search merchants…", text: $viewModel.unifiedSearchText)
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
        .clipShape(RoundedRectangle(cornerRadius: 40))
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

            if !featuredTopSortedElements.isEmpty {
                Section {
                    ForEach(featuredTopSortedElements, id: \.id) { element in
                        merchantRow(for: element)
                    }
                } header: {
                    merchantSectionHeader(
                        title: "Featured Nearby",
                        systemImage: "star.fill",
                        tint: Color(red: 0.71, green: 0.50, blue: 0.12),
                        topPadding: -4,
                        bottomPadding: -6
                    )
                }
                .clearListRowBackground(if: shouldUseGlassyRows)
            }

            if !regularTopSortedElements.isEmpty || featuredTopSortedElements.isEmpty {
                Section {
                    ForEach(regularTopSortedElements, id: \.id) { element in
                        merchantRow(for: element)
                    }

                    footerView
                        .clearListRowBackground(if: shouldUseGlassyRows)
                } header: {
                    if !featuredTopSortedElements.isEmpty {
                        merchantSectionHeader(
                            title: "More Nearby",
                            systemImage: "location.fill",
                            tint: .secondary,
                            topPadding: 4,
                            bottomPadding: -14
                        )
                    }
                }
                .clearListRowBackground(if: shouldUseGlassyRows)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: topSortedElements)
        }
    }

    // MARK: - Search Mode

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if !isCollapsedSheet {
                searchScopePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }

            List {
                if trimmedSearchQuery.count == 1 {
                    Text("Type at least 2 characters to search")
                        .foregroundStyle(.secondary)
                } else if trimmedSearchQuery.count >= 2 {
                    if let statusText = searchStatusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if displayedPrimaryResults.isEmpty &&
                        displayedFreshResults.isEmpty &&
                        !viewModel.merchantSearchIsWaitingForLocalDebounce &&
                        !viewModel.merchantSearchIsLoading {
                        Text(noResultsText)
                            .foregroundStyle(.secondary)
                    } else {
                        if viewModel.selectedMerchantSearchScope == .onMap {
                            if !displayedFeaturedPrimaryResults.isEmpty {
                                Section {
                                    ForEach(displayedFeaturedPrimaryResults, id: \.id) { element in
                                        merchantSearchRow(for: element)
                                    }
                                } header: {
                                    merchantSectionHeader(
                                        title: "Featured Nearby",
                                        systemImage: "star.fill",
                                        tint: Color(red: 0.71, green: 0.50, blue: 0.12),
                                        topPadding: 4,
                                        bottomPadding: -10
                                    )
                                }
                            }

                            if !displayedRegularPrimaryResults.isEmpty || displayedFeaturedPrimaryResults.isEmpty {
                                Section {
                                    ForEach(displayedRegularPrimaryResults, id: \.id) { element in
                                        merchantSearchRow(for: element)
                                    }
                                } header: {
                                    if !displayedFeaturedPrimaryResults.isEmpty {
                                        merchantSectionHeader(
                                            title: "More Nearby",
                                            systemImage: "location.fill",
                                            tint: .secondary,
                                            topPadding: 4,
                                            bottomPadding: -14
                                        )
                                    }
                                }
                            }
                        } else if !displayedPrimaryResults.isEmpty {
                            ForEach(displayedPrimaryResults, id: \.id) { element in
                                merchantSearchRow(for: element)
                            }
                        }

                        if !displayedFreshResults.isEmpty {
                            Section("More Results") {
                                ForEach(displayedFreshResults) { record in
                                    freshMerchantSearchRow(for: record)
                                }
                            }
                        }
                    }

                    if hasMoreSearchResults {
                        Button("Load more results") {
                            searchResultsLimit += 20
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.accent)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
            .contentMargins(.top, 0, for: .scrollContent)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: Array(viewModel.merchantSearchPrimaryResults.prefix(20)))
        }
    }

    // MARK: - Helpers

    private var trimmedSearchQuery: String {
        viewModel.unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFilteringMerchants: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var visibleCategoryChips: [MerchantCategoryChip] {
        guard trimmedSearchQuery.isEmpty else { return [] }
        guard viewModel.selectedMerchantSearchScope == .onMap else { return [] }
        return cachedVisibleCategoryChips
    }

    private var searchScopePicker: some View {
        Picker("Search Scope", selection: $viewModel.selectedMerchantSearchScope) {
            ForEach(MerchantSearchScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchStatusText: String? {
        if viewModel.selectedMerchantSearchScope == .onMap &&
            viewModel.merchantSearchIsWaitingForLocalDebounce {
            return "Searching nearby…"
        }
        if viewModel.selectedMerchantSearchScope == .worldwide &&
            viewModel.merchantSearchIsWaitingForLocalDebounce {
            return "Searching…"
        }
        if viewModel.selectedMerchantSearchScope == .worldwide &&
            viewModel.merchantSearchIsOfflineFallback {
            return "Offline/local results"
        }
        return nil
    }

    private var noResultsText: String {
        "No locations match your search"
    }

    private var displayedPrimaryResults: [Element] {
        let limit = min(searchResultsLimit, viewModel.merchantSearchPrimaryResults.count)
        return Array(viewModel.merchantSearchPrimaryResults.prefix(limit))
    }

    private var displayedFeaturedPrimaryResults: [Element] {
        displayedPrimaryResults.filter { $0.isCurrentlyBoosted() }
    }

    private var displayedRegularPrimaryResults: [Element] {
        displayedPrimaryResults.filter { !$0.isCurrentlyBoosted() }
    }

    private var displayedFreshResults: [V4PlaceRecord] {
        let remaining = max(0, searchResultsLimit - displayedPrimaryResults.count)
        return Array(viewModel.merchantSearchFreshResults.prefix(remaining))
    }

    private var hasMoreSearchResults: Bool {
        let totalCount = viewModel.merchantSearchPrimaryResults.count + viewModel.merchantSearchFreshResults.count
        return totalCount > searchResultsLimit
    }

    private var categoryChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleCategoryChips) { chip in
                    Button {
                        applyCategoryChip(chip)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.symbolName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(chip.localizedLabel)
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(chip.localizedLabel))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private func applyCategoryChip(_ chip: MerchantCategoryChip) {
        viewModel.selectedMerchantSearchScope = .onMap
        viewModel.isSearchActive = true
        viewModel.unifiedSearchText = chip.localizedLabel
    }

    private func refreshDiscoveryCache() {
        cachedTopSortedElements = nearestElements(elements, limit: maxListResults)
        cachedVisibleCategoryChips = ElementCategorySymbols.merchantCategoryChips(for: elements, limit: 6)
    }

    private func merchantSearchRow(for element: Element) -> some View {
        let cellVM = cellViewModel(for: element)
        return Button {
            viewModel.setSelectionSource(.list)
            viewModel.selectAnnotationForListSelection(
                element,
                animated: true,
                allowCameraMovement: !isLargeSheet
            )
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
    }

    private func merchantRow(for element: Element) -> some View {
        let cellVM = cellViewModel(for: element)
        return Button {
            viewModel.setSelectionSource(.list)
            viewModel.selectAnnotationForListSelection(
                element,
                animated: true,
                allowCameraMovement: !isLargeSheet
            )
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

    private func freshMerchantSearchRow(for result: V4PlaceRecord) -> some View {
        let remoteElement = V4PlaceToElementMapper.placeRecordToElement(result)
        let cellVM = cellViewModel(for: remoteElement)
        return Button {
            viewModel.selectMerchantSearchResult(
                result,
                allowCameraMovement: !isLargeSheet
            )
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
            viewModel.hydrateMerchantSearchPreviewIfNeeded(result)
        }
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
            let currentName = vm.element.displayName ?? ""
            let nextName = element.displayName ?? ""
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
            if elements.count > maxListResults {
                Text(
                    String(
                        format: NSLocalizedString("locations_returned_footer", comment: "Footer: N locations returned, top M displayed"),
                        elements.count,
                        min(elements.count, maxListResults)
                    )
                )
            } else {
                Text(
                    String(
                        format: NSLocalizedString("showing_locations_footer", comment: "Footer: Showing N of N locations"),
                        elements.count,
                        elements.count
                    )
                )
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func merchantSectionHeader(
        title: String,
        systemImage: String,
        tint: Color,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .textCase(nil)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }

    private func nearestElements(_ source: [Element], limit: Int) -> [Element] {
        guard limit > 0, !source.isEmpty else { return [] }
        return source
            .sorted(by: viewModel.merchantBrowseSortOrder)
            .prefix(limit)
            .map { $0 }
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

    private var shouldShowEmptyState: Bool {
        guard let detent = currentDetent else { return true }
        return detent != collapsedSheetDetent
    }

    private var isCollapsedSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detent == collapsedSheetDetent
    }

    private var isLargeSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("large")
    }

    private var collapsedSheetDetent: PresentationDetent {
        .fraction(0.11)
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
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
                    .font(.subheadline.weight(.medium))
            }
            
            HStack(alignment: .center, spacing: 8) {
                // Street number and name
                if let streetNumber = viewModel.address?.streetNumber {
                    Text("\(streetNumber) \(viewModel.address?.streetName ?? "")".trimmingCharacters(in: .whitespaces))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(viewModel.address?.streetName ?? "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
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
        .onAppear {
            guard !appeared else { return }
            appeared = true
            viewModel.onCellAppear()
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
        if address == nil || shouldEnrichMissingState(address) {
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
            if isAddressComplete(merged) && !shouldEnrichMissingState(merged) {
                return
            }
        } else if let preferred = element.address {
            self.address = preferred
            if isAddressComplete(preferred) && !shouldEnrichMissingState(preferred) {
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

    private func shouldEnrichMissingState(_ address: Address?) -> Bool {
        guard let address = address else { return false }
        return normalized(address.regionOrStateName) == nil
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
        HStack(spacing: 6) {
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
        .font(.subheadline)
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
