import SwiftUI
import Foundation
import MapKit
import Observation

struct CommunitiesListView: View {
    private let resultsPageSize = 15

    @Environment(ContentViewModel.self) private var viewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let metadataStore = CommunityRowMetadataObservableStore.shared
    var currentDetent: PresentationDetent? = nil
    @State private var filterText = ""
    @State private var communityResultsLimit = 15
    @FocusState private var isSearchFieldFocused: Bool

    private var isCollapsedSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detent == BottomSheetDetents.collapsed
    }

    var body: some View {
        let filtered = filteredCommunities
        let displayed = Array(filtered.prefix(communityResultsLimit))
        let hasMore = filtered.count > displayed.count

        VStack(spacing: 0) {
            searchBar
                .padding(.top, searchBarTopPadding)
                .padding(.bottom, 6)

            List {
                if viewModel.communityMapAreasIsLoading &&
                    viewModel.communityMapAreas.isEmpty &&
                    viewModel.areaBrowserAreas.isEmpty &&
                    filtered.isEmpty {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading communities…")
                                .foregroundStyle(.secondary)
                        }
                        .clearListRowBackground(if: shouldUseUnifiedSheetRows)
                    }
                    .clearListRowBackground(if: shouldUseUnifiedSheetRows)
                }

                Section {
                    if filtered.isEmpty {
                        Text(emptyStateMessage)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden, edges: .top)
                            .clearListRowBackground(if: shouldUseUnifiedSheetRows)
                    } else {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, area in
                            Button {
                                viewModel.selectCommunity(area, presentDetail: true)
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    CommunityRow(
                                        area: area,
                                        metadata: metadataStore.metadataByAreaID[area.id]
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.tactileRow)
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                            .clearListRowBackground(if: shouldUseUnifiedSheetRows)
                        }

                        if hasMore {
                            Button("Load more communities") {
                                communityResultsLimit += resultsPageSize
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.accent)
                            .clearListRowBackground(if: shouldUseUnifiedSheetRows)
                        }
                    }
                }
                .clearListRowBackground(if: shouldUseUnifiedSheetRows)
            }
            .listStyle(.plain)
            .scrollContentBackground(shouldUseUnifiedSheetRows ? .hidden : .automatic)
            .background(Color.clear)
            .sheetCollapsedReveal(
                geometry: viewModel.sheetGeometry,
                isCollapsedLike: isCollapsedSheet,
                forceRevealed: isSearchFieldFocused || !filterText.isEmpty
            )
        }
        .onAppear {
            // Returning from detail should always restore the visible-community browsing state,
            // but re-appearing while a detail route is still presented (e.g. closing Settings) must keep it.
            if viewModel.selectedCommunityArea != nil, viewModel.presentedCommunityArea == nil {
                viewModel.clearSelectedCommunity()
            }
            viewModel.ensureCommunityMapAreasLoaded()
        }
        .onChange(of: filterText) { _, _ in
            communityResultsLimit = resultsPageSize
        }
        .task(id: metadataPrewarmKey(for: displayed)) {
            await prewarmVisibleMetadata(for: displayed)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.primary.opacity(0.65))
                .font(.subheadline.weight(.medium))
            TextField(
                "",
                text: $filterText,
                prompt: Text("Search communities…").foregroundStyle(Color.primary.opacity(0.6))
            )
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
            if !filterText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    filterText = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .padding(.vertical, -11)
                .padding(.trailing, -8)
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

    private var shouldUseUnifiedSheetRows: Bool {
        guard currentDetent != nil else { return false }
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private var filteredCommunities: [V2AreaRecord] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.visibleCommunityListAreas }
        return viewModel.communityListAreas.filter { area in
            area.displayName.localizedStandardContains(q) ||
            (area.tags?["organization"]?.localizedStandardContains(q) ?? false) ||
            (area.tags?["continent"]?.localizedStandardContains(q) ?? false)
        }
    }

    private var emptyStateMessage: String {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty
            ? String(localized: "No communities in current map view", comment: "Empty state when no Bitcoin communities appear in the visible map area")
            : String(localized: "No communities found", comment: "Empty state when a community search returns no results")
    }

    private func metadataPrewarmKey(for areas: [V2AreaRecord]) -> String {
        let areaKey = areas
            .map { "\($0.id)|\($0.updatedAt ?? "")" }
            .joined(separator: ",")
        return areaKey
    }

    private func prewarmVisibleMetadata(for areas: [V2AreaRecord]) async {
        guard !areas.isEmpty else { return }

        let areasToResolve = areas.filter { area in
            metadataStore.metadataByAreaID[area.id]?.updatedAt != area.updatedAt
        }

        guard !areasToResolve.isEmpty else { return }

        let allElements = viewModel.allElements

        // Resolve all communities concurrently on background threads
        await withTaskGroup(of: CommunityRowMetadata?.self) { group in
            for area in areasToResolve {
                group.addTask(priority: .utility) {
                    await self.resolveMetadata(for: area, allElements: allElements)
                }
            }

            for await result in group {
                guard !Task.isCancelled, let result else { continue }
                metadataStore.metadataByAreaID[result.areaID] = result
            }
        }
    }

    private nonisolated func resolveMetadata(for area: V2AreaRecord, allElements: [Element]) async -> CommunityRowMetadata? {
        if let cached = await CommunityRowMetadataCache.shared.metadata(for: area.id, updatedAt: area.updatedAt) {
            return cached
        }

        guard let polygons = communityPolygons(for: area), !polygons.isEmpty else {
            let metadata = CommunityRowMetadata(
                areaID: area.id,
                updatedAt: area.updatedAt,
                merchantCount: nil,
                isResolved: true
            )
            await CommunityRowMetadataCache.shared.setMetadata(metadata)
            return metadata
        }

        // Compute bounding box for cheap pre-filtering
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        for polygon in polygons {
            for ring in polygon {
                for point in ring where point.count >= 2 {
                    minLon = min(minLon, point[0])
                    maxLon = max(maxLon, point[0])
                    minLat = min(minLat, point[1])
                    maxLat = max(maxLat, point[1])
                }
            }
        }

        let members = allElements.filter { element in
            guard let coordinate = element.mapCoordinate else { return false }
            // Fast bounding box rejection
            guard coordinate.latitude >= minLat, coordinate.latitude <= maxLat,
                  coordinate.longitude >= minLon, coordinate.longitude <= maxLon else {
                return false
            }
            return polygons.contains { polygon in
                coordinateInPolygon(latitude: coordinate.latitude, longitude: coordinate.longitude, rings: polygon)
            }
        }

        let merchantCount = members.count
        let metadata = CommunityRowMetadata(
            areaID: area.id,
            updatedAt: area.updatedAt,
            merchantCount: merchantCount,
            isResolved: true
        )

        await CommunityRowMetadataCache.shared.setMetadata(metadata)
        return metadata
    }

    private nonisolated func communityPolygons(for area: V2AreaRecord) -> [[[[Double]]]]? {
        guard let geoJSON = area.geoJSON else { return nil }

        var polygons: [[[[Double]]]] = []
        for feature in geoJSON.features {
            switch feature.geometry.coordinates {
            case .multiPolygon(let multipolygon):
                polygons.append(contentsOf: multipolygon)
            case .polygon(let polygon):
                polygons.append(polygon)
            }
        }

        return polygons.isEmpty ? nil : polygons
    }

    private nonisolated func coordinateInPolygon(latitude: Double, longitude: Double, rings: [[[Double]]]) -> Bool {
        guard let outerRing = rings.first,
              pointInRing(latitude: latitude, longitude: longitude, ring: outerRing) else {
            return false
        }

        for hole in rings.dropFirst() {
            if pointInRing(latitude: latitude, longitude: longitude, ring: hole) {
                return false
            }
        }

        return true
    }

    private nonisolated func pointInRing(latitude: Double, longitude: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }

        var inside = false
        var previousIndex = ring.count - 1

        for index in ring.indices {
            guard ring[index].count >= 2, ring[previousIndex].count >= 2 else {
                previousIndex = index
                continue
            }

            let currentLongitude = ring[index][0]
            let currentLatitude = ring[index][1]
            let previousLongitude = ring[previousIndex][0]
            let previousLatitude = ring[previousIndex][1]

            let intersects = ((currentLatitude > latitude) != (previousLatitude > latitude))
                && (longitude < (previousLongitude - currentLongitude) * (latitude - currentLatitude)
                    / ((previousLatitude - currentLatitude) == 0 ? 1e-12 : (previousLatitude - currentLatitude))
                    + currentLongitude)

            if intersects {
                inside.toggle()
            }

            previousIndex = index
        }

        return inside
    }
}

private struct CommunityRow: View {
    let area: V2AreaRecord
    let metadata: CommunityRowMetadata?

    var body: some View {
        HStack(spacing: 10) {
            communityIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(area.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            merchantCountBadge
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var communityIcon: some View {
        CommunityIconImage(url: iconURL, placeholderSystemName: "person.3.fill", scaleToFill: true)
            .frame(width: 32, height: 32)
            .background(Color.accentColor.opacity(0.10), in: .circle)
            .clipShape(.circle)
    }

    @ViewBuilder
    private var merchantCountBadge: some View {
        if let merchantCount = metadata?.merchantCount {
            HStack(spacing: 8) {
                Image(systemName: "storefront")
                    .font(.caption.weight(.semibold))

                Text("\(merchantCount)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: Capsule())
        } else if metadata?.isResolved == false || metadata == nil {
            PlaceholderCapsule(width: 44, height: 24)
        }
    }

    private var iconURL: URL? {
        guard let raw = area.tags?["icon:square"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }
}

struct CommunityRowMetadata: Codable, Sendable {
    let areaID: String
    let updatedAt: String?
    let merchantCount: Int?
    let isResolved: Bool
}

private struct PlaceholderCapsule: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ShimmerShape(shape: Capsule())
            .frame(width: width, height: height)
    }
}

private struct ShimmerShape<S: Shape>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shape: S
    private let duration: Double = 1.5

    var body: some View {
        if reduceMotion {
            shape
                .fill(Color.primary.opacity(0.08))
        } else {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: duration) / duration)
                let mapped = -0.8 + phase * 2.6  // maps 0…1 → -0.8…1.8

                shape
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.primary.opacity(0.14),
                                .clear
                            ],
                            startPoint: UnitPoint(x: mapped - 0.3, y: 0.3),
                            endPoint: UnitPoint(x: mapped + 0.3, y: 0.7)
                        )
                        .clipShape(shape)
                    }
            }
        }
    }
}

actor CommunityRowMetadataCache {
    static let shared = CommunityRowMetadataCache()

    private var storage: [String: CommunityRowMetadata] = [:]

    func metadata(for areaID: String, updatedAt: String?) -> CommunityRowMetadata? {
        guard let metadata = storage[areaID], metadata.updatedAt == updatedAt else { return nil }
        return metadata
    }

    func setMetadata(_ metadata: CommunityRowMetadata) {
        storage[metadata.areaID] = metadata
    }
}

@MainActor
@Observable
final class CommunityRowMetadataObservableStore {
    static let shared = CommunityRowMetadataObservableStore()

    var metadataByAreaID: [String: CommunityRowMetadata] = [:]
}
