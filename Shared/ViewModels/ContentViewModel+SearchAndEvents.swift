import SwiftUI
import Combine
import CoreLocation
import MapKit
import Foundation

extension ContentViewModel {
    // MARK: - Unified Search (forwarded to MerchantSearchController)

    func performUnifiedSearch() {
        merchantSearch.performUnifiedSearch()
    }

    func applyMerchantCategoryChip(_ chip: MerchantCategoryChip) {
        merchantSearch.applyMerchantCategoryChip(chip)
    }

    func clearMerchantSearch(userInitiated: Bool = true) {
        merchantSearch.clearMerchantSearch(userInitiated: userInitiated)
    }

    func restorePersistedMerchantCategoryIfNeeded() {
        merchantSearch.restorePersistedMerchantCategoryIfNeeded()
    }

    func handleMerchantSearchMapRegionChange() {
        merchantSearch.handleMerchantSearchMapRegionChange()
    }

    func setMerchantSearchMapResults(_ results: [Element]) {
        merchantSearch.setMerchantSearchMapResults(results)
    }

    func clearMerchantSearchMapResults() {
        merchantSearch.clearMerchantSearchMapResults()
    }

    func hydrateMerchantSearchPreviewIfNeeded(_ record: V4PlaceRecord) {
        merchantSearch.hydrateMerchantSearchPreviewIfNeeded(record)
    }

    func pruneTransientMerchantCachesIfNeeded(force: Bool = false) {
        let shouldPruneCellViewModels = force || cellViewModels.count > cellViewModelCacheLimit
        let shouldPruneSearchDocuments = force || merchantSearch.searchDocumentCacheNeedsPrune

        guard shouldPruneCellViewModels || shouldPruneSearchDocuments else { return }

        var retainedIDs: [String] = []
        retainedIDs.reserveCapacity(
            visibleElements.count +
            merchantSearchPrimaryResults.count +
            path.count +
            communityMemberElements.count + 1
        )

        func appendUnique(id: String?) {
            guard let id, !id.isEmpty, !retainedIDs.contains(id) else { return }
            retainedIDs.append(id)
        }

        visibleElements.forEach { appendUnique(id: $0.id) }
        merchantSearchPrimaryResults.forEach { appendUnique(id: $0.id) }
        path.forEach { appendUnique(id: $0.id) }
        communityMemberElements.prefix(100).forEach { appendUnique(id: $0.id) }
        appendUnique(id: selectedElement?.id)

        if shouldPruneCellViewModels {
            let keepIDs = Set(retainedIDs.prefix(cellViewModelCacheLimit))
            cellViewModels = cellViewModels.filter { keepIDs.contains($0.key) }
        }

        if shouldPruneSearchDocuments {
            let keepIDs = Set(retainedIDs.prefix(merchantSearch.merchantSearchDocumentCacheLimit))
            merchantSearch.pruneSearchDocumentCaches(keeping: keepIDs)
        }
    }

    /// Lazy-load events on first list appearance (no-op while events UI is disabled).
    func ensureEventsLoaded() {
        guard FeatureFlags.isEventsUIEnabled else { return }
        guard !hasLoadedEvents else { return }
        hasLoadedEvents = true
        loadBTCMapEvents()
    }

    /// Lazy-load areas on first list appearance (needed for search suggestions)
    func ensureAreasLoaded() {
        if areaBrowserIsLoading { return }
        if hasLoadedAreas && !areaBrowserAreas.isEmpty { return }
        hasLoadedAreas = true
        loadAreaBrowserAreas()
    }

    /// Loads the BTC Map v2 areas feed used by btcmap.org's communities map.
    func ensureCommunityMapAreasLoaded() {
        ensureAreasLoaded() // v3 fallback can render local communities immediately.
        if communityMapAreasIsLoading { return }
        let currentCommunityGeoJSON = communityMapAreas.count(where: { $0.isCommunity && !$0.isDeleted && $0.geoJSON != nil })
        if hasLoadedCommunityMapAreas && !communityMapAreas.isEmpty {
            if currentCommunityGeoJSON >= 100 { return }
        }
        hasLoadedCommunityMapAreas = true
        communityMapAreasIsLoading = true
        loadCommunityMapAreasV2()
    }

    var mapElementsForCurrentDisplay: [Element] {
        switch mapDisplayMode {
        case .merchants:
            if let digest = activeMerchantAlertDigest {
                return elementsForDisplay(merchantAlertElements(for: digest))
            }
            let trimmedQuery = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.count >= 2 {
                return elementsForDisplay(merchantSearchMapResults)
            }
            return elementsForDisplay(allElements)
        case .communities:
            return selectedCommunityArea == nil ? [] : elementsForDisplay(communityMemberElements)
        }
    }

    /// Cheap invalidation key for merchant annotations. MapView uses this to
    /// distinguish actual map-content changes from unrelated parent updates such
    /// as a sheet detent selection. Full element hashing remains the correctness
    /// check when this signature changes.
    var merchantMapAnnotationInputSignature: Int {
        var hasher = Hasher()
        hasher.combine(hideATMsFromMapAndList)

        if let digest = activeMerchantAlertDigest {
            hasher.combine(0)
            hasher.combine(digest)
            hasher.combine(merchantStoreRevision)
            return hasher.finalize()
        }

        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count >= 2 {
            hasher.combine(1)
            // Search result sets are small; their content-aware hash keeps same-ID
            // metadata changes correct without scanning the full merchant catalog.
            hasher.combine(merchantSearchMapResults.mapAnnotationsContentHash)
        } else {
            hasher.combine(2)
            hasher.combine(merchantStoreRevision)
        }
        return hasher.finalize()
    }

    var listElementsForCurrentDisplay: [Element] {
        if let digest = activeMerchantAlertDigest, mapDisplayMode == .merchants {
            return elementsForDisplay(merchantAlertElements(for: digest))
        }
        return visibleElements
    }

    /// Applies user display preferences (currently: optional ATM hiding).
    func elementsForDisplay(_ elements: [Element]) -> [Element] {
        guard hideATMsFromMapAndList else { return elements }
        return elements.filter { !$0.isATM }
    }

    func setHideATMsFromMapAndList(_ hide: Bool) {
        guard hideATMsFromMapAndList != hide else { return }
        hideATMsFromMapAndList = hide
        UserDefaults.standard.set(hide, forKey: Self.hideATMsFromMapAndListKey)

        if hide {
            visibleElements = visibleElements.filter { !$0.isATM }
            merchantSearch.removeATMsFromResults()
            communityMemberElements = communityMemberElements.filter { !$0.isATM }
        } else if !unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Re-run search so ATMs can reappear in results without a map pan.
            performUnifiedSearch()
        }

        forceMapRefresh = true
    }

    var isShowingMerchantAlertDigest: Bool {
        activeMerchantAlertDigest != nil
    }

    func activateMerchantAlertDigest(_ digest: CityDigest) {
        activeMerchantAlertDigest = digest
        mapDisplayMode = .merchants
        merchantSearch.resetForMerchantAlertDigest()
        selectedCommunityArea = nil
        presentedCommunityArea = nil
        communityMemberElements = []
        communityMemberElementIDs = []
        path = []
        deselectAnnotation()

        let elements = merchantAlertElements(for: digest)
        fitMapToMerchantAlertElements(elements, animated: true)

        let missingIDs = merchantAlertMissingIDs(for: digest)
        guard !missingIDs.isEmpty else { return }

        Debug.log("Merchant alert digest missing \(missingIDs.count) merchant(s) locally; refreshing merchant dataset")
        fetchElements { [weak self] in
            guard let self else { return }
            guard self.activeMerchantAlertDigest?.id == digest.id else { return }

            let refreshedElements = self.merchantAlertElements(for: digest)
            self.fitMapToMerchantAlertElements(refreshedElements, animated: true)
        }
    }

    func clearMerchantAlertDigest() {
        guard activeMerchantAlertDigest != nil else { return }
        activeMerchantAlertDigest = nil
        forceMapRefresh = true
    }

#if DEBUG
    func setAllElementsForTesting(_ elements: [Element]) {
        replaceMerchantCatalog(elements, forceMapRefresh: false)
    }
#endif

    var isShowingCommunityMembersOnMap: Bool {
        mapDisplayMode == .communities && selectedCommunityArea != nil
    }

    var communityListAreas: [V2AreaRecord] {
        let areas = effectiveCommunityAreasForDisplay
        let currentHash = areas.hashValue
        if let lastCommunityListAreasHash, lastCommunityListAreasHash == currentHash {
            return cachedCommunityListAreas
        }

        let sorted = areas.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        cachedCommunityListAreas = sorted
        lastCommunityListAreasHash = currentHash
        return sorted
    }

    var visibleCommunityListAreas: [V2AreaRecord] {
        let allAreas = communityListAreas
        guard mapDisplayMode == .communities,
              selectedCommunityArea == nil,
              let mapView = mapView else {
            return allAreas
        }

        let visibleRect = mapRect(for: mapView.bounds, in: mapView)
        let viewportBucketScale = 1_000.0
        let cacheKey = VisibleCommunityListCacheKey(
            areasHash: allAreas.hashValue,
            mapMode: mapDisplayMode,
            selectedCommunityID: selectedCommunityArea?.id,
            viewportMinXBucket: Int((visibleRect.minX / viewportBucketScale).rounded()),
            viewportMinYBucket: Int((visibleRect.minY / viewportBucketScale).rounded()),
            viewportMaxXBucket: Int((visibleRect.maxX / viewportBucketScale).rounded()),
            viewportMaxYBucket: Int((visibleRect.maxY / viewportBucketScale).rounded())
        )
        if lastVisibleCommunityListCacheKey == cacheKey {
            return cachedVisibleCommunityListAreas
        }

        var visibleIDs = Set<String>()

        for polygon in communityOverlays {
            let areaID = (polygon.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !areaID.isEmpty, polygon.boundingMapRect.intersects(visibleRect) else { continue }
            visibleIDs.insert(areaID)
        }

        let visibleAreas = allAreas.filter { visibleIDs.contains($0.id) }
        cachedVisibleCommunityListAreas = visibleAreas
        lastVisibleCommunityListCacheKey = cacheKey
        return visibleAreas
    }

    func communityArea(withID id: String) -> V2AreaRecord? {
        communityMapAreas.first { $0.id == id }
    }

    private func loadCommunityMapAreasV2() {
        let loader = CommunityAreasLoader(repository: btcMapRepository)
        loader.loadAll(initialAnchor: "2022-01-01T00:00:00.000Z") { [weak self] areas, isComplete, error in
            guard let self else { return }
            if let error {
                self.communityMapAreasIsLoading = false
                self.hasLoadedCommunityMapAreas = false
                Debug.logAPI("loadCommunityMapAreasV2 failed: \(error.localizedDescription)")
                return
            }

            // Publish progressively so visible communities can appear immediately.
            self.communityMapAreas = areas
            self.forceMapRefresh = true
            if isComplete {
                self.communityMapAreasIsLoading = false
            }
        }
    }

    // MARK: - BTCMap Events (v4)

    func clearEventsResults() {
        eventsResults = []
        eventsError = nil
        eventsIsLoading = false
    }

    func loadBTCMapEvents() {
        eventsIsLoading = true
        eventsError = nil

        let query = V4EventsQuery(includePast: eventsIncludePast, limit: 100)
        btcMapRepository.fetchEvents(query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.eventsIsLoading = false
                switch result {
                case .success(let events):
                    self.eventsResults = events.sorted { lhs, rhs in
                        let l = lhs.startsAt ?? lhs.updatedAt ?? ""
                        let r = rhs.startsAt ?? rhs.updatedAt ?? ""
                        return l < r
                    }
                case .failure(let error):
                    self.eventsResults = []
                    self.eventsError = error.localizedDescription
                }
            }
        }
    }

    func selectEvent(_ event: V4EventRecord) {
        guard let lat = event.lat, let lon = event.lon else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        updateMapRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05), animated: true)
    }
}
