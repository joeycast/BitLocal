import SwiftUI
import Combine
import CoreLocation
import MapKit
import Foundation

extension ContentViewModel {
    // MARK: - Community Map Mode

    var communityOverlays: [MKPolygon] {
        let areas = effectiveCommunityAreasForDisplay
        let currentHash = areas.hashValue
        if let cached = cachedCommunityOverlays, lastOverlayAreasHash == currentHash { return cached }

        let polygons = CommunityGeometryEngine.overlays(for: areas)
        cachedCommunityOverlays = polygons
        lastOverlayAreasHash = currentHash
        return polygons
    }

    var effectiveCommunityAreasForDisplay: [V2AreaRecord] {
        let v2Areas = communityMapAreas.filter { $0.isCommunity && !$0.isDeleted && $0.geoJSON != nil }
        let fallbackAreas = fallbackCommunityAreasFromV3()

        // While v2 is still loading, keep fallback communities visible and layer in v2 progressively.
        if communityMapAreasIsLoading {
            var merged = IdentifiableIndex.byID(fallbackAreas)
            for area in v2Areas { merged[area.id] = area }
            return Array(merged.values)
        }

        return v2Areas.isEmpty ? fallbackAreas : v2Areas
    }

    private func fallbackCommunityAreasFromV3() -> [V2AreaRecord] {
        areaBrowserAreas
            .filter { area in
                area.tags?["type"] == "community" &&
                area.geoJSON != nil
            }
            .map { area in
                V2AreaRecord(
                    id: String(area.id),
                    tags: area.tags,
                    createdAt: nil,
                    updatedAt: area.updatedAt,
                    deletedAt: nil,
                    geoJSON: area.geoJSON
                )
            }
    }

    func toggleMapMode() {
        let start = CFAbsoluteTimeGetCurrent()
        let switchingToCommunities = mapDisplayMode == .merchants
        Debug.log("⏱ toggleMapMode: START → switching to \(switchingToCommunities ? "communities" : "merchants")")

        // Reset community state only when the values actually differ from defaults,
        // avoiding unnecessary @Published emissions.
        if selectedCommunityArea != nil { selectedCommunityArea = nil }
        if !communityMemberElements.isEmpty { communityMemberElements = [] }
        if !communityMemberElementIDs.isEmpty { communityMemberElementIDs = [] }
        if communityMembersError != nil { communityMembersError = nil }
        if communityMembersIsLoading { communityMembersIsLoading = false }

        let afterReset = CFAbsoluteTimeGetCurrent()
        Debug.log("⏱ toggleMapMode: resets done in \(String(format: "%.1f", (afterReset - start) * 1000))ms")

        // Flip mode and refresh in a single pass.
        mapDisplayMode = switchingToCommunities ? .communities : .merchants
        forceMapRefresh = true

        let afterFlip = CFAbsoluteTimeGetCurrent()
        Debug.log("⏱ toggleMapMode: mode flipped in \(String(format: "%.1f", (afterFlip - afterReset) * 1000))ms")

        if switchingToCommunities {
            ensureCommunityMapAreasLoaded()
            Debug.log("⏱ toggleMapMode: ensureCommunityMapAreasLoaded in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - afterFlip) * 1000))ms")
        }

        Debug.log("⏱ toggleMapMode: TOTAL \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
    }

    func setMapDisplayMode(_ newMode: MapDisplayMode) {
        guard mapDisplayMode != newMode else { return }
        toggleMapMode()
    }

    /// Smoothly widens the map viewport so users in sparse areas can discover nearby merchants.
    func zoomOutMapToExploreNearby() {
        guard let mapView else { return }
        let current = mapView.region
        let nextLatDelta = min(max(current.span.latitudeDelta * 2.5, 0.25), 40.0)
        let nextLonDelta = min(max(current.span.longitudeDelta * 2.5, 0.25), 50.0)
        let expandedRegion = MKCoordinateRegion(
            center: current.center,
            span: MKCoordinateSpan(latitudeDelta: nextLatDelta, longitudeDelta: nextLonDelta)
        )
        mapView.setRegion(expandedRegion, animated: true)
    }

    func selectCommunity(_ area: V2AreaRecord, presentDetail: Bool = true) {
        ensureAreasLoaded()
        selectedCommunityArea = area
        if presentDetail {
            presentedCommunityArea = area
        }
        communityMembersError = nil
        communityMembersIsLoading = true
        communityMemberElements = []
        communityMemberElementIDs = []
        latestCommunitySelectionRequestID = UUID()
        let requestID = latestCommunitySelectionRequestID

        fitMapToCommunity(area, animated: true)

        // Match BTCMap community page behavior: derive members by polygon containment
        // against the synced v4 places dataset. Fall back to v3 area-elements only when
        // polygon data is unavailable.
        if let polygonMembers = communityMembersFromPolygon(for: area), !polygonMembers.isEmpty {
            communityMemberElements = polygonMembers
            communityMemberElementIDs = Set(polygonMembers.map(\.id))
            communityMembersError = nil
            let placeholderIDs = polygonMembers.compactMap { member -> String? in
                let name = member.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Element.isInvalidPrimaryName(name) ? member.id : nil
            }
            if placeholderIDs.isEmpty {
                communityMembersIsLoading = false
            } else {
                communityMembersIsLoading = true
                hydrateMissingCommunityMembers(
                    missingIDs: placeholderIDs,
                    seedMembers: polygonMembers,
                    requestID: requestID
                )
            }
            forceMapRefresh = true
            return
        }

        // V2 area IDs are slugs (e.g. "bitcoin-cordoba"); resolve the matching
        // V3 numeric ID via url_alias so we can query the area-elements endpoint.
        resolveV3AreaID(for: area) { [weak self] resolvedID in
            guard let self, let resolvedID else {
                Task { @MainActor [weak self] in
                    self?.communityMembersIsLoading = false
                    self?.communityMembersError = String(
                        localized: "Could not resolve community",
                        comment: "Error shown when a selected community area cannot be resolved to a BTC Map v3 ID"
                    )
                    self?.forceMapRefresh = true
                }
                return
            }
            self.fetchCommunityMembers(areaID: resolvedID, requestID: requestID)
        }
    }

    func showCommunityOnMap(_ area: V2AreaRecord) {
        selectedCommunityArea = area
        fitMapToCommunity(area, animated: true)
    }

    func fitMapToCommunity(_ area: V2AreaRecord, animated: Bool) {
        guard let mapView = mapView else {
            if let region = CommunityGeometryEngine.mapRegion(forCommunityArea: area) {
                updateMapRegion(center: region.center, span: region.span, animated: animated)
            }
            return
        }

        if let boundsRect = CommunityGeometryEngine.boundingMapRect(for: area) {
            var edgePadding = mapListViewportInsets(for: mapView)
            edgePadding.top += 12
            edgePadding.left += 20
            edgePadding.bottom += 20
            edgePadding.right += 20

            Task { @MainActor in
                mapView.setVisibleMapRect(boundsRect, edgePadding: edgePadding, animated: animated)
            }
            return
        }

        if let region = CommunityGeometryEngine.mapRegion(forCommunityArea: area) {
            updateMapRegion(center: region.center, span: region.span, animated: animated)
        }
    }

    private func communityMembersFromPolygon(for area: V2AreaRecord) -> [Element]? {
        guard let geoJSON = area.geoJSON else { return nil }
        let polygons = CommunityGeometryEngine.geoJSONPolygons(from: geoJSON)
        guard !polygons.isEmpty else { return nil }

        ensureMerchantSpatialIndex()

        let candidates: [MerchantSpatialIndex.Entry]
        if let box = MerchantPolygonGeometry.boundingBox(for: polygons) {
            candidates = merchantSpatialIndex.candidates(
                minLatitude: box.minLat,
                maxLatitude: box.maxLat,
                minLongitude: box.minLon,
                maxLongitude: box.maxLon
            )
        } else {
            // Degenerate geometry — fall back to scanning everything that has coordinates.
            candidates = allElements.compactMap { element in
                guard let coordinate = element.mapCoordinate else { return nil }
                return MerchantSpatialIndex.Entry(
                    id: element.id,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }

        let byID = Dictionary(allElements.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var members: [Element] = []
        members.reserveCapacity(min(candidates.count, 256))

        for candidate in candidates {
            guard polygons.contains(where: { polygon in
                CommunityGeometryEngine.coordinateInPolygon(
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    rings: polygon
                )
            }) else { continue }
            if let element = byID[candidate.id] {
                members.append(element)
            }
        }
        return members
    }

    func ensureMerchantSpatialIndex() {
        let signature = merchantStoreSignature(for: allElements)
        guard signature != merchantSpatialIndexSignature || merchantSpatialIndex.isEmpty else { return }
        let start = CFAbsoluteTimeGetCurrent()
        merchantSpatialIndex.rebuild(from: allElements, sourceSignature: signature)
        merchantSpatialIndexSignature = signature
        Debug.logTiming(
            "map",
            "merchant spatial index rebuilt entries=\(merchantSpatialIndex.entryCount) in \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000))ms"
        )
    }

    /// Sampled signature over id + coarse coordinates at several positions.
    /// Cheap enough for every membership query; catches wholesale replacements
    /// and sampled coordinate moves without hashing the full catalog.
    private func merchantStoreSignature(for elements: [Element]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        guard !elements.isEmpty else { return hasher.finalize() }

        let lastIndex = elements.count - 1
        let sampleIndexes: [Int] = [
            0,
            lastIndex / 4,
            lastIndex / 2,
            (3 * lastIndex) / 4,
            lastIndex
        ]
        var seen = Set<Int>()
        for index in sampleIndexes where seen.insert(index).inserted {
            let element = elements[index]
            hasher.combine(element.id)
            if let coordinate = element.mapCoordinate {
                // ~100m precision — enough to invalidate on real moves, cheap to hash.
                hasher.combine(Int((coordinate.latitude * 1_000).rounded()))
                hasher.combine(Int((coordinate.longitude * 1_000).rounded()))
            }
        }
        return hasher.finalize()
    }

    private func resolveV3AreaID(for area: V2AreaRecord, completion: @escaping @MainActor @Sendable (Int?) -> Void) {
        // If the V2 ID is already numeric, use it directly.
        if let parsed = Int(area.id) {
            completion(parsed)
            return
        }
        // The V3 url_alias lives inside tags, not the top-level urlAlias field.
        // Check already-loaded V3 areas for a tags["url_alias"] match.
        if let v3Match = areaBrowserAreas.first(where: { $0.tags?["url_alias"] == area.id }) {
            completion(v3Match.id)
            return
        }
        // V3 areas not loaded yet — fetch and search for a match.
        btcMapRepository.fetchV3Areas(updatedSince: "1970-01-01T00:00:00Z", limit: 10000) { result in
            Task { @MainActor in
                switch result {
                case .success(let areas):
                    let match = areas.first(where: { $0.tags?["url_alias"] == area.id })
                    completion(match?.id)
                case .failure:
                    completion(nil)
                }
            }
        }
    }

    private func fetchCommunityMembers(areaID: Int, requestID: UUID) {
        btcMapRepository.fetchV3AreaElements(areaID: areaID, updatedSince: "1970-01-01T00:00:00Z", limit: 10000) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.latestCommunitySelectionRequestID == requestID else { return }
                switch result {
                case .failure(let error):
                    self.communityMemberElements = []
                    self.communityMemberElementIDs = []
                    self.communityMembersError = error.localizedDescription
                    self.communityMembersIsLoading = false
                case .success(let rows):
                    let activeIDs = Set(rows.compactMap { row -> String? in
                        let isDeleted = !(row.deletedAt?.isEmpty ?? true)
                        guard !isDeleted else { return nil }
                        let trimmed = row.elementID.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    })
                    self.communityMemberElementIDs = activeIDs
                    self.communityMembersError = nil

                    let cachedMembers = self.allElements.filter { activeIDs.contains($0.id) }
                    let cachedIDs = Set(cachedMembers.map(\.id))
                    let missingIDs = activeIDs.subtracting(cachedIDs)
                    let placeholderIDs = cachedMembers.compactMap { member -> String? in
                        let name = member.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return Element.isInvalidPrimaryName(name) ? member.id : nil
                    }
                    let idsToHydrate = Set(missingIDs).union(placeholderIDs)

                    if idsToHydrate.isEmpty {
                        self.communityMemberElements = cachedMembers
                        self.communityMembersIsLoading = false
                    } else {
                        self.communityMemberElements = cachedMembers
                        self.communityMembersIsLoading = true
                        self.hydrateMissingCommunityMembers(
                            missingIDs: Array(idsToHydrate),
                            seedMembers: cachedMembers,
                            requestID: requestID
                        )
                    }
                }
                self.forceMapRefresh = true
            }
        }
    }

    private func hydrateMissingCommunityMembers(missingIDs: [String], seedMembers: [Element], requestID: UUID) {
        guard !missingIDs.isEmpty else {
            communityMembersIsLoading = false
            return
        }

        let repository = btcMapRepository
        let maxConcurrency = 8

        Task { [weak self] in
            let hydratedMembers: [Element] = await withTaskGroup(of: Element?.self) { group in
                var results: [Element] = []
                var iterator = missingIDs.makeIterator()

                for _ in 0..<maxConcurrency {
                    guard let id = iterator.next() else { break }
                    group.addTask {
                        guard let record = try? await repository.fetchPlace(id: id) else { return nil }
                        let mapped = V4PlaceToElementMapper.placeRecordToElement(record)
                        guard mapped.deletedAt?.isEmpty ?? true else { return nil }
                        return mapped
                    }
                }

                for await member in group {
                    if let member {
                        results.append(member)
                    }
                    if let id = iterator.next() {
                        group.addTask {
                            guard let record = try? await repository.fetchPlace(id: id) else { return nil }
                            let mapped = V4PlaceToElementMapper.placeRecordToElement(record)
                            guard mapped.deletedAt?.isEmpty ?? true else { return nil }
                            return mapped
                        }
                    }
                }

                return results
            }

            await MainActor.run {
                guard let self else { return }
                guard self.latestCommunitySelectionRequestID == requestID else { return }

                var byID = IdentifiableIndex.byID(seedMembers)
                for member in hydratedMembers {
                    byID[member.id] = member
                }
                self.communityMemberElements = Array(byID.values)

                if !hydratedMembers.isEmpty {
                    self.upsertMerchants(hydratedMembers, forceMapRefresh: false)
                }

                self.communityMembersIsLoading = false
                self.communityMembersError = nil
                self.forceMapRefresh = true
            }
        }
    }

    func clearSelectedCommunity() {
        selectedCommunityArea = nil
        communityMemberElements = []
        communityMemberElementIDs = []
        communityMembersIsLoading = false
        communityMembersError = nil
        forceMapRefresh = true
    }

    // MARK: - BTCMap Areas (v3 bridge)

    func loadAreaBrowserAreas() {
        areaBrowserIsLoading = true
        areaBrowserError = nil
        loadAreaBrowserAreasPaginated(anchor: "1970-01-01T00:00:00Z", page: 1, accumulated: [:])
    }

    private func loadAreaBrowserAreasPaginated(anchor: String, page: Int, accumulated: [Int: V3AreaRecord]) {
        let pageLimit = 5000
        let maxPages = 12
        btcMapRepository.fetchV3Areas(updatedSince: anchor, limit: pageLimit) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch result {
                case .failure(let error):
                    self.areaBrowserIsLoading = false
                    Debug.logAPI("loadAreaBrowserAreas failed (page \(page)): \(error.localizedDescription)")
                    self.areaBrowserAreas = []
                    self.areaBrowserError = error.localizedDescription

                case .success(let areas):
                    var merged = accumulated
                    for area in areas {
                        merged[area.id] = area
                    }

                    let nextAnchor = areas.compactMap(\.updatedAt).max()
                    let shouldContinue = areas.count >= pageLimit &&
                        page < maxPages &&
                        nextAnchor != nil &&
                        nextAnchor != anchor

                    if shouldContinue, let nextAnchor {
                        self.loadAreaBrowserAreasPaginated(anchor: nextAnchor, page: page + 1, accumulated: merged)
                        return
                    }

                    self.areaBrowserIsLoading = false
                    let finalAreas = Array(merged.values)
                    self.areaBrowserAreas = finalAreas
                        .filter { $0.bounds != nil || $0.geoJSON != nil }
                        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

                    self.hydrateMissingCommunityAreaGeoJSONIfNeeded()
                }
            }
        }
    }

    private func hydrateMissingCommunityAreaGeoJSONIfNeeded() {
        guard !communityGeoJSONHydrationInFlight else { return }

        let missingCommunityIDs = areaBrowserAreas
            .filter { $0.tags?["type"] == "community" && $0.geoJSON == nil }
            .map(\.id)
            .filter { !requestedCommunityAreaDetailIDs.contains($0) }

        guard !missingCommunityIDs.isEmpty else { return }

        communityGeoJSONHydrationInFlight = true
        let batchIDs = Array(missingCommunityIDs.prefix(100))
        batchIDs.forEach { requestedCommunityAreaDetailIDs.insert($0) }

        let repository = btcMapRepository
        let maxConcurrency = 8

        Task { [weak self] in
            let hydrated: [V3AreaRecord] = await withTaskGroup(of: V3AreaRecord?.self) { group in
                var results: [V3AreaRecord] = []
                var iterator = batchIDs.makeIterator()

                for _ in 0..<maxConcurrency {
                    guard let areaID = iterator.next() else { break }
                    group.addTask {
                        guard let area = try? await repository.fetchV3Area(id: areaID),
                              area.geoJSON != nil else {
                            return nil
                        }
                        return area
                    }
                }

                for await area in group {
                    if let area {
                        results.append(area)
                    }
                    if let areaID = iterator.next() {
                        group.addTask {
                            guard let area = try? await repository.fetchV3Area(id: areaID),
                                  area.geoJSON != nil else {
                                return nil
                            }
                            return area
                        }
                    }
                }

                return results
            }

            await MainActor.run {
                guard let self else { return }
                self.communityGeoJSONHydrationInFlight = false

                if !hydrated.isEmpty {
                    var byID = IdentifiableIndex.byID(self.areaBrowserAreas)
                    for area in hydrated {
                        byID[area.id] = area
                    }
                    self.areaBrowserAreas = Array(byID.values)
                        .filter { $0.bounds != nil || $0.geoJSON != nil }
                        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                    self.forceMapRefresh = true
                }

                // Continue in batches until we exhaust missing community polygons.
                self.hydrateMissingCommunityAreaGeoJSONIfNeeded()
            }
        }
    }

    func selectArea(_ area: V3AreaRecord) {
        selectedAreaID = area.id
        selectedAreaElementCount = nil

        if let region = CommunityGeometryEngine.mapRegion(for: area) {
            updateMapRegion(center: region.center, span: region.span, animated: true)
        }

        btcMapRepository.fetchV3AreaElements(areaID: area.id, updatedSince: "1970-01-01T00:00:00Z", limit: 5000) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let rows):
                    let activeCount = rows.count(where: { $0.deletedAt?.isEmpty ?? true })
                    self.selectedAreaElementCount = activeCount
                case .failure:
                    self.selectedAreaElementCount = nil
                }
            }
        }
    }

    func selectMerchantSearchResult(_ record: V4PlaceRecord, allowCameraMovement: Bool = true) {
        let fallbackElement = V4PlaceToElementMapper.placeRecordToElement(record)
        if let existing = allElements.first(where: { $0.id == fallbackElement.id }) {
            presentMerchantSearchSelection(existing, allowCameraMovement: allowCameraMovement)
            return
        }

        if record.lat != nil, record.lon != nil, merchantSearch.shouldHydrateSearchResult(record) {
            btcMapRepository.fetchPlace(id: record.idString) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let fullRecord):
                        let fullElement = V4PlaceToElementMapper.placeRecordToElement(fullRecord)
                        self.presentMerchantSearchSelection(
                            fullElement,
                            allowCameraMovement: allowCameraMovement
                        )
                    case .failure:
                        self.presentMerchantSearchSelection(
                            fallbackElement,
                            allowCameraMovement: allowCameraMovement
                        )
                    }
                }
            }
        } else {
            presentMerchantSearchSelection(fallbackElement, allowCameraMovement: allowCameraMovement)
        }
    }

    private func presentMerchantSearchSelection(_ element: Element, allowCameraMovement: Bool) {
        upsertElementIntoStore(element)

        setSelectionSource(.list)
        selectAnnotationForListSelection(
            element,
            animated: true,
            allowCameraMovement: allowCameraMovement
        )
        selectedElement = element
        path = [.place(element)]
    }

    func upsertElementIntoStore(_ element: Element) {
        replaceOrUpsertMerchant(element, forceMapRefresh: true)
    }
}
