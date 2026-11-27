// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation
import UIKit

struct BusinessesListView: View {

    @Environment(ContentViewModel.self) var viewModel
    @Environment(\.calendar) var calendar
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    let maxListResults = 25
    var elements: [Element]
    var userLocation: CLLocation?
    @Binding var currentDetent: PresentationDetent?

    @State var lastLoggedLocation: CLLocationCoordinate2D? // Track last logged location
    @State var searchResultsLimit = 20
    @State var discoveryResultsLimit = 25
    @State var cachedTopSortedElements: [Element] = []
    @State var cachedFilteredBrowseCount = 0
    @State var cachedVisibleCategoryChips: [MerchantCategoryChip] = []
    @State var showFocusedSearchCategoryChips = false
    @State var canShowEmptyState = false
    @State var emptyStateDelayTask: Task<Void, Never>?
    @State var showingAddBusinessForm = false
    @FocusState private var isSearchFieldFocused: Bool

    let savedPlacesStore = SavedPlacesStore.shared
    private let reachabilityMonitor = NetworkReachabilityMonitor.shared

    init(
        elements: [Element],
        userLocation: CLLocation? = nil,
        currentDetent: Binding<PresentationDetent?> = .constant(nil)
    ) {
        self.elements = elements
        self.userLocation = userLocation
        self._currentDetent = currentDetent
    }

    var topSortedElements: [Element] {
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
                if viewModel.hasActiveChipFilters {
                    refreshDiscoveryCache()
                }
            }
            .onChange(of: viewModel.hideATMsFromMapAndList) { _, _ in
                if viewModel.hasActiveChipFilters {
                    refreshDiscoveryCache()
                }
            }
            .onChange(of: viewModel.visibleElements.count) { _, _ in
                viewModel.restorePersistedMerchantCategoryIfNeeded()
            }
            .onReceive(viewModel.mapStoppedMovingSubject) { _ in
                if viewModel.hasActiveChipFilters {
                    refreshDiscoveryCache()
                }
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
            .onChange(of: viewModel.activeQuickFilters) { _, _ in
                discoveryResultsLimit = maxListResults
                searchResultsLimit = 20
                refreshDiscoveryCache()
                syncDisplayedSearchResultsToMap()
                refreshEmptyStateVisibility()
            }
            .onChange(of: viewModel.activeCategoryFilters) { _, _ in
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
            .onChange(of: viewModel.merchantStoreRevision) { _, _ in
                refreshDiscoveryCache()
            }
            .onAppear {
                if FeatureFlags.isEventsUIEnabled {
                    viewModel.ensureEventsLoaded()
                }
                viewModel.ensureAreasLoaded() // Keep community/area data warming in background during merchant browsing.
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
                } else if viewModel.hasActiveChipFilters && cachedFilteredBrowseCount == 0 {
                    quickFilterEmptyStateView
                } else if !viewModel.hasActiveChipFilters && elements.isEmpty {
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
        @Bindable var viewModel = viewModel
        return HStack(spacing: 8) {
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
                .strokeBorder(
                    BitLocalSheetSurface.borderColor(
                        for: .searchField,
                        colorScheme: colorScheme,
                        contrast: colorSchemeContrast
                    ),
                    lineWidth: 0.5
                )
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
        .background(
            BitLocalSheetSurface.fillColor(
                for: .control,
                colorScheme: colorScheme,
                contrast: colorSchemeContrast
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    BitLocalSheetSurface.borderColor(
                        for: .control,
                        colorScheme: colorScheme,
                        contrast: colorSchemeContrast
                    ),
                    lineWidth: 0.5
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var searchFieldSurfaceColor: Color {
        BitLocalSheetSurface.fillColor(
            for: .searchField,
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
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
                        .environment(viewModel)
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
                        title: String(localized: "Featured Nearby", comment: "Section header for boosted nearby merchants"),
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
                            title: String(localized: "More Nearby", comment: "Section header for additional nearby merchants"),
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
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: emptyStateSystemImage)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(emptyStateTitle)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(emptyStateMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)

                    if shouldShowEmptyStateRetry {
                        Button {
                            viewModel.refreshMerchantData(userInitiated: true)
                        } label: {
                            Text(String(localized: "Try Again", comment: "Retry button when merchant sync fails"))
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
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var quickFilterEmptyStateView: some View {
        GeometryReader { proxy in
            ScrollView {
                quickFilterEmptyStateContent
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var isOnlySavedFilterActive: Bool {
        viewModel.activeQuickFilters == [.saved] && viewModel.activeCategoryFilters.isEmpty
    }

    private var quickFilterEmptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: isOnlySavedFilterActive ? "bookmark.slash" : "line.3.horizontal.decrease.circle")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(quickFilterEmptyStateTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(quickFilterEmptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Button {
                BitLocalHaptics.selection()
                viewModel.clearMerchantChipFilters()
            } label: {
                Text(String(localized: "Clear Filters", comment: "Button to clear active merchant quick filters"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private var quickFilterEmptyStateTitle: String {
        if isOnlySavedFilterActive {
            return String(localized: "No saved places", comment: "Empty state title when Saved filter has no matching places")
        }
        return String(localized: "No matching places", comment: "Empty state title when quick filters yield zero matches")
    }

    private var quickFilterEmptyStateMessage: String {
        if isOnlySavedFilterActive {
            return String(localized:
                "Save places from any merchant detail page to find them quickly here.",
                comment: "Empty state message when Saved filter has no matching places"
            )
        }
        return String(localized:
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
            return String(localized: "Couldn't load merchants", comment: "Title when merchant dataset failed to load")
        }
        if viewModel.allElements.isEmpty {
            return String(localized: "Updating merchants…", comment: "Title while waiting for first merchant sync")
        }
        return String(localized: "no_locations_found", comment: "Empty state for no locations found")
    }

    private var emptyStateMessage: String {
        if let message = viewModel.merchantSyncStatusMessage, !message.isEmpty {
            return message
        }
        if viewModel.allElements.isEmpty {
            return String(localized:
                "BitLocal is downloading the latest Bitcoin merchants. Use Try Again if this takes too long, or refresh merchants in About.",
                comment: "Message while waiting for first merchant sync"
            )
        }
        return String(localized:
            "No Bitcoin merchants in this map area. Pan or zoom to explore nearby places.",
            comment: "Empty state when the viewport has no merchants but the catalog is loaded"
        )
    }

    private var shouldShowEmptyStateRetry: Bool {
        viewModel.merchantSyncFailed || (viewModel.hasLoadedInitialData && viewModel.allElements.isEmpty)
    }

    var lastSyncedFooterLine: String? {
        guard let relative = viewModel.lastSuccessfulSyncRelativeDescription else { return nil }
        return String(
            localized: "Updated \(relative)",
            comment: "Relative last-synced label, e.g. Updated 5 minutes ago"
        )
    }

    private var digestResultsView: some View {
        List {
            if let digest = viewModel.activeMerchantAlertDigest {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "New merchants in \(digest.cityDisplayName)", comment: "Digest header showing the city name"))
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
                        if viewModel.hasActiveChipFilters {
                            quickFilterEmptyStateContent
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
                                    title: String(localized: "Featured Nearby", comment: "Section header for boosted nearby search results"),
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
                                        title: String(localized: "More Nearby", comment: "Section header for additional nearby search results"),
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
}
