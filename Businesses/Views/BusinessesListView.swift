// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation
import UIKit

@available(iOS 17.0, *)
struct BusinessesListView: View {

    @EnvironmentObject var viewModel: ContentViewModel
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    let maxListResults = 25
    var elements: [Element]
    var userLocation: CLLocation?
    var liveSheetHeight: CGFloat = 0
    @Binding private var currentDetent: PresentationDetent?

    @State private var cellViewModels: [String: ElementCellViewModel] = [:] // Keyed by Element ID
    @State private var lastLoggedLocation: CLLocationCoordinate2D? // Track last logged location
    @State private var searchResultsLimit = 20
    @State private var cachedTopSortedElements: [Element] = []
    @State private var cachedVisibleCategoryChips: [MerchantCategoryChip] = []
    @State private var showFocusedSearchCategoryChips = false
    @FocusState private var isSearchFieldFocused: Bool

    init(
        elements: [Element],
        userLocation: CLLocation? = nil,
        currentDetent: Binding<PresentationDetent?> = .constant(nil),
        liveSheetHeight: CGFloat = 0
    ) {
        self.elements = elements
        self.userLocation = userLocation
        self.liveSheetHeight = liveSheetHeight
        self._currentDetent = currentDetent
    }

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

            if shouldShowCategoryChips && !visibleCategoryChips.isEmpty {
                categoryChipsView
                    .padding(.bottom, 6)
                    .opacity(contentRevealProgress)
                    .offset(y: (1 - contentRevealProgress) * -8)
            }

            ZStack {
                if isShowingInitialLoadingState {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shouldHideCollapsedSheetContent {
                    Spacer(minLength: 0)
                } else if isFilteringMerchants {
                    searchResultsView
                } else if viewModel.activeMerchantAlertDigest != nil {
                    digestResultsView
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

                if isShowingInitialLoadingState {
                    LoadingScreenView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                }
            }
            .opacity(contentRevealProgress)
            .offset(y: (1 - contentRevealProgress) * 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.userLocation) { _, newLocation in
            handleUserLocationChange(newLocation)
            refreshDiscoveryCache()
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused && !viewModel.isSearchActive {
                viewModel.isSearchActive = true
            } else if !focused {
                showFocusedSearchCategoryChips = false
            }
        }
        .onChange(of: viewModel.unifiedSearchText) { _, _ in
            searchResultsLimit = 20
            clearSearchDrivenMapResults()
        }
        .onChange(of: displayedPrimaryResults.map(\.id)) { _, _ in
            syncDisplayedSearchResultsToMap()
        }
        .onChange(of: searchResultsLimit) { _, _ in
            syncDisplayedSearchResultsToMap()
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
            syncDisplayedSearchResultsToMap()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard isSearchFieldFocused else { return }
            withAnimation(keyboardAnimation(for: notification)) {
                showFocusedSearchCategoryChips = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            withAnimation(keyboardAnimation(for: notification)) {
                showFocusedSearchCategoryChips = false
            }
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
            Section {
                EventsDiscoverySection()
                    .environmentObject(viewModel)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .clearListRowBackground(if: shouldUseGlassyRows)
            }

            if !featuredTopSortedElements.isEmpty {
                Section {
                    ForEach(Array(featuredTopSortedElements.enumerated()), id: \.element.id) { index, element in
                        merchantRow(
                            for: element,
                            showsBottomDivider: index == featuredTopSortedElements.count - 1
                        )
                    }
                } header: {
                    merchantSectionHeader(
                        title: "Featured Nearby",
                        systemImage: "star.fill",
                        tint: Color(red: 0.71, green: 0.50, blue: 0.12),
                        topPadding: -3,
                        bottomPadding: -14
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
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: topSortedElements)
        }
    }

    private var digestResultsView: some View {
        List {
            if let digest = viewModel.activeMerchantAlertDigest {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New merchants in \(digest.cityDisplayName)")
                            .font(.headline)
                        Text(digest.summaryLine)
                            .foregroundStyle(.secondary)

                        Button("Clear Alert Filter") {
                            viewModel.clearMerchantAlertDigest()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(elements, id: \.id) { element in
                    merchantRow(for: element)
                }

                footerView
            }
            .clearListRowBackground(if: shouldUseGlassyRows)
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: elements)
        }
    }

    // MARK: - Search Mode

    private var searchResultsView: some View {
        VStack(spacing: 0) {
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
                        !viewModel.merchantSearchIsWaitingForLocalDebounce &&
                        !viewModel.merchantSearchIsLoading {
                        Text(noResultsText)
                            .foregroundStyle(.secondary)
                    } else {
                        if !displayedFeaturedPrimaryResults.isEmpty {
                            Section {
                                ForEach(Array(displayedFeaturedPrimaryResults.enumerated()), id: \.element.id) { index, element in
                                    merchantSearchRow(
                                        for: element,
                                        showsBottomDivider: index == displayedFeaturedPrimaryResults.count - 1
                                    )
                                }
                            } header: {
                                merchantSectionHeader(
                                    title: "Featured Nearby",
                                    systemImage: "star.fill",
                                    tint: Color(red: 0.71, green: 0.50, blue: 0.12),
                                    topPadding: 3,
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
                        } else if !displayedPrimaryResults.isEmpty {
                            ForEach(displayedPrimaryResults, id: \.id) { element in
                                merchantSearchRow(for: element)
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
            .listSectionSpacing(0)
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
        return cachedVisibleCategoryChips
    }

    private var shouldShowCategoryChips: Bool {
        guard viewModel.hasLoadedInitialData, !isShowingInitialLoadingState else { return false }
        guard viewModel.activeMerchantAlertDigest == nil else { return false }
        return !isCollapsedSheet || showFocusedSearchCategoryChips || liveSheetHeight > collapsedContentRevealHeight
    }

    private var isShowingInitialLoadingState: Bool {
        viewModel.isLoading && elements.isEmpty && !viewModel.hasLoadedInitialData
    }

    private var shouldHideCollapsedSheetContent: Bool {
        isCollapsedSheet &&
        !isFilteringMerchants &&
        !showFocusedSearchCategoryChips &&
        liveSheetHeight <= collapsedContentRevealHeight
    }

    private var collapsedContentRevealHeight: CGFloat {
        140
    }

    private var contentRevealProgress: CGFloat {
        if !isCollapsedSheet || showFocusedSearchCategoryChips {
            return 1
        }

        let revealRange: CGFloat = 36
        let rawProgress = (liveSheetHeight - collapsedContentRevealHeight) / revealRange
        return min(max(rawProgress, 0), 1)
    }

    private var searchStatusText: String? {
        if viewModel.merchantSearchIsWaitingForLocalDebounce {
            return "Searching nearby…"
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

    private var hasMoreSearchResults: Bool {
        let totalCount = viewModel.merchantSearchPrimaryResults.count
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
        viewModel.isSearchActive = true
        viewModel.unifiedSearchText = chip.localizedLabel
    }

    private func refreshDiscoveryCache() {
        cachedTopSortedElements = nearestElements(elements, limit: maxListResults)
        cachedVisibleCategoryChips = ElementCategorySymbols.merchantCategoryChips(for: elements, limit: 6)
    }

    private func syncDisplayedSearchResultsToMap() {
        guard trimmedSearchQuery.count >= 2 else {
            viewModel.clearMerchantSearchMapResults()
            return
        }
        viewModel.setMerchantSearchMapResults(displayedPrimaryResults)
    }

    private func clearSearchDrivenMapResults() {
        viewModel.clearMerchantSearchMapResults()
    }

    private func keyboardAnimation(for notification: Notification) -> Animation {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        return .easeInOut(duration: duration)
    }

    private func merchantSearchRow(for element: Element, showsBottomDivider: Bool = false) -> some View {
        let cellVM = cellViewModel(for: element)
        return NavigationLink {
            businessDetailDestination(for: element)
        } label: {
            ElementCell(viewModel: cellVM, showsBottomDivider: showsBottomDivider)
        }
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: [element])
        }
    }

    private func merchantRow(for element: Element, showsBottomDivider: Bool = false) -> some View {
        let cellVM = cellViewModel(for: element)
        return NavigationLink {
            businessDetailDestination(for: element)
        } label: {
            ElementCell(viewModel: cellVM, showsBottomDivider: showsBottomDivider)
        }
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

    private func businessDetailDestination(for element: Element) -> some View {
        BusinessDetailView(
            element: element,
            userLocation: viewModel.userLocation,
            contentViewModel: viewModel,
            currentDetent: $currentDetent
        )
        .onAppear {
            prepareListNavigation(for: element)
        }
    }

    private func prepareListNavigation(for element: Element) {
        viewModel.setSelectionSource(.list)
        viewModel.selectAnnotationForListSelection(
            element,
            animated: true,
            allowCameraMovement: !isLargeSheet
        )
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
        guard viewModel.hasLoadedInitialData else { return false }
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
    var showsBottomDivider = false
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
            
            if let primaryLine = viewModel.compactDisplayAddress?.primaryLine {
                HStack(alignment: .center, spacing: 8) {
                    Text(primaryLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }

            HStack {
                if let secondaryLine = viewModel.compactDisplayAddress?.secondaryLine {
                    Text(secondaryLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                PaymentIcons(element: viewModel.element)
            }

            if showsBottomDivider {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.trailing, -18)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            appeared = true
            viewModel.onCellAppear()
        }
        .onDisappear {
            guard appeared else { return }
            appeared = false
            viewModel.onCellDisappear()
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
    let allowsLiveAddressEnrichment: Bool
    @Published var address: Address?
    @Published private(set) var compactDisplayAddress: FormattedAddress?
    
    // OPTIMIZED: Remove the excessive logging from userLocation didSet
    @Published var userLocation: CLLocation?
    
    private var userLocationCancellable: AnyCancellable?
    private var lastLocationUpdate: CLLocationCoordinate2D?
    private var isAddressLookupInFlight = false
    private var isCompactDisplayFrozen = false
    
    init(
        element: Element,
        userLocation: CLLocation?,
        viewModel: ContentViewModel,
        allowsLiveAddressEnrichment: Bool = false
    ) {
        self.element = element
        self.userLocation = userLocation
        self.viewModel = viewModel
        self.allowsLiveAddressEnrichment = allowsLiveAddressEnrichment
        
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
        
        if let cachedEntry = getCachedAddressEntry(), allowsLiveAddressEnrichment {
            self.address = Address.merged(preferred: element.address, fallback: cachedEntry.address)
        } else {
            self.address = element.address
        }

        refreshCompactDisplayAddress()
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
        if !isCompactDisplayFrozen {
            refreshCompactDisplayAddress()
            isCompactDisplayFrozen = true
        }

        guard allowsLiveAddressEnrichment else { return }
        if shouldAttemptReverseGeocode() {
            updateAddress()
        }
    }

    func onCellDisappear() {
        isCompactDisplayFrozen = false
        refreshCompactDisplayAddress()
    }
    
    private var addressCacheKey: String {
        guard let coord = element.mapCoordinate else {
            return ""
        }
        return ReverseGeocodingSpatialKey.key(for: coord)
    }

    private func getCachedAddressEntry() -> ReverseGeocodingCacheEntry? {
        guard !addressCacheKey.isEmpty else { return nil }
        return viewModel.geocodingCache.getValue(forKey: addressCacheKey)
    }

    private func setCachedAddressEntry(_ entry: ReverseGeocodingCacheEntry) {
        guard !addressCacheKey.isEmpty else { return }
        viewModel.geocodingCache.setValue(entry, forKey: addressCacheKey)
    }

    func updateAddress() {
        if let cachedEntry = getCachedAddressEntry() {
            let merged = Address.merged(preferred: element.address, fallback: cachedEntry.address)
            adoptResolvedAddress(merged)
            if cachedEntry.status == .resolved || cachedEntry.status == .partial {
                return
            }
            if !cachedEntry.shouldRetry() {
                return
            }
        } else if let preferred = element.address {
            adoptResolvedAddress(preferred)
            if preferred.hasAnyGeocodingFields && !Address.needsEnrichment(preferred) {
                setCachedAddressEntry(.forAddress(preferred))
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
                        countryName: self.normalized(placemark.country),
                        countryCode: self.normalized(placemark.isoCountryCode),
                        regionOrStateName: self.normalized(placemark.administrativeArea)
                    ),
                    regionOrStateName: self.normalized(placemark.administrativeArea),
                    countryName: self.normalized(placemark.country),
                    countryCode: self.normalized(placemark.isoCountryCode)
                )
                let merged = Address.merged(preferred: self.element.address, fallback: Address.merged(preferred: geocodedAddress, fallback: self.address))
                self.adoptResolvedAddress(merged)
                if let merged {
                    _ = self.viewModel.persistResolvedAddress(merged, forMerchantID: self.element.id)
                }

                if let merged, merged.hasAnyGeocodingFields {
                    self.setCachedAddressEntry(.forAddress(merged))
                } else {
                    self.setCachedAddressEntry(
                        .noResult(retryAfter: Date().addingTimeInterval(24 * 60 * 60))
                    )
                }
            } else if let staleFallback, staleFallback.hasAnyGeocodingFields {
                self.adoptResolvedAddress(Address.merged(preferred: self.element.address, fallback: staleFallback))
                self.setCachedAddressEntry(.forAddress(staleFallback))
            } else if let retryAfter = response.retryAfter {
                self.setCachedAddressEntry(.failed(retryAfter: retryAfter))
            } else {
                self.setCachedAddressEntry(
                    .noResult(retryAfter: Date().addingTimeInterval(24 * 60 * 60))
                )
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

    private func refreshCompactDisplayAddressIfNeeded() {
        guard !isCompactDisplayFrozen else { return }
        refreshCompactDisplayAddress()
    }

    func adoptResolvedAddress(_ newAddress: Address?) {
        address = newAddress
        refreshCompactDisplayAddressIfNeeded()
    }

    private func refreshCompactDisplayAddress() {
        compactDisplayAddress = element.formattedAddress(
            using: address,
            style: .compact(referenceRegionCode: Locale.autoupdatingCurrent.region?.identifier)
        )
    }

    private func shouldAttemptReverseGeocode() -> Bool {
        if isAddressLookupInFlight {
            return false
        }

        if let cachedEntry = getCachedAddressEntry() {
            switch cachedEntry.status {
            case .resolved:
                let merged = Address.merged(preferred: element.address, fallback: cachedEntry.address)
                return Address.needsEnrichment(merged)
            case .partial:
                let merged = Address.merged(preferred: element.address, fallback: cachedEntry.address)
                return Address.needsEnrichment(merged)
            case .noResult, .failed:
                return cachedEntry.shouldRetry()
            }
        }

        guard let currentAddress = address else {
            return true
        }

        return Address.needsEnrichment(currentAddress)
    }

    private func addressesMatch(_ lhs: Address?, _ rhs: Address?) -> Bool {
        normalized(lhs?.streetNumber) == normalized(rhs?.streetNumber) &&
        normalized(lhs?.streetName) == normalized(rhs?.streetName) &&
        normalized(lhs?.cityOrTownName) == normalized(rhs?.cityOrTownName) &&
        normalized(lhs?.postalCode) == normalized(rhs?.postalCode) &&
        normalized(lhs?.regionOrStateName) == normalized(rhs?.regionOrStateName) &&
        normalized(lhs?.countryName) == normalized(rhs?.countryName) &&
        normalized(lhs?.countryCode) == normalized(rhs?.countryCode)
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
