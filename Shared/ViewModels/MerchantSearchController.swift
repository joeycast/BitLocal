//
//  MerchantSearchController.swift
//  bitlocal
//

import SwiftUI
import Combine
import CoreLocation
import MapKit

/// Map/catalog state the search controller reads from its owner. `ContentViewModel`
/// conforms directly; tests can supply a lightweight fake.
protocol MerchantSearchHost: AnyObject {
    var region: MKCoordinateRegion { get }
    var userLocation: CLLocation? { get }
    var visibleElements: [Element] { get }
    var mapDisplayMode: MapDisplayMode { get }
    var hasLoadedInitialData: Bool { get }
    var allElements: [Element] { get }
    func elementsForDisplay(_ elements: [Element]) -> [Element]
    func hydratePlaceholderNamesIfNeeded(in elements: [Element])
    func pruneTransientMerchantCachesIfNeeded(force: Bool)
    func upsertElementIntoStore(_ element: Element)
}

/// Owns merchant search state and orchestration (hybrid local search, legacy remote
/// search, result caches). Extracted from `ContentViewModel`, which forwards to it.
final class MerchantSearchController: ObservableObject {
    @Published var unifiedSearchText = ""
    @Published var isSearchActive = false
    @Published private(set) var localFilteredMerchants: [Element] = []
    @Published var selectedMerchantSearchScope: MerchantSearchScope = .onMap
    @Published private(set) var merchantSearchPrimaryResults: [Element] = []
    @Published private(set) var merchantSearchMapResults: [Element] = []
    @Published private(set) var merchantSearchFreshResults: [V4PlaceRecord] = []
    @Published private(set) var merchantSearchNormalizedQuery = ""
    @Published var searchMatchingAreas: [V3AreaRecord] = []
    // Remote merchant search
    @Published var merchantSearchResults: [V4PlaceRecord] = []
    @Published var merchantSearchIsLoading = false
    @Published private(set) var merchantSearchIsWaitingForLocalDebounce = false
    @Published var merchantSearchError: String?
    @Published var merchantSearchIsOfflineFallback = false
    @Published var merchantSearchRadiusKM: Double = 20
    @Published var merchantSearchProviderFilter = ""

    weak var host: MerchantSearchHost?

    private let btcMapRepository: BTCMapSearchServiceProtocol
    private var unifiedSearchDebounceTask: Task<Void, Never>?
    private var localMerchantSearchTask: Task<Void, Never>?
    private let unifiedSearchDebounceNanoseconds: UInt64
    private let unifiedSearchWorldwideDebounceNanoseconds: UInt64
    private let localSearchWorldwideDebounceNanoseconds: UInt64
    private var latestMerchantSearchRequestID = UUID()
    private var merchantSearchAnchorCenter: CLLocationCoordinate2D?
    private var merchantSearchAnchorQuery = ""
    private let merchantSearchRequeryDistanceMeters: CLLocationDistance = 5_000
    private var didRestorePersistedMerchantCategory = false
    private var merchantSearchDocumentByID: [String: MerchantSearchDocument] = [:]
    private var merchantSearchDocumentSignatureByID: [String: String] = [:]
    private var merchantSearchLocalMatchScoreByID: [String: Int] = [:]
    private var merchantSearchStrongLocalHitCount = 0
    private var merchantSearchPreviewHydrationInFlight = Set<String>()
    private var merchantSearchLoadingTimeoutTask: Task<Void, Never>?
    private let merchantSearchV2HybridFlagKey = "search_v2_hybrid"
    let merchantSearchDocumentCacheLimit = 1_200

    init(
        btcMapRepository: BTCMapSearchServiceProtocol,
        unifiedSearchDebounceNanoseconds: UInt64 = 400_000_000,
        unifiedSearchWorldwideDebounceNanoseconds: UInt64 = 700_000_000,
        localSearchWorldwideDebounceNanoseconds: UInt64 = 250_000_000
    ) {
        self.btcMapRepository = btcMapRepository
        self.unifiedSearchDebounceNanoseconds = unifiedSearchDebounceNanoseconds
        self.unifiedSearchWorldwideDebounceNanoseconds = unifiedSearchWorldwideDebounceNanoseconds
        self.localSearchWorldwideDebounceNanoseconds = localSearchWorldwideDebounceNanoseconds
    }

    // MARK: - Host state

    private var region: MKCoordinateRegion { host?.region ?? MKCoordinateRegion() }
    private var userLocation: CLLocation? { host?.userLocation }
    private var visibleElements: [Element] { host?.visibleElements ?? [] }
    private var mapDisplayMode: MapDisplayMode { host?.mapDisplayMode ?? .merchants }
    private var hasLoadedInitialData: Bool { host?.hasLoadedInitialData ?? false }
    private var allElements: [Element] { host?.allElements ?? [] }

    private func elementsForDisplay(_ elements: [Element]) -> [Element] {
        host?.elementsForDisplay(elements) ?? elements
    }

    private func hydratePlaceholderNamesIfNeeded(in elements: [Element]) {
        host?.hydratePlaceholderNamesIfNeeded(in: elements)
    }

    private func pruneTransientMerchantCachesIfNeeded(force: Bool = false) {
        host?.pruneTransientMerchantCachesIfNeeded(force: force)
    }

    private func upsertElementIntoStore(_ element: Element) {
        host?.upsertElementIntoStore(element)
    }

    // MARK: - Owner hooks

    var searchDocumentCacheNeedsPrune: Bool {
        merchantSearchDocumentByID.count > merchantSearchDocumentCacheLimit
    }

    /// Drops cached search documents/scores for ids outside `keepIDs`.
    func pruneSearchDocumentCaches(keeping keepIDs: Set<String>) {
        merchantSearchDocumentByID = merchantSearchDocumentByID.filter { keepIDs.contains($0.key) }
        merchantSearchDocumentSignatureByID = merchantSearchDocumentSignatureByID.filter { keepIDs.contains($0.key) }
        merchantSearchLocalMatchScoreByID = merchantSearchLocalMatchScoreByID.filter { keepIDs.contains($0.key) }
    }

    /// Called when the user turns on ATM hiding.
    func removeATMsFromResults() {
        localFilteredMerchants = localFilteredMerchants.filter { !$0.isATM }
        merchantSearchPrimaryResults = merchantSearchPrimaryResults.filter { !$0.isATM }
        merchantSearchMapResults = merchantSearchMapResults.filter { !$0.isATM }
    }

    /// Clears search so a merchant alert digest can take over the map and list.
    func resetForMerchantAlertDigest() {
        unifiedSearchText = ""
        isSearchActive = false
        localFilteredMerchants = []
        merchantSearchPrimaryResults = []
        merchantSearchMapResults = []
        merchantSearchFreshResults = []
        merchantSearchNormalizedQuery = ""
    }

    // MARK: - Unified Search

    func performUnifiedSearch() {
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            MerchantSearchPersistence.clear()
        } else if let group = ElementCategorySymbols.resolvedCategoryGroup(
            forNormalizedQuery: SearchTextNormalizer.normalize(query)
        ), group.localizedLabel.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            // Only persist exact category chip labels — never free-text.
            MerchantSearchPersistence.saveCategoryGroup(group)
        }
        if merchantSearchV2HybridEnabled {
            performUnifiedSearchHybrid(query: query)
        } else {
            performUnifiedSearchLegacyRemotePrimary(query: query)
        }
    }

    /// Applies a category chip and persists the selection for return visits.
    func applyMerchantCategoryChip(_ chip: MerchantCategoryChip) {
        isSearchActive = true
        MerchantSearchPersistence.saveCategoryGroup(chip.group)
        unifiedSearchText = chip.localizedLabel
        performUnifiedSearch()
    }

    /// Clears search text and forgets any persisted category chip.
    func clearMerchantSearch(userInitiated: Bool = true) {
        if userInitiated {
            MerchantSearchPersistence.clear()
        }
        // Setting isSearchActive = false re-enters this method via the
        // bottom sheet's onChange; skip the redundant second search pass.
        let wasCleared = unifiedSearchText.isEmpty && !isSearchActive
        unifiedSearchText = ""
        isSearchActive = false
        guard !wasCleared else { return }
        performUnifiedSearch()
    }

    /// Restores the last category chip once after initial merchant data is ready.
    /// Free-text is intentionally not restored (avoids surprise worldwide queries).
    ///
    /// When the current viewport has no matches, keep trying on later map/list
    /// updates (do not set `didRestore…`) so cold-start over empty ocean can
    /// still restore after the user pans into a populated area.
    func restorePersistedMerchantCategoryIfNeeded() {
        guard !didRestorePersistedMerchantCategory else { return }
        guard mapDisplayMode == .merchants else { return }
        guard hasLoadedInitialData, !allElements.isEmpty else { return }
        // Local search filters the viewport (visibleElements); restoring before
        // any pins are on screen guarantees an empty "no results" takeover on
        // cold launch. Wait until the map has settled somewhere with merchants.
        guard !visibleElements.isEmpty else { return }
        guard unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // User already typed or selected something — never auto-restore over it.
            didRestorePersistedMerchantCategory = true
            return
        }
        guard let group = MerchantSearchPersistence.loadCategoryGroup() else {
            // Nothing to restore (missing/expired) — stop rechecking.
            didRestorePersistedMerchantCategory = true
            return
        }
        // Only take over the sheet when the category actually has matches in
        // the current viewport. Leave the flag false so a later pan/zoom can retry.
        let hasVisibleMatch = visibleElements.contains {
            ElementCategorySymbols.merchantCategoryGroups(for: $0).contains(group)
        }
        guard hasVisibleMatch else {
            Debug.logAPI("Deferred category chip restore (\(group.rawValue)): no visible matches in viewport")
            return
        }
        didRestorePersistedMerchantCategory = true
        isSearchActive = true
        unifiedSearchText = group.localizedLabel
        performUnifiedSearch()
        Debug.logAPI("Restored persisted merchant category chip: \(group.rawValue)")
    }

    func refreshMerchantSearchFromVisibleElementsIfNeeded() {
        guard mapDisplayMode == .merchants else { return }
        guard merchantSearchV2HybridEnabled else { return }
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let normalizedQuery = SearchTextNormalizer.normalize(query)
        localFilteredMerchants = filteredMerchantElements(
            in: visibleElements,
            normalizedQuery: normalizedQuery
        )
        merchantSearchPrimaryResults = localFilteredMerchants
        pruneFreshResultsAgainstPrimary()
        hydratePlaceholderNamesIfNeeded(in: Array(localFilteredMerchants.prefix(20)))
    }

    private func filteredMerchantElements(
        in source: [Element],
        normalizedQuery: String
    ) -> [Element] {
        let result = MerchantSearchEngine.filterElements(
            source,
            normalizedQuery: normalizedQuery,
            documentProvider: { [weak self] element in
                self?.merchantSearchDocument(for: element) ?? MerchantSearchEngine.document(for: element)
            }
        )
        merchantSearchLocalMatchScoreByID = result.scoresByID
        merchantSearchStrongLocalHitCount = result.strongHitCount

        return elementsForDisplay(result.elements.sorted(by: merchantElementSearchSortOrder))
    }

    private func performUnifiedSearchHybrid(query: String) {
        localMerchantSearchTask?.cancel()

        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchNormalizedQuery = ""
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            searchMatchingAreas = []
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            pruneTransientMerchantCachesIfNeeded(force: true)
            return
        }

        guard query.count >= 2 else {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchNormalizedQuery = ""
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            merchantSearchIsWaitingForLocalDebounce = false
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            pruneTransientMerchantCachesIfNeeded(force: true)
            return
        }

        let normalizedQuery = SearchTextNormalizer.normalize(query)
        merchantSearchNormalizedQuery = normalizedQuery
        searchMatchingAreas = []
        scheduleLocalMerchantSearch(query: query, normalizedQuery: normalizedQuery)

        merchantSearchAnchorCenter = region.center
        merchantSearchAnchorQuery = query

        Debug.logAPI(
            "Merchant search queued (hybrid): query='\(query)', normalized='\(normalizedQuery)', scope=Nearby, local=\(localFilteredMerchants.count)"
        )
    }

    private func scheduleLocalMerchantSearch(query: String, normalizedQuery: String) {
        let source = visibleElements
        merchantSearchIsWaitingForLocalDebounce = true

        localMerchantSearchTask = Task { [weak self] in
            let debounceNanoseconds = self?.effectiveLocalMerchantSearchDebounceNanoseconds() ?? 0
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                self.merchantSearchIsWaitingForLocalDebounce = false
                let filtered = self.filteredMerchantElements(
                    in: source,
                    normalizedQuery: normalizedQuery
                )
                self.localFilteredMerchants = filtered
                self.merchantSearchPrimaryResults = filtered
                self.hydratePlaceholderNamesIfNeeded(in: Array(filtered.prefix(20)))
                self.pruneTransientMerchantCachesIfNeeded()
            }
        }
    }

    private func performUnifiedSearchLegacyRemotePrimary(query: String) {
        if query.isEmpty {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            searchMatchingAreas = []
            clearMerchantSearchResults()
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        guard query.count >= 2 else {
            localFilteredMerchants = []
            merchantSearchPrimaryResults = []
            merchantSearchFreshResults = []
            merchantSearchLocalMatchScoreByID = [:]
            merchantSearchStrongLocalHitCount = 0
            clearMerchantSearchResults()
            merchantSearchAnchorCenter = nil
            merchantSearchAnchorQuery = ""
            return
        }

        searchMatchingAreas = []

        unifiedSearchDebounceTask?.cancel()
        merchantSearchResults = []
        merchantSearchFreshResults = []
        merchantSearchError = nil
        merchantSearchIsOfflineFallback = false

        merchantSearchAnchorCenter = region.center
        merchantSearchAnchorQuery = query

        Debug.logAPI("Merchant search queued (legacy): query='\(query)', center=(\(region.center.latitude), \(region.center.longitude)), radiusKM=\(merchantSearchRadiusKM)")

        unifiedSearchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: unifiedSearchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                merchantSearchText = query
                performRemoteMerchantSearch()
            }
        }
    }

    private func localMerchantSearchSource(for scope: MerchantSearchScope) -> [Element] {
        switch scope {
        case .onMap:
            return visibleElements
        case .worldwide:
            return []
        }
    }

    private func merchantSearchDocument(for element: Element) -> MerchantSearchDocument {
        let signature = MerchantSearchEngine.documentSignature(for: element)
        if merchantSearchDocumentSignatureByID[element.id] == signature,
           let cached = merchantSearchDocumentByID[element.id] {
            return cached
        }

        let document = MerchantSearchEngine.document(for: element)
        merchantSearchDocumentSignatureByID[element.id] = signature
        merchantSearchDocumentByID[element.id] = document
        return document
    }

    private func merchantSearchDocument(for record: V4PlaceRecord) -> MerchantSearchDocument {
        MerchantSearchEngine.document(for: record)
    }

    private func pruneFreshResultsAgainstPrimary() {
        let primaryIDs = Set(merchantSearchPrimaryResults.map(\.id))
        merchantSearchFreshResults = merchantSearchFreshResults.filter { !primaryIDs.contains($0.idString) }
    }

    func handleMerchantSearchMapRegionChange() {
        guard mapDisplayMode == .merchants else { return }
        let query = unifiedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        guard merchantSearchAnchorQuery == query,
              let anchor = merchantSearchAnchorCenter else {
            merchantSearchAnchorCenter = region.center
            merchantSearchAnchorQuery = query
            return
        }

        let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let currentLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let distance = anchorLocation.distance(from: currentLocation)
        guard distance >= merchantSearchRequeryDistanceMeters else { return }
        performUnifiedSearch()
    }

    func setMerchantSearchMapResults(_ results: [Element]) {
        let filtered = elementsForDisplay(results)
        let currentIDs = merchantSearchMapResults.map(\.id)
        let newIDs = filtered.map(\.id)
        guard currentIDs != newIDs else { return }
        merchantSearchMapResults = filtered
    }

    func clearMerchantSearchMapResults() {
        guard !merchantSearchMapResults.isEmpty else { return }
        merchantSearchMapResults = []
    }

    /// Internal property for remote search text (synced from unifiedSearchText)
    private var merchantSearchText: String = ""

    func clearMerchantSearchResults() {
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchResults = []
        merchantSearchFreshResults = []
        merchantSearchError = nil
        merchantSearchIsLoading = false
        merchantSearchIsOfflineFallback = false
    }

    private var merchantSearchV2HybridEnabled: Bool {
        if UserDefaults.standard.object(forKey: merchantSearchV2HybridFlagKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: merchantSearchV2HybridFlagKey)
    }

    private func performRemoteMerchantSearch() {
        let trimmedName = merchantSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 3 else {
            merchantSearchLoadingTimeoutTask?.cancel()
            merchantSearchIsLoading = false
            merchantSearchFreshResults = []
            merchantSearchResults = []
            return
        }
        let normalizedQuery = merchantSearchNormalizedQuery.isEmpty
            ? SearchTextNormalizer.normalize(trimmedName)
            : merchantSearchNormalizedQuery
        let plans = merchantRemoteSearchPlans(query: trimmedName, normalizedQuery: normalizedQuery)

        guard !plans.isEmpty else {
            merchantSearchLoadingTimeoutTask?.cancel()
            merchantSearchIsLoading = false
            merchantSearchFreshResults = []
            merchantSearchResults = []
            merchantSearchError = nil
            merchantSearchIsOfflineFallback = false
            return
        }

        let requestID = UUID()
        latestMerchantSearchRequestID = requestID
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchIsLoading = true
        merchantSearchError = nil
        merchantSearchIsOfflineFallback = false
        scheduleMerchantSearchLoadingTimeout(for: requestID)

        Debug.logAPI(
            "Merchant remote search START: scope=\(selectedMerchantSearchScope.rawValue), query='\(trimmedName)', plans=\(plans.map(\.source).joined(separator: ","))"
        )

        let group = DispatchGroup()
        let aggregationQueue = DispatchQueue(label: "bitlocal.merchant-search.remote-aggregation")
        var mergedByID: [String: V4PlaceRecord] = [:]
        var errors: [String] = []
        var hadSuccess = false

        for plan in plans {
            group.enter()
            btcMapRepository.searchPlaces(query: plan.query) { [weak self] result in
                guard let self else {
                    group.leave()
                    return
                }

                switch result {
                case .success(let records):
                    let filtered = self.filterRemoteSearchRecords(records, normalizedQuery: normalizedQuery)
                    aggregationQueue.async {
                        hadSuccess = true
                        for record in filtered {
                            mergedByID[record.idString] = mergedByID[record.idString] ?? record
                        }
                        group.leave()
                    }

                case .failure(let error):
                    aggregationQueue.async {
                        errors.append(error.localizedDescription)
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            guard self.latestMerchantSearchRequestID == requestID else { return }

            if hadSuccess {
                let rankedRecords = self.filterRemoteSearchRecords(
                    Array(mergedByID.values),
                    normalizedQuery: normalizedQuery
                )
                self.applyRemoteEnrichment(
                    records: rankedRecords,
                    requestID: requestID,
                    source: plans.map(\.source).joined(separator: "+")
                )
            } else {
                self.merchantSearchResults = []
                self.merchantSearchFreshResults = []
                self.merchantSearchError = errors.first ?? NSLocalizedString("Search unavailable", comment: "Fallback error when remote merchant search fails")
                self.merchantSearchLoadingTimeoutTask?.cancel()
                self.merchantSearchIsLoading = false
                self.merchantSearchIsOfflineFallback = true
                Debug.logAPI("Merchant remote search FAILURE: \(self.merchantSearchError ?? "unknown"). Local primary results retained: \(self.merchantSearchPrimaryResults.count)")
            }
        }
    }

    private func merchantRemoteSearchPlans(
        query: String,
        normalizedQuery: String
    ) -> [MerchantRemoteSearchPlan] {
        let trimmedProvider = merchantSearchProviderFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerTagName: String? = {
            guard !trimmedProvider.isEmpty else { return nil }
            return trimmedProvider.contains(":") ? trimmedProvider : "payment:\(trimmedProvider)"
        }()

        var plans: [MerchantRemoteSearchPlan] = []
        var seenQueries = Set<V4SearchQuery>()

        func appendPlan(_ query: V4SearchQuery, source: String) {
            guard !query.isEmpty else { return }
            guard seenQueries.insert(query).inserted else { return }
            plans.append(MerchantRemoteSearchPlan(query: query, source: source))
        }

        switch selectedMerchantSearchScope {
        case .onMap:
            return []

        case .worldwide:
            appendPlan(
                V4SearchQuery(
                    name: query,
                    lat: nil,
                    lon: nil,
                    radiusKM: nil,
                    tagName: providerTagName,
                    tagValue: providerTagName == nil ? nil : "yes"
                ),
                source: "name-worldwide"
            )

            guard providerTagName == nil,
                  let resolvedGroup = ElementCategorySymbols.resolvedCategoryGroup(forNormalizedQuery: normalizedQuery),
                  let filter = ElementCategorySymbols.preferredRemoteTagFilters(
                    for: resolvedGroup,
                    matchingNormalizedQuery: normalizedQuery,
                    limit: 1
                  ).first else {
                return plans
            }

            appendPlan(
                V4SearchQuery(
                    name: nil,
                    lat: nil,
                    lon: nil,
                    radiusKM: nil,
                    tagName: filter.tagKey,
                    tagValue: filter.tagValue
                ),
                source: "\(resolvedGroup.rawValue)-worldwide-\(filter.tagKey)=\(filter.tagValue)"
            )
        }

        return plans
    }

    private func filterRemoteSearchRecords(
        _ records: [V4PlaceRecord],
        normalizedQuery: String
    ) -> [V4PlaceRecord] {
        MerchantSearchEngine.filterRecords(records, normalizedQuery: normalizedQuery)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return merchantRecordSearchSortOrder(lhs.record, rhs.record)
            }
            .map(\.record)
    }

    private func applyRemoteEnrichment(
        records: [V4PlaceRecord],
        requestID: UUID,
        source: String
    ) {
        guard latestMerchantSearchRequestID == requestID else { return }

        merchantSearchResults = records
        let primaryIDs = Set(merchantSearchPrimaryResults.map(\.id))
        merchantSearchFreshResults = records.filter { !primaryIDs.contains($0.idString) }
        merchantSearchError = nil
        merchantSearchLoadingTimeoutTask?.cancel()
        merchantSearchIsLoading = false
        merchantSearchIsOfflineFallback = false

        if !merchantSearchPrimaryResults.isEmpty && records.isEmpty {
            Debug.logAPI("Merchant search diagnostic local_hit_remote_miss: query='\(merchantSearchText)', local=\(merchantSearchPrimaryResults.count), source=\(source)")
        }

        Debug.logAPI("Merchant remote search SUCCESS (\(source)): remote=\(records.count), fresh=\(merchantSearchFreshResults.count), local=\(merchantSearchPrimaryResults.count)")
    }

    private func scheduleMerchantSearchLoadingTimeout(for requestID: UUID) {
        merchantSearchLoadingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.latestMerchantSearchRequestID == requestID else { return }
                guard self.merchantSearchIsLoading else { return }

                self.merchantSearchIsLoading = false
                self.merchantSearchError = self.merchantSearchError ?? NSLocalizedString("Search timed out", comment: "Error shown when merchant search takes too long")
                self.merchantSearchIsOfflineFallback = true
                Debug.logAPI("Merchant search timeout: requestID=\(requestID)")
            }
        }
    }

    private func remoteSearchGeometry(for scope: MerchantSearchScope) -> (lat: Double?, lon: Double?, radiusKM: Double?) {
        switch scope {
        case .onMap:
            return (region.center.latitude, region.center.longitude, merchantSearchRadiusKM)
        case .worldwide:
            return (nil, nil, nil)
        }
    }

    private func effectiveMerchantSearchDebounceNanoseconds() -> UInt64 {
        switch selectedMerchantSearchScope {
        case .onMap:
            return unifiedSearchDebounceNanoseconds
        case .worldwide:
            return unifiedSearchWorldwideDebounceNanoseconds
        }
    }

    private func effectiveLocalMerchantSearchDebounceNanoseconds() -> UInt64 {
        switch selectedMerchantSearchScope {
        case .onMap:
            return unifiedSearchDebounceNanoseconds
        case .worldwide:
            return localSearchWorldwideDebounceNanoseconds
        }
    }

    func hydrateMerchantSearchPreviewIfNeeded(_ record: V4PlaceRecord) {
        let id = record.idString
        guard shouldHydrateSearchResult(record) else { return }
        guard !merchantSearchPreviewHydrationInFlight.contains(id) else { return }
        merchantSearchPreviewHydrationInFlight.insert(id)

        btcMapRepository.fetchPlace(id: id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.merchantSearchPreviewHydrationInFlight.remove(id)
                guard case .success(let hydratedRecord) = result else { return }

                if let index = self.merchantSearchFreshResults.firstIndex(where: { $0.idString == id }) {
                    self.merchantSearchFreshResults[index] = hydratedRecord
                }
                if let index = self.merchantSearchResults.firstIndex(where: { $0.idString == id }) {
                    self.merchantSearchResults[index] = hydratedRecord
                }
                self.upsertElementIntoStore(V4PlaceToElementMapper.placeRecordToElement(hydratedRecord))
            }
        }
    }

    func shouldHydrateSearchResult(_ record: V4PlaceRecord) -> Bool {
        // Search may return partial fields; hydrate when key detail fields are absent.
        (record.description == nil && record.openingHours == nil) || (record.phone == nil && record.website == nil)
    }

    private func merchantElementSearchSortOrder(_ lhs: Element, _ rhs: Element) -> Bool {
        let lhsScore = merchantSearchLocalMatchScoreByID[lhs.id] ?? 0
        let rhsScore = merchantSearchLocalMatchScoreByID[rhs.id] ?? 0
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        let lhsBoosted = lhs.isCurrentlyBoosted()
        let rhsBoosted = rhs.isCurrentlyBoosted()
        if lhsBoosted != rhsBoosted {
            return lhsBoosted && !rhsBoosted
        }

        let lhsDistance = merchantSearchDistance(for: lhs)
        let rhsDistance = merchantSearchDistance(for: rhs)

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsName = normalizedMerchantName(lhs.displayName ?? "")
        let rhsName = normalizedMerchantName(rhs.displayName ?? "")
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id < rhs.id
    }

    private func merchantRecordSearchSortOrder(_ lhs: V4PlaceRecord, _ rhs: V4PlaceRecord) -> Bool {
        let lhsBoosted = lhs.isCurrentlyBoosted()
        let rhsBoosted = rhs.isCurrentlyBoosted()
        if lhsBoosted != rhsBoosted {
            return lhsBoosted && !rhsBoosted
        }

        let lhsDistance = merchantSearchDistance(for: lhs)
        let rhsDistance = merchantSearchDistance(for: rhs)

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsName = normalizedMerchantName(lhs.displayName)
        let rhsName = normalizedMerchantName(rhs.displayName)
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return lhs.id < rhs.id
    }

    private func merchantSearchDistance(for element: Element) -> CLLocationDistance {
        guard let coordinate = element.mapCoordinate else { return .greatestFiniteMagnitude }
        return merchantSearchDistance(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func merchantSearchDistance(for record: V4PlaceRecord) -> CLLocationDistance {
        guard let lat = record.lat, let lon = record.lon else { return .greatestFiniteMagnitude }
        return merchantSearchDistance(latitude: lat, longitude: lon)
    }

    private func merchantSearchDistance(latitude: Double, longitude: Double) -> CLLocationDistance {
        let target = CLLocation(latitude: latitude, longitude: longitude)

        if let user = userLocation {
            return user.distance(from: target)
        }

        let mapCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return mapCenter.distance(from: target)
    }

    private func normalizedMerchantName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
