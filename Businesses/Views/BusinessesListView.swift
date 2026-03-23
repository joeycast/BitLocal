// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation
import UIKit

struct BusinessesListView: View {

    @EnvironmentObject var viewModel: ContentViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    let maxListResults = 25
    var elements: [Element]
    var userLocation: CLLocation?
    var liveSheetHeight: CGFloat = 0
    @Binding private var currentDetent: PresentationDetent?

    @State private var cellViewModels: [String: ElementCellViewModel] = [:] // Keyed by Element ID
    @State private var lastLoggedLocation: CLLocationCoordinate2D? // Track last logged location
    @State private var searchResultsLimit = 20
    @State private var discoveryResultsLimit = 25
    @State private var cachedTopSortedElements: [Element] = []
    @State private var cachedVisibleCategoryChips: [MerchantCategoryChip] = []
    @State private var showFocusedSearchCategoryChips = false
    @State private var canShowEmptyState = false
    @State private var emptyStateRevealWorkItem: DispatchWorkItem?
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
                .padding(.top, searchBarTopPadding)
                .padding(.bottom, 2)

            if shouldShowCategoryChips && !visibleCategoryChips.isEmpty {
                categoryChipsView
                    .padding(.bottom, categoryChipsBottomPadding)
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
                } else if shouldShowDiscoveryLoadingState {
                    LoadingScreenView()
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
            syncDisplayedSearchResultsToMap()
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
            discoveryResultsLimit = maxListResults
            refreshDiscoveryCache()
            refreshEmptyStateVisibility()
        }
        .onAppear {
            viewModel.ensureEventsLoaded()
            viewModel.ensureAreasLoaded() // Keep community/area data warming in background during merchant browsing.
            refreshDiscoveryCache()
            syncDisplayedSearchResultsToMap()
            refreshEmptyStateVisibility()
        }
        .onChange(of: viewModel.isLoading) { _, _ in
            refreshEmptyStateVisibility()
        }
        .onChange(of: viewModel.hasLoadedInitialData) { _, _ in
            refreshEmptyStateVisibility()
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
        .featureHintAnchor(.merchantSearch)
    }

    private var searchBarTopPadding: CGFloat {
        if horizontalSizeClass == .regular {
            return 10
        }
        if #available(iOS 26.0, *) {
            return 20
        }
        return 16
    }

    private var categoryChipsBottomPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 6
        }
        return -8
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
                            showsBottomDivider: index == featuredTopSortedElements.count - 1,
                            hidesTopSeparator: index == 0
                        )
                    }
                } header: {
                    merchantSectionHeader(
                        title: NSLocalizedString("Featured Nearby", comment: "Section header for boosted nearby merchants"),
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
                    ForEach(Array(regularTopSortedElements.enumerated()), id: \.element.id) { index, element in
                        merchantRow(for: element, hidesTopSeparator: index == 0)
                    }

                    if hasMoreDiscoveryResults {
                        Button("Load more results") {
                            discoveryResultsLimit += maxListResults
                            refreshDiscoveryCache()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.accent)
                        .clearListRowBackground(if: shouldUseGlassyRows)
                    }

                    footerView
                        .clearListRowBackground(if: shouldUseGlassyRows)
                } header: {
                    if !featuredTopSortedElements.isEmpty {
                        merchantSectionHeader(
                            title: NSLocalizedString("More Nearby", comment: "Section header for additional nearby merchants"),
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
                        Text(String(format: NSLocalizedString("New merchants in %@", comment: "Digest header showing the city name"), digest.cityDisplayName))
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
                ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                    merchantRow(for: element, hidesTopSeparator: index == 0)
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
                        .listRowSeparator(.hidden, edges: .top)
                } else if trimmedSearchQuery.count >= 2 {
                    if let statusText = searchStatusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden, edges: .top)
                    }

                    if displayedPrimaryResults.isEmpty &&
                        !viewModel.merchantSearchIsWaitingForLocalDebounce &&
                        !viewModel.merchantSearchIsLoading {
                        Text(noResultsText)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden, edges: .top)
                    } else {
                        if !displayedFeaturedPrimaryResults.isEmpty {
                            Section {
                                ForEach(Array(displayedFeaturedPrimaryResults.enumerated()), id: \.element.id) { index, element in
                                    merchantSearchRow(
                                        for: element,
                                        showsBottomDivider: index == displayedFeaturedPrimaryResults.count - 1,
                                        hidesTopSeparator: index == 0
                                    )
                                }
                            } header: {
                                merchantSectionHeader(
                                    title: NSLocalizedString("Featured Nearby", comment: "Section header for boosted nearby search results"),
                                    systemImage: "star.fill",
                                    tint: Color(red: 0.71, green: 0.50, blue: 0.12),
                                    topPadding: 3,
                                    bottomPadding: -10
                                )
                            }
                        }

                        if !displayedRegularPrimaryResults.isEmpty || displayedFeaturedPrimaryResults.isEmpty {
                            Section {
                                ForEach(Array(displayedRegularPrimaryResults.enumerated()), id: \.element.id) { index, element in
                                    merchantSearchRow(for: element, hidesTopSeparator: index == 0)
                                }
                            } header: {
                                if !displayedFeaturedPrimaryResults.isEmpty {
                                    merchantSectionHeader(
                                        title: NSLocalizedString("More Nearby", comment: "Section header for additional nearby search results"),
                                        systemImage: "location.fill",
                                        tint: .secondary,
                                        topPadding: 4,
                                        bottomPadding: -14
                                    )
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

    private var shouldShowDiscoveryLoadingState: Bool {
        guard !isFilteringMerchants else { return false }
        guard viewModel.activeMerchantAlertDigest == nil else { return false }
        if viewModel.isLoading && elements.isEmpty && viewModel.allElements.isEmpty {
            return true
        }
        return viewModel.isLoading && containsPlaceholderMerchantNames(elements)
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
            return NSLocalizedString("Searching nearby…", comment: "Status shown while nearby merchant search is in progress")
        }
        return nil
    }

    private var noResultsText: String {
        NSLocalizedString("No locations match your search", comment: "Empty state for merchant search with no matches")
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

    private var hasMoreDiscoveryResults: Bool {
        elements.count > topSortedElements.count
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
            .padding(.top, categoryChipsTopPadding)
        }
    }

    private var categoryChipsTopPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 6
        }
        return 4
    }

    private func applyCategoryChip(_ chip: MerchantCategoryChip) {
        viewModel.isSearchActive = true
        viewModel.unifiedSearchText = chip.localizedLabel
    }

    private func refreshDiscoveryCache() {
        cachedTopSortedElements = nearestElements(elements, limit: discoveryResultsLimit)
        cachedVisibleCategoryChips = ElementCategorySymbols.merchantCategoryChips(for: elements, limit: 6)
    }

    private func containsPlaceholderMerchantNames(_ elements: [Element]) -> Bool {
        elements.contains { element in
            let rawName = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Element.isInvalidPrimaryName(rawName)
        }
    }

    private func syncDisplayedSearchResultsToMap() {
        guard trimmedSearchQuery.count >= 2 else {
            viewModel.clearMerchantSearchMapResults()
            return
        }
        viewModel.setMerchantSearchMapResults(displayedPrimaryResults)
    }

    private func keyboardAnimation(for notification: Notification) -> Animation {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        return .easeInOut(duration: duration)
    }

    private func merchantSearchRow(
        for element: Element,
        showsBottomDivider: Bool = false,
        hidesTopSeparator: Bool = false
    ) -> some View {
        let cellVM = cellViewModel(for: element)
        return Button {
            prepareListNavigation(for: element)
            viewModel.path = [element]
        } label: {
            ZStack(alignment: .trailing) {
                ElementCell(viewModel: cellVM, showsBottomDivider: showsBottomDivider)
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
        .listRowSeparator(hidesTopSeparator ? .hidden : .visible, edges: .top)
        .listRowSeparator(showsBottomDivider ? .hidden : .visible, edges: .bottom)
    }

    private func merchantRow(
        for element: Element,
        showsBottomDivider: Bool = false,
        hidesTopSeparator: Bool = false
    ) -> some View {
        let cellVM = cellViewModel(for: element)
        return Button {
            prepareListNavigation(for: element)
            viewModel.path = [element]
        } label: {
            ZStack(alignment: .trailing) {
                ElementCell(viewModel: cellVM, showsBottomDivider: showsBottomDivider)
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
        .listRowSeparator(hidesTopSeparator ? .hidden : .visible, edges: .top)
        .listRowSeparator(showsBottomDivider ? .hidden : .visible, edges: .bottom)
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
        Text(
            String(
                format: NSLocalizedString("showing_locations_footer", comment: "Footer: Showing N of N locations"),
                topSortedElements.count,
                elements.count
            )
        )
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
        .clearNavigationContainerBackgroundIfAvailable()
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
        guard canShowEmptyState else { return false }
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

    private func refreshEmptyStateVisibility() {
        emptyStateRevealWorkItem?.cancel()

        let shouldDelayEmptyState = !isFilteringMerchants &&
            viewModel.activeMerchantAlertDigest == nil &&
            viewModel.hasLoadedInitialData &&
            elements.isEmpty

        guard shouldDelayEmptyState else {
            canShowEmptyState = true
            return
        }

        canShowEmptyState = false

        let workItem = DispatchWorkItem {
            guard elements.isEmpty else { return }
            guard !viewModel.isLoading else { return }
            canShowEmptyState = true
        }
        emptyStateRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }
}

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
            
            HStack(alignment: .center, spacing: 8) {
                if let formatted = viewModel.address?.formatted(.compact) {
                    let lines = formatted.components(separatedBy: .newlines)
                    Text(lines.first ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack {
                if let formatted = viewModel.address?.formatted(.compact) {
                    let lines = formatted.components(separatedBy: .newlines)
                    Text(lines.dropFirst().joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PaymentIcons(element: viewModel.element)
            }

            if showsBottomDivider {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.trailing, -22)
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
                        .noResult(retryAfter: Date().addingTimeInterval(24 * 60 * 60))
                    )
                }
            } else if let staleFallback, staleFallback.hasAnyGeocodingFields {
                self.setAddressIfChanged(self.mergedAddress(preferred: self.element.address, fallback: staleFallback))
                self.setCachedAddressEntry(.forAddress(staleFallback))
            } else if let retryAfter = response.retryAfter {
                self.setCachedAddressEntry(.failed(retryAfter: retryAfter))
            } else {
                self.setCachedAddressEntry(
                    .noResult(retryAfter: Date().addingTimeInterval(24 * 60 * 60))
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
