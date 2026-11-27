import SwiftUI
import CoreLocation
import MapKit

extension BusinessesListView {
    // MARK: - Helpers

    var trimmedSearchQuery: String {
        viewModel.unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFilteringMerchants: Bool {
        !trimmedSearchQuery.isEmpty
    }

    var visibleCategoryChips: [MerchantCategoryChip] {
        cachedVisibleCategoryChips
    }

    var visibleQuickFilters: [MerchantQuickFilter] {
        MerchantQuickFilter.allCases.filter { filter in
            if filter == .saved {
                return !savedPlacesStore.savedIDs.isEmpty || viewModel.activeQuickFilters.contains(.saved)
            }
            return true
        }
    }

    var shouldShowFilterChips: Bool {
        guard viewModel.hasLoadedInitialData, !isShowingInitialLoadingState else { return false }
        guard viewModel.activeMerchantAlertDigest == nil else { return false }
        // Detent-based visibility; continuous fade is handled by sheetCollapsedReveal.
        return !isCollapsedSheet || showFocusedSearchCategoryChips || isFilteringMerchants
    }

    var shouldShowDiscoveryLoadingState: Bool {
        guard !isFilteringMerchants else { return false }
        guard viewModel.activeMerchantAlertDigest == nil else { return false }
        if viewModel.isLoading && elements.isEmpty && viewModel.allElements.isEmpty {
            return true
        }
        return viewModel.isLoading && containsPlaceholderMerchantNames(elements)
    }

    var isShowingInitialLoadingState: Bool {
        viewModel.isLoading && elements.isEmpty && !viewModel.hasLoadedInitialData
    }

    var searchStatusText: String? {
        if viewModel.merchantSearchIsWaitingForLocalDebounce {
            return NSLocalizedString("Searching nearby…", comment: "Status shown while nearby merchant search is in progress")
        }
        return nil
    }

    var noResultsText: String {
        NSLocalizedString("No locations match your search", comment: "Empty state for merchant search with no matches")
    }

    private var browseSourceElements: [Element] {
        if viewModel.activeQuickFilters.contains(.saved) {
            return viewModel.elementsForDisplay(viewModel.allElements)
        }
        return elements.map { viewModel.merchantElementStore.element(id: $0.id) ?? $0 }
    }

    private var totalDiscoveryCount: Int {
        viewModel.hasActiveChipFilters ? cachedFilteredBrowseCount : elements.count
    }

    private var filteredPrimarySearchResults: [Element] {
        viewModel.applyMerchantChipFilters(
            to: viewModel.merchantSearchPrimaryResults,
            calendar: calendar
        )
    }

    var displayedPrimaryResults: [Element] {
        let filtered = filteredPrimarySearchResults
        let limit = min(searchResultsLimit, filtered.count)
        return Array(filtered.prefix(limit))
    }

    var displayedFeaturedPrimaryResults: [Element] {
        displayedPrimaryResults.filter { $0.isCurrentlyBoosted() }
    }

    var displayedRegularPrimaryResults: [Element] {
        displayedPrimaryResults.filter { !$0.isCurrentlyBoosted() }
    }

    var hasMoreSearchResults: Bool {
        let totalCount = filteredPrimarySearchResults.count
        return totalCount > searchResultsLimit
    }

    var hasMoreDiscoveryResults: Bool {
        totalDiscoveryCount > topSortedElements.count
    }

    var categoryChipsView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(visibleQuickFilters) { filter in
                    let isSelected = viewModel.activeQuickFilters.contains(filter)
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
                                    .font(.caption.bold())
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
                    let isSelected = viewModel.activeCategoryFilters.contains(chip.group)
                    Button {
                        toggleCategoryChip(chip)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.symbolName)
                                .font(.caption.weight(.semibold))
                            Text(chip.localizedLabel)
                                .font(.footnote.weight(.medium))
                            if isSelected {
                                Image(systemName: "xmark")
                                    .font(.caption.bold())
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
        viewModel.toggleQuickFilter(filter)
    }

    private func toggleCategoryChip(_ chip: MerchantCategoryChip) {
        BitLocalHaptics.selection()
        viewModel.toggleCategoryFilter(chip.group)
    }

    func handlePendingIntentAction() {
        guard let action = intentRouter.pendingAction else { return }
        if case .openMerchants(let filter, let query) = action {
            _ = intentRouter.consumePendingAction()
            if viewModel.mapDisplayMode != .merchants {
                viewModel.setMapDisplayMode(.merchants)
            }
            if let filter {
                viewModel.activeQuickFilters = [filter]
            }
            if let query {
                viewModel.unifiedSearchText = query
            }
        }
    }

    func refreshDiscoveryCache() {
        let filteredBrowse = viewModel.applyMerchantChipFilters(
            to: browseSourceElements,
            calendar: calendar
        )
        cachedFilteredBrowseCount = filteredBrowse.count
        cachedTopSortedElements = nearestElements(filteredBrowse, limit: discoveryResultsLimit)
        cachedVisibleCategoryChips = MerchantChipFilterEngine.visibleCategoryChips(
            for: viewModel.unfilteredViewportElements,
            selectedCategories: viewModel.activeCategoryFilters,
            limit: 6
        )
    }

    private func containsPlaceholderMerchantNames(_ elements: [Element]) -> Bool {
        elements.contains { element in
            let rawName = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Element.isInvalidPrimaryName(rawName)
        }
    }

    func syncDisplayedSearchResultsToMap() {
        guard trimmedSearchQuery.count >= 2 else {
            viewModel.clearMerchantSearchMapResults()
            return
        }
        viewModel.setMerchantSearchMapResults(displayedPrimaryResults)
    }

    func keyboardAnimation(for notification: Notification) -> Animation {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        return .easeInOut(duration: duration)
    }

    func merchantSearchRow(
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

    func merchantRow(
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

    func handleUserLocationChange(_ newLocation: CLLocation?) {
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
        viewModel.cachedCellViewModel(for: element)
    }

    var footerView: some View {
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

            if !viewModel.hasActiveChipFilters && elements.count <= 3 && viewModel.activeMerchantAlertDigest == nil {
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

    func merchantSectionHeader(
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
    var shouldHideSheetBackground: Bool {
        guard let detent = currentDetent else { return false }
        if #available(iOS 26.0, *) {
            // Keep the List transparent at every detent (including `.large`) so
            // rows never render stark white over the system sheet's tinted surface.
            return true
        }
        return detent != .large
    }

    var shouldUseGlassyRows: Bool {
        guard currentDetent != nil else { return false }
        guard #available(iOS 26.0, *) else { return false }
        return true
    }

    var shouldShowEmptyState: Bool {
        guard viewModel.hasLoadedInitialData else { return false }
        guard canShowEmptyState else { return false }
        guard let detent = currentDetent else { return true }
        return detent != collapsedSheetDetent
    }

    var isCollapsedSheet: Bool {
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

    func refreshEmptyStateVisibility() {
        emptyStateDelayTask?.cancel()
        emptyStateDelayTask = nil

        let shouldDelayEmptyState = !isFilteringMerchants &&
            !viewModel.hasActiveChipFilters &&
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
            guard elements.isEmpty, !viewModel.hasActiveChipFilters else { return }
            guard !viewModel.isLoading else { return }
            canShowEmptyState = true
        }
    }
}
