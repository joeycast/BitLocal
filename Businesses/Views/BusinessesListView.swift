// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation
import UIKit

struct BusinessesListView: View {

    @EnvironmentObject var viewModel: ContentViewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    let maxListResults = 25
    var elements: [Element]
    var userLocation: CLLocation?
    @Binding private var currentDetent: PresentationDetent?

    @State private var lastLoggedLocation: CLLocationCoordinate2D? // Track last logged location
    @State private var searchResultsLimit = 20
    @State private var discoveryResultsLimit = 25
    @State private var cachedTopSortedElements: [Element] = []
    @State private var cachedFilteredBrowseCount = 0
    @State private var cachedVisibleCategoryChips: [MerchantCategoryChip] = []
    @State private var activeQuickFilters: Set<MerchantQuickFilter> = []
    @State private var showFocusedSearchCategoryChips = false
    @State private var canShowEmptyState = false
    @State private var emptyStateDelayTask: Task<Void, Never>?
    @State private var showingAddBusinessForm = false
    @FocusState private var isSearchFieldFocused: Bool

    @ObservedObject private var savedPlacesStore = SavedPlacesStore.shared
    @ObservedObject private var reachabilityMonitor = NetworkReachabilityMonitor.shared
    @ObservedObject private var intentRouter = BitLocalAppIntentRouter.shared

    init(
        elements: [Element],
        userLocation: CLLocation? = nil,
        currentDetent: Binding<PresentationDetent?> = .constant(nil)
    ) {
        self.elements = elements
        self.userLocation = userLocation
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
        contentWithDiscoveryObservers
            .onChange(of: viewModel.isLoading) { _, _ in
                refreshEmptyStateVisibility()
            }
            .onChange(of: viewModel.hasLoadedInitialData) { _, _ in
                refreshEmptyStateVisibility()
                viewModel.restorePersistedMerchantCategoryIfNeeded()
            }
            .onChange(of: viewModel.allElements.count) { _, _ in
                viewModel.restorePersistedMerchantCategoryIfNeeded()
                if activeQuickFilters.contains(.saved) {
                    refreshDiscoveryCache()
                }
            }
            .onChange(of: viewModel.hideATMsFromMapAndList) { _, _ in
                if activeQuickFilters.contains(.saved) {
                    refreshDiscoveryCache()
                }
            }
            .onChange(of: viewModel.visibleElements.count) { _, _ in
                viewModel.restorePersistedMerchantCategoryIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard isSearchFieldFocused else { return }
                withAnimation(BitLocalMotion.animation(keyboardAnimation(for: notification), reduceMotion: reduceMotion)) {
                    showFocusedSearchCategoryChips = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                withAnimation(BitLocalMotion.animation(keyboardAnimation(for: notification), reduceMotion: reduceMotion)) {
                    showFocusedSearchCategoryChips = false
                }
            }
    }

    private var contentWithDiscoveryObservers: some View {
        contentWithSearchObservers
            .onChange(of: activeQuickFilters) { _, _ in
                discoveryResultsLimit = maxListResults
                searchResultsLimit = 20
                refreshDiscoveryCache()
                syncDisplayedSearchResultsToMap()
                refreshEmptyStateVisibility()
            }
            .onChange(of: savedPlacesStore.savedIDs) { _, _ in
                refreshDiscoveryCache()
                syncDisplayedSearchResultsToMap()
                refreshEmptyStateVisibility()
            }
            .onChange(of: intentRouter.pendingAction) { _, _ in
                handlePendingIntentAction()
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
                if FeatureFlags.isEventsUIEnabled {
                    viewModel.ensureEventsLoaded()
                }
                viewModel.ensureAreasLoaded() // Keep community/area data warming in background during merchant browsing.
                handlePendingIntentAction()
                refreshDiscoveryCache()
                syncDisplayedSearchResultsToMap()
                refreshEmptyStateVisibility()
            }
    }

    private var contentWithSearchObservers: some View {
        mainContent
            .animation(
                BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion),
                value: reachabilityMonitor.isOffline
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheet(isPresented: $showingAddBusinessForm) {
                AddBusinessInfoView()
            }
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
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.top, searchBarTopPadding)
                .padding(.bottom, 6)

            if reachabilityMonitor.isOffline {
                offlineTravelBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .sheetCollapsedReveal(
                        geometry: viewModel.sheetGeometry,
                        isCollapsedLike: isCollapsedSheet
                    )
            }

            if !viewModel.isSearchActive && viewModel.activeMerchantAlertDigest == nil {
                SheetMapModeSwitcher(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .sheetCollapsedReveal(
                        geometry: viewModel.sheetGeometry,
                        isCollapsedLike: isCollapsedSheet
                    )
            }

            if shouldShowFilterChips && (!visibleQuickFilters.isEmpty || !visibleCategoryChips.isEmpty) {
                categoryChipsView
                    .padding(.bottom, categoryChipsBottomPadding)
                    .sheetCollapsedReveal(
                        geometry: viewModel.sheetGeometry,
                        isCollapsedLike: isCollapsedSheet,
                        forceRevealed: showFocusedSearchCategoryChips || isFilteringMerchants
                    )
            }

            ZStack {
                if isShowingInitialLoadingState {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isFilteringMerchants {
                    searchResultsView
                } else if viewModel.activeMerchantAlertDigest != nil {
                    digestResultsView
                } else if shouldShowDiscoveryLoadingState {
                    LoadingScreenView()
                } else if !activeQuickFilters.isEmpty && cachedFilteredBrowseCount == 0 {
                    quickFilterEmptyStateView
                } else if activeQuickFilters.isEmpty && elements.isEmpty {
                    if shouldShowEmptyState {
                        merchantEmptyStateView
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
            // Keep list identity stable while collapsed; only the reveal modifier
            // observes live sheet height (avoids recreating List on every drag tick).
            .sheetCollapsedReveal(
                geometry: viewModel.sheetGeometry,
                isCollapsedLike: isCollapsedSheet,
                forceRevealed: isFilteringMerchants || showFocusedSearchCategoryChips
            )
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.primary.opacity(0.65))
                .font(.subheadline.weight(.medium))
            TextField(
                "",
                text: $viewModel.unifiedSearchText,
                prompt: Text("Search merchants…").foregroundStyle(Color.primary.opacity(0.6))
            )
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
            if !viewModel.unifiedSearchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    BitLocalHaptics.selection()
                    viewModel.clearMerchantSearch(userInitiated: true)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .padding(.vertical, -11)
                .padding(.horizontal, -8)
                .buttonStyle(.tactilePress(scale: 0.92))
            }
            if viewModel.isSearchActive {
                Button("Cancel") {
                    BitLocalHaptics.selection()
                    isSearchFieldFocused = false
                    viewModel.clearMerchantSearch(userInitiated: true)
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.tactilePress(scale: 0.96))
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .trailing).combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(searchFieldSurfaceColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .animation(
            BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion),
            value: viewModel.isSearchActive
        )
        .featureHintAnchor(.merchantSearch)
    }

    private var offlineTravelBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Offline · Browsing \(viewModel.allElements.count.formatted()) cached places")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var searchFieldSurfaceColor: Color {
        guard shouldUseGlassyRows else {
            return Color(.tertiarySystemFill)
        }
        return Color(.systemBackground).opacity(colorScheme == .dark ? 0.24 : 0.58)
    }

    private var searchBarTopPadding: CGFloat {
        // Side-panel presentation (no sheet detent) gets its top offset from the split sidebar container.
        if currentDetent == nil {
            return 0
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
        return shouldUseCompactChipSpacingBelow ? -8 : 6
    }

    private var shouldUseCompactChipSpacingBelow: Bool {
        if isFilteringMerchants {
            return !displayedFeaturedPrimaryResults.isEmpty
        }
        return !featuredTopSortedElements.isEmpty
    }

    // MARK: - Normal Mode (discovery hub)

    private var normalListView: some View {
        List {
            // Kept behind FeatureFlags.isEventsUIEnabled until product is ready.
            if FeatureFlags.isEventsUIEnabled {
                Section {
                    EventsDiscoverySection()
                        .environmentObject(viewModel)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .clearListRowBackground(if: shouldUseGlassyRows)
                }
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

    private var merchantEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateSystemImage)
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if shouldShowEmptyStateRetry {
                Button {
                    viewModel.refreshMerchantData(userInitiated: true)
                } label: {
                    Text(NSLocalizedString("Try Again", comment: "Retry button when merchant sync fails"))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            } else if !viewModel.allElements.isEmpty {
                VStack(spacing: 8) {
                    Button {
                        viewModel.zoomOutMapToExploreNearby()
                    } label: {
                        Label("Zoom Out to Find More", systemImage: "minus.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingAddBusinessForm = true
                    } label: {
                        Label("Add a Bitcoin Business", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }

            if let syncLine = lastSyncedFooterLine {
                Text(syncLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    private var quickFilterEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: activeQuickFilters == [.saved] ? "bookmark.slash" : "line.3.horizontal.decrease.circle")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(quickFilterEmptyStateTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(quickFilterEmptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                BitLocalHaptics.selection()
                activeQuickFilters.removeAll()
            } label: {
                Text(NSLocalizedString("Clear Filters", comment: "Button to clear active merchant quick filters"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private var quickFilterEmptyStateTitle: String {
        if activeQuickFilters == [.saved] {
            return NSLocalizedString("No saved places", comment: "Empty state title when Saved filter has no matching places")
        }
        return NSLocalizedString("No matching places", comment: "Empty state title when quick filters yield zero matches")
    }

    private var quickFilterEmptyStateMessage: String {
        if activeQuickFilters == [.saved] {
            return NSLocalizedString(
                "Save places from any merchant detail page to find them quickly here.",
                comment: "Empty state message when Saved filter has no matching places"
            )
        }
        return NSLocalizedString(
            "No places match your active filters. Try clearing one or more filters to see more merchants.",
            comment: "Empty state message when quick filters yield zero matches"
        )
    }

    private var emptyStateSystemImage: String {
        if viewModel.merchantSyncFailed && viewModel.allElements.isEmpty {
            return "wifi.exclamationmark"
        }
        if viewModel.allElements.isEmpty {
            return "arrow.triangle.2.circlepath"
        }
        return "mappin.slash"
    }

    private var emptyStateTitle: String {
        if viewModel.merchantSyncFailed && viewModel.allElements.isEmpty {
            return NSLocalizedString("Couldn't load merchants", comment: "Title when merchant dataset failed to load")
        }
        if viewModel.allElements.isEmpty {
            return NSLocalizedString("Updating merchants…", comment: "Title while waiting for first merchant sync")
        }
        return NSLocalizedString("no_locations_found", comment: "Empty state for no locations found")
    }

    private var emptyStateMessage: String {
        if let message = viewModel.merchantSyncStatusMessage, !message.isEmpty {
            return message
        }
        if viewModel.allElements.isEmpty {
            return NSLocalizedString(
                "BitLocal is downloading the latest Bitcoin merchants. Use Try Again if this takes too long, or refresh merchants in About.",
                comment: "Message while waiting for first merchant sync"
            )
        }
        return NSLocalizedString(
            "No Bitcoin merchants in this map area. Pan or zoom to explore nearby places.",
            comment: "Empty state when the viewport has no merchants but the catalog is loaded"
        )
    }

    private var shouldShowEmptyStateRetry: Bool {
        viewModel.merchantSyncFailed || (viewModel.hasLoadedInitialData && viewModel.allElements.isEmpty)
    }

    private var lastSyncedFooterLine: String? {
        guard let relative = viewModel.lastSuccessfulSyncRelativeDescription else { return nil }
        return String(
            format: NSLocalizedString("Updated %@", comment: "Relative last-synced label, e.g. Updated 5 minutes ago"),
            relative
        )
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
                    .clearListRowBackground(if: shouldUseGlassyRows)
                }
                .clearListRowBackground(if: shouldUseGlassyRows)
            }

            Section {
                ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                    merchantRow(for: element, hidesTopSeparator: index == 0)
                }

                footerView
                    .clearListRowBackground(if: shouldUseGlassyRows)
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
                        .clearListRowBackground(if: shouldUseGlassyRows)
                } else if trimmedSearchQuery.count >= 2 {
                    if let statusText = searchStatusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden, edges: .top)
                            .clearListRowBackground(if: shouldUseGlassyRows)
                    }

                    if displayedPrimaryResults.isEmpty &&
                        !viewModel.merchantSearchIsWaitingForLocalDebounce &&
                        !viewModel.merchantSearchIsLoading {
                        if !activeQuickFilters.isEmpty {
                            quickFilterEmptyStateView
                                .listRowSeparator(.hidden)
                                .clearListRowBackground(if: shouldUseGlassyRows)
                        } else {
                            Text(noResultsText)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden, edges: .top)
                                .clearListRowBackground(if: shouldUseGlassyRows)
                        }
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
                            .clearListRowBackground(if: shouldUseGlassyRows)
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
                            .clearListRowBackground(if: shouldUseGlassyRows)
                        }
                    }

                    if hasMoreSearchResults {
                        Button("Load more results") {
                            searchResultsLimit += 20
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.accent)
                        .clearListRowBackground(if: shouldUseGlassyRows)
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

    private var visibleQuickFilters: [MerchantQuickFilter] {
        MerchantQuickFilter.allCases.filter { filter in
            if filter == .saved {
                return !savedPlacesStore.savedIDs.isEmpty || activeQuickFilters.contains(.saved)
            }
            return true
        }
    }

    private var shouldShowFilterChips: Bool {
        guard viewModel.hasLoadedInitialData, !isShowingInitialLoadingState else { return false }
        guard viewModel.activeMerchantAlertDigest == nil else { return false }
        // Detent-based visibility; continuous fade is handled by sheetCollapsedReveal.
        return !isCollapsedSheet || showFocusedSearchCategoryChips || isFilteringMerchants
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

    private var searchStatusText: String? {
        if viewModel.merchantSearchIsWaitingForLocalDebounce {
            return NSLocalizedString("Searching nearby…", comment: "Status shown while nearby merchant search is in progress")
        }
        return nil
    }

    private var noResultsText: String {
        NSLocalizedString("No locations match your search", comment: "Empty state for merchant search with no matches")
    }

    private var browseSourceElements: [Element] {
        if activeQuickFilters.contains(.saved) {
            return viewModel.elementsForDisplay(viewModel.allElements)
        }
        return elements
    }

    private var totalDiscoveryCount: Int {
        activeQuickFilters.isEmpty ? elements.count : cachedFilteredBrowseCount
    }

    private var filteredPrimarySearchResults: [Element] {
        applyQuickFilters(to: viewModel.merchantSearchPrimaryResults)
    }

    private var displayedPrimaryResults: [Element] {
        let filtered = filteredPrimarySearchResults
        let limit = min(searchResultsLimit, filtered.count)
        return Array(filtered.prefix(limit))
    }

    private var displayedFeaturedPrimaryResults: [Element] {
        displayedPrimaryResults.filter { $0.isCurrentlyBoosted() }
    }

    private var displayedRegularPrimaryResults: [Element] {
        displayedPrimaryResults.filter { !$0.isCurrentlyBoosted() }
    }

    private var hasMoreSearchResults: Bool {
        let totalCount = filteredPrimarySearchResults.count
        return totalCount > searchResultsLimit
    }

    private var hasMoreDiscoveryResults: Bool {
        totalDiscoveryCount > topSortedElements.count
    }

    private var activeCategoryChipGroup: MerchantCategoryGroup? {
        guard isFilteringMerchants else { return nil }
        let normalized = trimmedSearchQuery.lowercased()
        return visibleCategoryChips.first {
            $0.localizedLabel.lowercased() == normalized
        }?.group
    }

    private var categoryChipsView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(visibleQuickFilters) { filter in
                    let isSelected = activeQuickFilters.contains(filter)
                    let title = quickFilterTitle(for: filter)
                    Button {
                        toggleQuickFilter(filter)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(title)
                                .font(.footnote.weight(.medium))
                            if isSelected {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 36)
                        .background(
                            isSelected ? Color.accentColor : chipSurfaceColor,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.primary.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        }
                        .animation(
                            BitLocalMotion.animation(BitLocalMotion.press, reduceMotion: reduceMotion),
                            value: isSelected
                        )
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactilePress(scale: 0.96))
                    .accessibilityLabel(Text(title))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(
                        isSelected
                            ? NSLocalizedString("Double-tap to clear filter", comment: "VoiceOver hint for selected quick filter chip")
                            : NSLocalizedString("Double-tap to filter merchants", comment: "VoiceOver hint for unselected quick filter chip")
                    )
                }

                if !visibleQuickFilters.isEmpty && !visibleCategoryChips.isEmpty {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)
                        .accessibilityHidden(true)
                }

                ForEach(visibleCategoryChips) { chip in
                    let isSelected = activeCategoryChipGroup == chip.group
                    Button {
                        applyCategoryChip(chip)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.symbolName)
                                .font(.caption.weight(.semibold))
                            Text(chip.localizedLabel)
                                .font(.footnote.weight(.medium))
                            if isSelected {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 36)
                        .background(
                            isSelected ? Color.accentColor : chipSurfaceColor,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.primary.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        }
                        .animation(
                            BitLocalMotion.animation(BitLocalMotion.press, reduceMotion: reduceMotion),
                            value: isSelected
                        )
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactilePress(scale: 0.96))
                    .accessibilityLabel(Text(chip.localizedLabel))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(
                        isSelected
                            ? NSLocalizedString("Double-tap to clear category filter", comment: "VoiceOver hint for selected category chip")
                            : NSLocalizedString("Double-tap to filter nearby merchants", comment: "VoiceOver hint for unselected category chip")
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, categoryChipsTopPadding)
        }
        .scrollIndicators(.hidden)
    }

    private var chipSurfaceColor: Color {
        guard shouldUseGlassyRows else {
            return Color(.secondarySystemFill)
        }
        return Color(.systemBackground).opacity(colorScheme == .dark ? 0.24 : 0.60)
    }

    private var categoryChipsTopPadding: CGFloat {
        if #available(iOS 26.0, *) {
            return 2
        }
        return 0
    }

    private func quickFilterTitle(for filter: MerchantQuickFilter) -> String {
        if filter == .saved, !savedPlacesStore.savedIDs.isEmpty {
            return "\(filter.displayTitle) (\(savedPlacesStore.savedIDs.count))"
        }
        return filter.displayTitle
    }

    private func toggleQuickFilter(_ filter: MerchantQuickFilter) {
        BitLocalHaptics.selection()
        if activeQuickFilters.contains(filter) {
            activeQuickFilters.remove(filter)
        } else {
            activeQuickFilters.insert(filter)
        }
    }

    private func applyQuickFilters(to source: [Element]) -> [Element] {
        guard !activeQuickFilters.isEmpty else { return source }
        let now = Date.now
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)
            ?? now.addingTimeInterval(-365 * 24 * 60 * 60)

        let requiresSaved = activeQuickFilters.contains(.saved)
        let requiresLightning = activeQuickFilters.contains(.lightning)
        let requiresNFC = activeQuickFilters.contains(.nfc)
        let requiresVerified = activeQuickFilters.contains(.verified)
        let requiresOpenNow = activeQuickFilters.contains(.openNow)

        return source.filter { element in
            if requiresSaved && !savedPlacesStore.isSaved(element.id) {
                return false
            }
            if requiresLightning && !acceptsLightning(element: element) {
                return false
            }
            if requiresNFC && !acceptsContactlessLightning(element: element) {
                return false
            }
            if requiresVerified {
                guard let verifiedDate = BTCMapDateParser.parse(element.v4Metadata?.verifiedAt),
                      verifiedDate >= oneYearAgo else {
                    return false
                }
            }
            if requiresOpenNow {
                guard OpeningHoursLiveStatus.isOpenNow(
                    rawOpeningHours: element.osmJSON?.tags?.openingHours,
                    now: now,
                    calendar: calendar
                ) else {
                    return false
                }
            }
            return true
        }
    }

    private func handlePendingIntentAction() {
        guard let action = intentRouter.pendingAction else { return }
        if case .openMerchants(let filter, let query) = action {
            _ = intentRouter.consumePendingAction()
            if viewModel.mapDisplayMode != .merchants {
                viewModel.setMapDisplayMode(.merchants)
            }
            if let filter {
                activeQuickFilters = [filter]
            }
            if let query {
                viewModel.unifiedSearchText = query
            }
        }
    }

    private func applyCategoryChip(_ chip: MerchantCategoryChip) {
        BitLocalHaptics.selection()
        if activeCategoryChipGroup == chip.group {
            viewModel.clearMerchantSearch(userInitiated: true)
        } else {
            viewModel.applyMerchantCategoryChip(chip)
        }
    }

    private func refreshDiscoveryCache() {
        let filteredBrowse = applyQuickFilters(to: browseSourceElements)
        cachedFilteredBrowseCount = filteredBrowse.count
        cachedTopSortedElements = nearestElements(filteredBrowse, limit: discoveryResultsLimit)
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
            viewModel.path = [.place(element)]
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ElementCell(
                    viewModel: cellVM,
                    showsBottomDivider: showsBottomDivider,
                    isSaved: savedPlacesStore.isSaved(element.id)
                )
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.tactileRow)
        .onAppear {
            viewModel.requestPlaceholderNameHydration(for: [element])
        }
        .listRowSeparator(hidesTopSeparator ? .hidden : .visible, edges: .top)
        .listRowSeparator(showsBottomDivider ? .hidden : .visible, edges: .bottom)
        .clearListRowBackground(if: shouldUseGlassyRows)
    }

    private func merchantRow(
        for element: Element,
        showsBottomDivider: Bool = false,
        hidesTopSeparator: Bool = false
    ) -> some View {
        let cellVM = cellViewModel(for: element)
        return Button {
            prepareListNavigation(for: element)
            viewModel.path = [.place(element)]
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ElementCell(
                    viewModel: cellVM,
                    showsBottomDivider: showsBottomDivider,
                    isSaved: savedPlacesStore.isSaved(element.id)
                )
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.tactileRow)
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
            HStack(alignment: .center, spacing: 10) {
                ElementCell(
                    viewModel: cellVM,
                    isSaved: savedPlacesStore.isSaved(remoteElement.id)
                )
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.tactileRow)
        .onAppear {
            viewModel.hydrateMerchantSearchPreviewIfNeeded(result)
        }
        .clearListRowBackground(if: shouldUseGlassyRows)
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
    }

    private func cellViewModel(for element: Element) -> ElementCellViewModel {
        if let vm = viewModel.cellViewModels[element.id] {
            let currentName = vm.element.displayNameForUI ?? ""
            let nextName = element.displayNameForUI ?? ""
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    String(
                        format: NSLocalizedString("showing_locations_footer", comment: "Footer: Showing N of N locations"),
                        topSortedElements.count,
                        totalDiscoveryCount
                    )
                )
                if let syncLine = lastSyncedFooterLine {
                    Text(syncLine)
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.65))

            if activeQuickFilters.isEmpty && elements.count <= 3 && viewModel.activeMerchantAlertDigest == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        viewModel.zoomOutMapToExploreNearby()
                    } label: {
                        Label("Zoom Out to Find More", systemImage: "minus.magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingAddBusinessForm = true
                    } label: {
                        Label("Add a Bitcoin Business", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
        return viewModel.sortedElementsForMerchantBrowse(source, limit: limit)
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
        if #available(iOS 26.0, *) {
            // Keep the List transparent at every detent (including `.large`) so
            // rows never render stark white over the system sheet's tinted surface.
            return true
        }
        return detent != .large
    }

    private var shouldUseGlassyRows: Bool {
        guard currentDetent != nil else { return false }
        guard #available(iOS 26.0, *) else { return false }
        return true
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
        return detent == BottomSheetDetents.expandedLeading || detentIdentifier(detent).contains("large")
    }

    private var collapsedSheetDetent: PresentationDetent {
        BottomSheetDetents.collapsed
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    private func refreshEmptyStateVisibility() {
        emptyStateDelayTask?.cancel()
        emptyStateDelayTask = nil

        let shouldDelayEmptyState = !isFilteringMerchants &&
            activeQuickFilters.isEmpty &&
            viewModel.activeMerchantAlertDigest == nil &&
            viewModel.hasLoadedInitialData &&
            elements.isEmpty

        guard shouldDelayEmptyState else {
            canShowEmptyState = true
            return
        }

        canShowEmptyState = false

        emptyStateDelayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard elements.isEmpty, activeQuickFilters.isEmpty else { return }
            guard !viewModel.isLoading else { return }
            canShowEmptyState = true
        }
    }
}

struct ElementCell: View {

    @ObservedObject var viewModel: ElementCellViewModel
    var showsBottomDivider = false
    var isSaved = false
    @State private var appeared = false
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    private var categoryBadgeSymbolName: String {
        ElementCategoryBadgeHelper.badgeSymbolName(for: viewModel.element)
    }

    private var formattedDistance: String? {
        if let distance = localizedDistanceString(for: viewModel.element) {
            return distance
        }
        if let distance = viewModel.viewModel.distanceInMiles(element: viewModel.element) {
            let fractionDigits = distance < 1 ? 2 : 1
            return Measurement(value: distance, unit: UnitLength.miles).formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
                )
                .locale(locale)
            )
        }
        return nil
    }

    private var addressLines: [String] {
        guard let formatted = viewModel.address?.formatted(.compact) else { return [] }
        return formatted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Solid map-pin badge (MarkerColor circle + crisp white symbol)
                // links each row 1:1 to its map marker in both Light and Dark Mode.
                Image(systemName: categoryBadgeSymbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color("MarkerColor"), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
                    }
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(
                            viewModel.element.displayNameForUI ??
                            NSLocalizedString("name_not_available", comment: "Fallback name for unavailable business name")
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isSaved || formattedDistance != nil {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                if isSaved {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel(NSLocalizedString("Saved", comment: "VoiceOver label for saved place indicator"))
                                }

                                if let distance = formattedDistance {
                                    Text(distance)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Color.primary.opacity(0.68))
                                        .fixedSize()
                                }
                            }
                        }
                    }

                    if let firstLine = addressLines.first {
                        Text(firstLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .lineLimit(1)
                    }

                    let secondaryLine = addressLines.dropFirst().joined(separator: ", ")
                    HStack(alignment: .center, spacing: 8) {
                        if !secondaryLine.isEmpty {
                            Text(secondaryLine)
                                .font(.footnote)
                                .foregroundStyle(Color.primary.opacity(0.65))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }

                        PaymentIcons(element: viewModel.element)
                    }
                }
            }
            .padding(.vertical, 4)

            if showsBottomDivider {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                    .padding(.top, 8)
                    .padding(.trailing, -22)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            guard !appeared else { return }
            appeared = true
            viewModel.onCellAppear()
        }
    }
    
    private func localizedDistanceString(for element: Element) -> String? {
        guard let userLocation = viewModel.viewModel.userLocation, let coord = element.mapCoordinate else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let useMetric: Bool
        switch distanceUnit {
        case .auto:
            useMetric = locale.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        let value = useMetric ? (distanceInMeters / 1000) : (distanceInMeters / 1609.344)
        let unit: UnitLength = useMetric ? .kilometers : .miles
        let fractionDigits = value < 1 ? 2 : 1
        return Measurement(value: value, unit: unit).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
            )
            .locale(locale)
        )
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
struct PaymentIcons: View {
    let element: Element

    var body: some View {
        HStack(spacing: 6) {
            if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(NSLocalizedString("On-chain Bitcoin", comment: "VoiceOver payment method"))
            }

            if acceptsLightning(element: element) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(NSLocalizedString("Lightning", comment: "VoiceOver payment method"))
            }

            if acceptsContactlessLightning(element: element) {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(NSLocalizedString("Contactless Lightning", comment: "VoiceOver payment method"))
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(paymentMethodsAccessibilityLabel)
    }

    private var paymentMethodsAccessibilityLabel: String {
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
        if methods.isEmpty {
            return NSLocalizedString("Payment methods unavailable", comment: "VoiceOver when no payment method icons are shown")
        }
        return String(
            format: NSLocalizedString("Accepts %@", comment: "VoiceOver summary of accepted payment methods"),
            methods.formatted(.list(type: .and))
        )
    }
}
