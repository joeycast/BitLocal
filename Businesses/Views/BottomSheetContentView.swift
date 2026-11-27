//
//  BottomSheetContentView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import Foundation // for Debug logging
import UIKit
import CryptoKit
import MapKit
import Observation

struct BottomSheetContentView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @Environment(FeatureHintsController.self) private var featureHintsController
    @Environment(\.colorScheme) private var colorScheme

    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent
    var preferredLeadingWidth: CGFloat? = nil

    private var glassContrastScrimOpacity: Double {
        if currentDetent == .large {
            return 0
        }
        return colorScheme == .dark ? 0.18 : 0.28
    }

    var body: some View {
        navigationStack
            .background {
                // Softens saturated map blues/greens behind translucent Liquid Glass
                // sheets so body and secondary text stay legible (≥4.5:1 contrast).
                Color(.systemBackground)
                    .opacity(glassContrastScrimOpacity)
                    .ignoresSafeArea()
            }
            .ignoresSafeArea(edges: .bottom)
            // UIKit reader reports screen-bottom → sheet-top using the presentation
            // frame (not NavigationStack layout height), so map buttons clear the card,
            // and applies preferredLeadingWidth directly to UISheetPresentationController.
            .background {
                SheetEdgeHeightReader(
                    preferredLeadingWidth: preferredLeadingWidth,
                    onHeightChange: { height in
                        viewModel.reportSheetHeight(height)
                    },
                    onMotionSettled: { height in
                        viewModel.reportSheetMotionSettled(height)
                    }
                )
            }
            .onAppear {
                featureHintsController.markMainUIVisible()
            }
            .onChange(of: viewModel.unifiedSearchText) { _, _ in
                guard viewModel.mapDisplayMode != .communities else { return }
                viewModel.performUnifiedSearch()
            }
            .onChange(of: viewModel.isSearchActive) { _, isActive in
                guard viewModel.mapDisplayMode != .communities else { return }
                if !isActive {
                    // Clearing search dismisses any persisted category chip.
                    viewModel.clearMerchantSearch(userInitiated: true)
                }
            }
            .onChange(of: viewModel.path) { _, newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if let activeElement = newPath.last?.element {
                    _ = viewModel.consumeSelectionSource()
                    viewModel.selectedElement = activeElement
                } else {
                    viewModel.deselectAnnotation()
                }
            }
    }

    private var navigationStack: some View {
        NavigationStack(path: $viewModel.path) {
            sheetRootContentWithSafeAreaBehavior
                .modifier(RootSheetNavigationBarModifier())
                .disableVerticalToolbarIfAvailable()
                .navigationDestination(for: BitLocalNavigationRoute.self) { route in
                    switch route {
                    case .place(let element):
                        businessDetailDestination(for: element)
                    case .placeComments(let element):
                        BTCMapPlaceCommentsListView(element: element)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .disableVerticalToolbarIfAvailable()
                    case .allEvents:
                        AllEventsListView()
                            .environmentObject(viewModel)
                            .clearNavigationContainerBackgroundIfAvailable()
                            .disableVerticalToolbarIfAvailable()
                    }
                }
                .navigationDestination(item: $viewModel.presentedCommunityArea) { area in
                    CommunityDetailView(
                        area: area,
                        currentDetent: currentDetentBinding
                    )
                    .id(area.id)
                    .environmentObject(viewModel)
                    .clearNavigationContainerBackgroundIfAvailable()
                    .disableVerticalToolbarIfAvailable()
                }
                .clearNavigationContainerBackgroundIfAvailable()
        }
        .disableVerticalToolbarIfAvailable()
    }

    @ViewBuilder
    private var sheetRootContentWithSafeAreaBehavior: some View {
        if #available(iOS 26.0, *) {
            sheetRootContent
                .ignoresSafeArea(.container, edges: .top)
        } else {
            sheetRootContent
        }
    }

    @ViewBuilder
    private var sheetRootContent: some View {
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView(currentDetent: currentDetent)
                .environmentObject(viewModel)
        } else {
            BusinessesListView(
                elements: visibleElements,
                currentDetent: currentDetentBinding
            )
            .environmentObject(viewModel)
        }
    }

    private func businessDetailDestination(for element: Element) -> some View {
        BusinessDetailView(
            element: element,
            userLocation: viewModel.userLocation,
            contentViewModel: viewModel,
            currentDetent: currentDetentBinding
        )
        .id(element.id)
        .clearNavigationContainerBackgroundIfAvailable()
        .disableVerticalToolbarIfAvailable()
    }

    private var currentDetentBinding: Binding<PresentationDetent?> {
        Binding(
            get: { currentDetent },
            set: { newValue in
                if let newValue {
                    currentDetent = newValue
                }
            }
        )
    }
}

private struct RootSheetNavigationBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbarVisibility(.visible, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
        } else {
            content
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

/// Clear labeled mode switcher (`Merchants | Communities`) embedded inside the
/// sheet/sidebar header so users never have to guess what an icon-only button does.
struct SheetMapModeSwitcher: View {
    @ObservedObject var viewModel: ContentViewModel

    private var selectionBinding: Binding<MapDisplayMode> {
        Binding(
            get: { viewModel.mapDisplayMode },
            set: { newMode in
                viewModel.setMapDisplayMode(newMode)
            }
        )
    }

    var body: some View {
        Picker("Map display mode", selection: selectionBinding) {
            Text(NSLocalizedString("Merchants", comment: "Segmented control option for Bitcoin merchants"))
                .tag(MapDisplayMode.merchants)
            Text(NSLocalizedString("Communities", comment: "Segmented control option for Bitcoin communities"))
                .tag(MapDisplayMode.communities)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .featureHintAnchor(.communityToggle)
    }
}

struct CommunitiesListView: View {
    private let resultsPageSize = 15

    @EnvironmentObject private var viewModel: ContentViewModel
    @Environment(\.colorScheme) private var colorScheme
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

            if !isSearchFieldFocused && filterText.isEmpty {
                SheetMapModeSwitcher(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .sheetCollapsedReveal(
                        geometry: viewModel.sheetGeometry,
                        isCollapsedLike: isCollapsedSheet
                    )
            }

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
            // Returning from detail should always restore the visible-community browsing state.
            if viewModel.selectedCommunityArea != nil {
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
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
    }

    private var searchFieldSurfaceColor: Color {
        guard shouldUseUnifiedSheetRows else {
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
        return q.isEmpty ? "No communities in current map view" : "No communities found"
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

private struct CommunityRowMetadata: Codable, Sendable {
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

private actor CommunityRowMetadataCache {
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
private final class CommunityRowMetadataObservableStore {
    static let shared = CommunityRowMetadataObservableStore()

    var metadataByAreaID: [String: CommunityRowMetadata] = [:]
}

struct CommunityDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var viewModel: ContentViewModel
    private let metadataStore = CommunityRowMetadataObservableStore.shared
    let area: V2AreaRecord
    @Binding private var currentDetent: PresentationDetent?
    @AppStorage("community.lastLightningWalletID") private var lastLightningWalletID: String = ""
    @State private var isHeroScrolledPast = false
    @State private var showLightningAlert = false
    @State private var showWalletAlert = false
    @State private var showTipsDisclaimerAlert = false
    @State private var shareItem: ShareTextItem?
    @State private var linkOpenErrorItem: CommunityLinkOpenError?
    @State private var lightningErrorMessage: String?
    @State private var memberElements: [Element] = []

    init(area: V2AreaRecord, currentDetent: Binding<PresentationDetent?> = .constant(nil)) {
        self.area = area
        self._currentDetent = currentDetent
    }

    var body: some View {
        detailWithTipAlerts
            .sheet(item: $shareItem) { item in
                ActivityView(items: item.items)
            }
            .alert("Unable to Open Wallet", isPresented: Binding(
                get: { lightningErrorMessage != nil },
                set: { newValue in
                    if !newValue { lightningErrorMessage = nil }
                })
            ) {
            } message: {
                Text(lightningErrorMessage ?? "")
            }
            .alert("Unable to Open", isPresented: Binding(
                get: { linkOpenErrorItem != nil },
                set: { newValue in
                    if !newValue { linkOpenErrorItem = nil }
                })
            ) {
                if let copyValue = linkOpenErrorItem?.copyValue {
                    Button(String(format: NSLocalizedString("Copy %@", comment: "Button title to copy a value label"), "npub")) {
                        UIPasteboard.general.string = copyValue
                        BitLocalHaptics.success()
                    }
                }
                Button("OK") {}
            } message: {
                Text(linkOpenErrorItem?.message ?? "")
            }
    }

    private var detailWithTipAlerts: some View {
        detailWithChromeAndLifecycle
            .alert("Tip This Community", isPresented: $showLightningAlert) {
                if let lastWallet = knownWallets.first(where: { $0.id == lastLightningWalletID }),
                   let payload = payableLightningPayload {
                    Button(String(format: NSLocalizedString("Copy and Open %@", comment: "Button title to copy a value and open the selected wallet"), lastWallet.name)) {
                        openWallet(lastWallet, payload: payload)
                    }
                }
                Button("Choose Wallet") {
                    showWalletAlert = true
                }
                if let payload = payableLightningPayload {
                    Button("Copy Lightning Address") {
                        UIPasteboard.general.string = payload
                        BitLocalHaptics.success()
                    }
                    Button("Share") {
                        shareItem = ShareTextItem(text: payload)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a wallet or copy the Lightning address to tip this community.")
            }
            .alert("Choose Wallet", isPresented: $showWalletAlert) {
                if let payload = payableLightningPayload {
                    ForEach(walletsForPicker) { wallet in
                        Button(wallet.name) {
                            openWallet(wallet, payload: payload)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose your Lightning wallet. BitLocal will copy the Lightning address, then open the wallet.")
            }
            .alert("Tipping Disclaimer", isPresented: $showTipsDisclaimerAlert) {
            } message: {
                Text("BitLocal does not process, custody, or guarantee tip transactions. We only open your selected wallet or link and help copy/share the Lightning address.")
            }
    }

    private var detailWithChromeAndLifecycle: some View {
        scrollContent
            // Only observes live height while collapsed-like; expanded detail is free of drag churn.
            .sheetCollapsedReveal(
                geometry: viewModel.sheetGeometry,
                isCollapsedLike: isCollapsedLikeDetent
            )
            .navigationTitle((isHeroScrolledPast || isCollapsedLikeDetent) ? area.displayName : "")
            .navigationBarTitleDisplayMode(.inline)
            .bitLocalDetailNavigationChrome()
            .toolbar {
                if isHeroScrolledPast, let shareableURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            BitLocalHaptics.lightTap()
                            shareItem = ShareTextItem(items: [area.displayName, shareableURL])
                        } label: {
                            Label("Share community", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task(id: area.id) {
                if viewModel.selectedCommunityArea?.id != area.id || viewModel.communityMemberElements.isEmpty {
                    viewModel.selectCommunity(area, presentDetail: false)
                }
                updateMemberElements()
            }
            .onChange(of: area.id) { _, _ in
                updateMemberElements()
            }
            .onChange(of: viewModel.selectedCommunityArea?.id) { _, _ in
                updateMemberElements()
            }
            .onChange(of: viewModel.communityMemberElements) { _, _ in
                updateMemberElements()
            }
            .onAppear {
                updateMemberElements()
            }
    }

    private var scrollContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader(scrollProxy: scrollProxy)

                    quickActionBar

                    detailsSurface

                    if let descriptionText {
                        descriptionSection(descriptionText)
                    }

                    if let payload = payableLightningPayload {
                        tippingSection(payload: payload)
                    } else if let tipFallbackURL {
                        tipFallbackSection(url: tipFallbackURL)
                    }

                    merchantsSection

                    verificationSection
                        .id("community-verification-section")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 56
            } action: { _, scrolledPast in
                guard isHeroScrolledPast != scrolledPast else { return }
                withAnimation(BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)) {
                    isHeroScrolledPast = scrolledPast
                }
            }
        }
    }

    // MARK: - Hero Header & Quick Actions

    @ViewBuilder
    private func heroHeader(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                communityHeroIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(area.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metadataLine = heroMetadataLine {
                        Text(metadataLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Quiet inline verification status (tappable to jump to verification section)
            Button {
                BitLocalHaptics.selection()
                withAnimation(BitLocalMotion.animation(BitLocalMotion.disclosureSpring, reduceMotion: reduceMotion)) {
                    scrollProxy.scrollTo("community-verification-section", anchor: .center)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: heroVerificationIcon)
                        .font(.caption.weight(.semibold))
                    Text(heroVerificationTitle)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(heroVerificationTint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .padding(.vertical, -8)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var communityHeroIcon: some View {
        if let communityIconURL {
            CommunityIconImage(url: communityIconURL, placeholderSystemName: "person.3.fill", scaleToFill: true)
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.3.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color("MarkerColor"), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                }
                .accessibilityHidden(true)
        }
    }

    private var resolvedMerchantCount: Int? {
        if sameSelectedCommunity && !viewModel.communityMembersIsLoading {
            return memberElements.count
        }
        if !memberElements.isEmpty {
            return memberElements.count
        }
        return metadataStore.metadataByAreaID[area.id]?.merchantCount
    }

    private var heroMetadataLine: String? {
        guard let count = resolvedMerchantCount else { return nil }
        return String(localized: "^[\(count) merchant](inflect: true)")
    }

    private var heroVerificationIcon: String {
        verificationStatus?.icon ?? "questionmark.circle"
    }

    private var heroVerificationTitle: String {
        verificationStatus?.title ?? "Unverified"
    }

    private var heroVerificationTint: Color {
        verificationStatus?.tint ?? .secondary
    }

    @ViewBuilder
    private var quickActionBar: some View {
        let hasTip = hasTipAction
        let websiteURL = primaryWebsiteURL
        let shareURL = shareableURL
        if hasTip || websiteURL != nil || shareURL != nil {
            HStack(spacing: 8) {
                if hasTip {
                    quickActionButton(
                        title: LocalizedStringKey("Tip"),
                        systemImage: "bolt.fill",
                        isPrimary: true
                    ) {
                        BitLocalHaptics.lightTap()
                        if payableLightningPayload != nil {
                            showLightningAlert = true
                        } else if let tipFallbackURL {
                            openURL(tipFallbackURL)
                        }
                    }

                    if let websiteURL {
                        quickActionButton(
                            title: LocalizedStringKey("Website"),
                            systemImage: "safari.fill",
                            isPrimary: false
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(websiteURL)
                        }
                    }
                } else if let websiteURL {
                    quickActionButton(
                        title: LocalizedStringKey("Website"),
                        systemImage: "safari.fill",
                        isPrimary: true
                    ) {
                        BitLocalHaptics.lightTap()
                        openURL(websiteURL)
                    }
                }

                if let shareURL {
                    quickActionButton(
                        title: LocalizedStringKey("Share"),
                        systemImage: "square.and.arrow.up",
                        isPrimary: false
                    ) {
                        BitLocalHaptics.lightTap()
                        shareItem = ShareTextItem(items: [area.displayName, shareURL])
                    }
                }
            }
        }
    }

    private func quickActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isPrimary ? Color.clear : Color(.separator).opacity(0.35),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.tactilePress(scale: 0.96))
    }

    // MARK: - Consolidated Details & Socials Surface

    @ViewBuilder
    private var detailsSurface: some View {
        let contacts = contactInformationLinks
        let socials = socialLinks
        if !contacts.isEmpty || !socials.isEmpty {
            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(contacts.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            detailsRowDivider
                        }
                        communityContactRow(item)
                    }

                    if !socials.isEmpty {
                        if !contacts.isEmpty {
                            detailsRowDivider
                        }
                        communitySocialsRow(socials)
                    }
                }
            }
        }
    }

    private var detailsRowDivider: some View {
        Divider()
            .padding(.leading, 32)
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private func communityContactRow(_ item: CommunitySocialLink) -> some View {
        let copyTitle = String(
            format: NSLocalizedString("Copy %@", comment: "Context menu title to copy a labeled value"),
            item.label
        )
        HStack(alignment: .center, spacing: 4) {
            if item.isInteractive {
                Button {
                    BitLocalHaptics.lightTap()
                    openCommunityLink(item)
                } label: {
                    contactRowLabel(item)
                }
                .buttonStyle(.tactileRow(cornerRadius: 10))
                .copyValueContextMenu(item.value, title: copyTitle)
            } else {
                contactRowLabel(item)
                    .copyValueContextMenu(item.value, title: copyTitle)
            }

            if !item.value.isEmpty {
                TactileCopyButton(value: item.value, accessibilityLabel: copyTitle)
            }
        }
    }

    private func contactRowLabel(_ item: CommunitySocialLink) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func communitySocialsRow(_ socials: [CommunitySocialLink]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "at")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Socials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                BitLocalFlowLayout(horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(socials) { social in
                        communitySocialLink(social)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func communitySocialLink(_ social: CommunitySocialLink) -> some View {
        let copyTitle = String(
            format: NSLocalizedString("Copy %@", comment: "Context menu title to copy a labeled value"),
            social.label
        )
        let content = HStack(spacing: 5) {
            Image(systemName: social.icon)
                .font(.caption.weight(.semibold))
            Text(social.label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(social.isInteractive ? Color.accentColor : Color.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if social.isInteractive {
            Button {
                BitLocalHaptics.lightTap()
                openCommunityLink(social)
            } label: {
                content
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .copyValueContextMenu(social.value, title: copyTitle)
        } else {
            content
                .copyValueContextMenu(social.value, title: copyTitle)
        }
    }

    // MARK: - Description Section

    private var descriptionText: String? {
        guard let raw = area.tags?["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tipping Section

    private func tippingSection(payload: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tips")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 6)) {
                HStack(alignment: .center, spacing: 0) {
                    Button {
                        BitLocalHaptics.lightTap()
                        showLightningAlert = true
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tip This Community")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(payload)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactileRow(cornerRadius: 10))
                    .copyValueContextMenu(payload, title: "Copy Lightning Address")

                    Button {
                        BitLocalHaptics.selection()
                        showTipsDisclaimerAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactilePress(scale: 0.92))
                    .accessibilityLabel("Tipping disclaimer")

                    TactileCopyButton(
                        value: payload,
                        accessibilityLabel: "Copy Lightning Address"
                    )
                }
            }
        }
    }

    private func tipFallbackSection(url: URL) -> some View {
        let displayHost = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        return VStack(alignment: .leading, spacing: 6) {
            Text("Tips")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                HStack(alignment: .center, spacing: 4) {
                    Button {
                        BitLocalHaptics.lightTap()
                        openURL(url)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "heart")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Support This Community")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(displayHost)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactileRow(cornerRadius: 10))
                    .copyValueContextMenu(url.absoluteString, title: "Copy Support Link")

                    TactileCopyButton(
                        value: url.absoluteString,
                        accessibilityLabel: "Copy Support Link"
                    )
                }
            }
        }
    }

    // MARK: - Merchants Section

    private var merchantsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Merchants")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.communityMembersIsLoading || !memberElements.isEmpty {
                    Text("\(memberElements.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)

            if viewModel.communityMembersIsLoading && sameSelectedCommunity {
                PlaceGroupedSurface {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading merchants…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = viewModel.communityMembersError, !error.isEmpty, sameSelectedCommunity {
                PlaceGroupedSurface {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if memberElements.isEmpty {
                PlaceGroupedSurface {
                    Text("No merchants found for this community")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(memberElements.enumerated()), id: \.element.id) { index, element in
                            VStack(alignment: .leading, spacing: 0) {
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                                NavigationLink(value: BitLocalNavigationRoute.place(element)) {
                                    HStack(alignment: .center, spacing: 8) {
                                        ElementCell(viewModel: cellViewModel(for: element))
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.tactileRow(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Verification Section

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                if let verificationStatus {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: verificationStatus.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(verificationStatus.tint)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(verificationStatus.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(verificationStatus.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(verificationStatus.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Not Yet Verified")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("No verification date is available for this community.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data & Link Helpers

    private var socialLinks: [CommunitySocialLink] {
        let tags = area.tags ?? [:]
        let candidates: [(label: String, icon: String, keys: [String], base: String?)] = [
            ("X", "xmark", ["contact:x", "contact:twitter", "twitter"], "https://x.com/"),
            ("Facebook", "f.cursive", ["contact:facebook", "facebook"], "https://facebook.com/"),
            ("Instagram", "camera", ["contact:instagram", "instagram"], "https://instagram.com/"),
            ("Telegram", "paperplane", ["contact:telegram", "telegram"], "https://t.me/"),
            ("GitHub", "chevron.left.forwardslash.chevron.right", ["contact:github"], "https://github.com/"),
            ("LinkedIn", "briefcase", ["contact:linkedin"], "https://linkedin.com/in/"),
            ("YouTube", "play.rectangle", ["contact:youtube"], "https://youtube.com/"),
            ("Reddit", "bubble.left.and.bubble.right", ["contact:reddit"], "https://reddit.com/"),
            ("Nostr", "dot.radiowaves.left.and.right", ["contact:nostr"], nil)
        ]

        return candidates.compactMap { candidate in
            guard let rawValue = firstTagValue(for: candidate.keys, in: tags) else { return nil }
            let linkTarget: CommunityLinkTarget?
            if candidate.label == "Nostr" {
                linkTarget = nostrLinkTarget(for: rawValue)
            } else if let base = candidate.base {
                linkTarget = socialURL(for: rawValue, base: base).map { .web($0) }
            } else {
                linkTarget = websiteURL(from: rawValue).map { .web($0) }
            }
            return CommunitySocialLink(
                label: candidate.label,
                value: rawValue.cleanedForDisplay(),
                icon: candidate.icon,
                linkTarget: linkTarget
            )
        }
    }

    private var contactInformationLinks: [CommunitySocialLink] {
        let tags = area.tags ?? [:]
        let candidates: [(label: String, icon: String, key: String)] = [
            ("Website", "globe", "contact:website"),
            ("Website", "globe", "website"),
            ("Email", "envelope", "contact:email"),
            ("Phone", "phone", "contact:phone"),
            ("Discord", "message", "contact:discord"),
            ("Eventbrite", "ticket", "contact:eventbrite"),
            ("Geyser", "bolt", "contact:geyser"),
            ("Matrix", "square.grid.3x3", "contact:matrix"),
            ("Meetup", "person.3", "contact:meetup"),
            ("RSS", "dot.radiowaves.right", "contact:rss"),
            ("Satlantis", "sparkles", "contact:satlantis"),
            ("Signal", "message.badge", "contact:signal"),
            ("SimpleX", "ellipsis.bubble", "contact:simplex"),
            ("WhatsApp", "phone.bubble", "contact:whatsapp")
        ]

        var seen = Set<String>()
        return candidates.compactMap { item -> CommunitySocialLink? in
            guard let rawValue = firstTagValue(for: [item.key], in: tags) else { return nil }
            let displayValue = rawValue.cleanedForDisplay()
            let dedupeKey = "\(item.label)|\(displayValue)"
            guard !seen.contains(dedupeKey) else { return nil }
            seen.insert(dedupeKey)
            return CommunitySocialLink(
                label: item.label,
                value: displayValue,
                icon: item.icon,
                linkTarget: resolvedContactURL(forKey: item.key, value: rawValue).map { .web($0) }
            )
        }
    }

    private var primaryWebsiteURL: URL? {
        let tags = area.tags ?? [:]
        guard let raw = firstTagValue(for: ["contact:website", "website"], in: tags) else {
            return nil
        }
        return resolvedContactURL(forKey: "contact:website", value: raw)
    }

    private var btcMapCommunityURL: URL? {
        let rawSlug = area.tags?["url_alias"] ?? area.id
        let trimmed = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://btcmap.org/community/\(encoded)")
    }

    private var shareableURL: URL? {
        primaryWebsiteURL ?? btcMapCommunityURL
    }

    private var hasTipAction: Bool {
        payableLightningPayload != nil || tipFallbackURL != nil
    }

    private var tipValuesInPriority: [String] {
        let tags = area.tags ?? [:]
        let orderedKeys = ["tips:lightning_address", "tips:url", "ln_address"]
        var seen = Set<String>()
        return orderedKeys.compactMap { key in
            guard let raw = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            guard !seen.contains(raw) else { return nil }
            seen.insert(raw)
            return raw
        }
    }

    private var payableLightningPayload: String? {
        tipValuesInPriority.compactMap(normalizedPayableLightningPayload).first
    }

    private var tipFallbackURL: URL? {
        for value in tipValuesInPriority {
            if normalizedPayableLightningPayload(from: value) != nil { continue }
            if let fallback = nonPayableTipURL(from: value) {
                return fallback
            }
        }
        return nil
    }

    private var knownWallets: [LightningWalletOption] {
        [
            .init(id: "cashapp", name: "Cash App", appURLs: urls(["cashapp://", "squarecash://"])),
            .init(id: "strike", name: "Strike", appURLs: urls(["strike://"])),
            .init(id: "bluewallet", name: "BlueWallet", appURLs: urls(["bluewallet://"])),
            .init(id: "phoenix", name: "Phoenix", appURLs: urls(["phoenix://"])),
            .init(id: "zeus", name: "Zeus", appURLs: urls(["zeusln://"])),
            .init(id: "muun", name: "Muun", appURLs: urls(["muun://"])),
            .init(id: "wos", name: "Wallet of Satoshi", appURLs: urls(["walletofsatoshi://"])),
            .init(id: "breez", name: "Breez", appURLs: urls(["breez://"])),
            .init(id: "aqua", name: "Aqua", appURLs: urls(["aqua://"]))
        ]
    }

    private var installedWallets: [LightningWalletOption] {
        knownWallets.filter { wallet in
            wallet.appURLs.contains { UIApplication.shared.canOpenURL($0) }
        }
    }

    private var walletsForPicker: [LightningWalletOption] {
        installedWallets.isEmpty ? knownWallets : installedWallets
    }

    private var verificationStatus: CommunityVerificationStatus? {
        guard let raw = area.tags?["verified:date"],
              let verifiedDate = parsedBTCMapDate(raw),
              let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: .now) else {
            return nil
        }
        let formattedDate = verifiedDate.formatted(date: .abbreviated, time: .omitted)
        if verifiedDate > oneYearAgo {
            return .init(
                icon: "checkmark.seal.fill",
                tint: .green,
                title: "Verified",
                statusText: String(format: NSLocalizedString("Last verified: %@", comment: "Verification status date label"), formattedDate),
                explanation: "Someone physically confirmed this community within the past year."
            )
        }
        return .init(
            icon: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "Not Recently Verified",
            statusText: String(format: NSLocalizedString("Last verified: %@", comment: "Verification status date label"), formattedDate),
            explanation: "It has been more than a year since this community was verified."
        )
    }

    private func firstTagValue(for keys: [String], in tags: [String: String]) -> String? {
        keys.compactMap { key in
            tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first(where: { !$0.isEmpty })
    }

    private func websiteURL(from value: String) -> URL? {
        let normalized = value.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: value)
        }
        return URL(string: "https://\(value)")
    }

    private func socialURL(for value: String, base: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let handle = trimmed.replacingOccurrences(of: "@", with: "")
        return URL(string: base + handle)
    }

    private func resolvedContactURL(forKey key: String, value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        switch key {
        case "contact:website", "website":
            return websiteURL(from: trimmed)
        case "contact:email":
            return URL(string: "mailto:\(trimmed)")
        case "contact:phone":
            return URL(string: "tel:\(trimmed)")
        case "contact:github":
            return socialURL(for: trimmed, base: "https://github.com/")
        case "contact:linkedin":
            return socialURL(for: trimmed, base: "https://linkedin.com/in/")
        case "contact:discord":
            return socialURL(for: trimmed, base: "https://discord.gg/")
        case "contact:whatsapp":
            return socialURL(for: trimmed, base: "https://wa.me/")
        case "contact:matrix":
            return URL(string: "https://matrix.to/#/\(trimmed)")
        default:
            return websiteURL(from: trimmed)
        }
    }

    private var communityIconURL: URL? {
        guard let raw = area.tags?["icon:square"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return websiteURL(from: raw)
    }

    private func parsedBTCMapDate(_ raw: String) -> Date? {
        BTCMapDateParser.parse(raw)
    }

    private func normalizedPayableLightningPayload(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        // Support `lightning:<payload>` URIs only when payload looks wallet-payable.
        if lower.hasPrefix("lightning:") {
            let payload = String(trimmed.dropFirst("lightning:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return looksPayableLightningPayload(payload) ? payload : nil
        }

        return looksPayableLightningPayload(trimmed) ? trimmed : nil
    }

    private func looksPayableLightningPayload(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt") {
            return true // BOLT11 invoices
        }
        if lower.hasPrefix("lno1") || lower.hasPrefix("lnr1") || lower.hasPrefix("lni1") {
            return true // BOLT12 offer / invoice request / invoice
        }
        if lower.hasPrefix("lnurl1") {
            return true // Bech32 LNURL
        }
        if isLightningAddress(value) {
            return true // LUD-16 identifier (name@domain)
        }
        return false
    }

    private func nonPayableTipURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if isLightningAddress(trimmed) {
            let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let name = parts[0]
            let domain = parts[1]
            return URL(string: "https://\(domain)/\(name)")
        }
        return websiteURL(from: trimmed)
    }

    private func isLightningAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !local.contains(" "), !domain.contains(" ") else { return false }
        return domain.contains(".")
    }

    private func openWallet(_ wallet: LightningWalletOption, payload: String) {
        let appURL = wallet.appURLs.first(where: { UIApplication.shared.canOpenURL($0) }) ?? wallet.appURLs.first
        guard let appURL else {
            lightningErrorMessage = NSLocalizedString("The selected wallet could not be opened.", comment: "Error shown when no wallet URL can be opened")
            return
        }
        UIPasteboard.general.string = payload
        UIApplication.shared.open(appURL, options: [:]) { success in
            if success {
                lastLightningWalletID = wallet.id
            } else {
                lightningErrorMessage = String(
                    format: NSLocalizedString(
                        "Could not open %@. The lightning value has been copied so you can paste it manually.",
                        comment: "Error shown when opening a specific wallet fails"
                    ),
                    wallet.name
                )
            }
        }
    }

    private func openCommunityLink(_ item: CommunitySocialLink) {
        guard let linkTarget = item.linkTarget else { return }

        switch linkTarget {
        case .web(let url):
            openURL(url)
        case .appPreferred(let appURL):
            openURL(appURL) { accepted in
                guard !accepted else { return }
                linkOpenErrorItem = .nostr(copyValue: item.value)
            }
        }
    }

    private func nostrLinkTarget(for value: String) -> CommunityLinkTarget? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: trimmed).map { .web($0) }
        }

        let identifier: String
        if lowered.hasPrefix("nostr:") {
            identifier = String(trimmed.dropFirst("nostr:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            identifier = trimmed
        }

        guard !identifier.isEmpty else { return nil }
        return URL(string: "nostr:\(identifier)").map { .appPreferred(appURL: $0) }
    }

    private var sameSelectedCommunity: Bool {
        viewModel.selectedCommunityArea?.id == area.id
    }

    private func updateMemberElements() {
        guard sameSelectedCommunity else {
            if !memberElements.isEmpty { memberElements = [] }
            return
        }
        let sorted = viewModel.communityMemberElements.sorted {
            let lhs = $0.displayName ?? $0.id
            let rhs = $1.displayName ?? $1.id
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        if sorted.map(\.id) != memberElements.map(\.id) {
            memberElements = sorted
        }
    }

    private func cellViewModel(for element: Element) -> ElementCellViewModel {
        viewModel.cachedCellViewModel(for: element)
    }

    private var isCollapsedLikeDetent: Bool {
        guard let detent = currentDetent else { return false }
        return detent == BottomSheetDetents.collapsed || detentIdentifier(detent).contains("fraction 0.11")
    }

    private var isLargeSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("large")
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    private func urls(_ values: [String]) -> [URL] {
        values.compactMap(URL.init(string:))
    }
}

private struct CommunitySocialLink: Identifiable {
    let label: String
    let value: String
    let icon: String
    let linkTarget: CommunityLinkTarget?

    var id: String { "\(label)|\(value)" }
    var isInteractive: Bool { linkTarget != nil }
}

private enum CommunityLinkTarget {
    case web(URL)
    case appPreferred(appURL: URL)
}

private struct CommunityLinkOpenError {
    let message: String
    let copyValue: String?

    static func nostr(copyValue: String) -> Self {
        Self(
            message: NSLocalizedString("It doesn't look like you have a Nostr app installed.", comment: "Error shown when trying to open a nostr profile without a compatible app"),
            copyValue: copyValue
        )
    }
}

private struct CommunityVerificationStatus {
    let icon: String
    let tint: Color
    let title: String
    let statusText: String
    let explanation: String
}

private struct LightningWalletOption: Identifiable {
    let id: String
    let name: String
    let appURLs: [URL]
}

private struct ShareTextItem: Identifiable {
    let id = UUID()
    let items: [Any]

    init(text: String) {
        self.items = [text]
    }

    init(items: [Any]) {
        self.items = items
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
private struct CommunityIconImage: View {
    let url: URL?
    let placeholderSystemName: String?
    let scaleToFill: Bool

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: scaleToFill ? .fill : .fit)
            } else if let placeholderSystemName {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.accent)
            } else {
                Color.clear
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                uiImage = nil
                return
            }
            uiImage = await CommunityIconCache.shared.image(for: url)
        }
    }
}

actor CommunityIconCache {
    static let shared = CommunityIconCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let directoryURL: URL

    private init() {
        directoryURL = URL.cachesDirectory.appending(path: "CommunityIconCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let fileURL = directoryURL.appending(path: fileName(for: url))
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: cacheKey)
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).img"
    }
}

private extension View {
    func copyValueContextMenu(_ value: String, title: String = "Copy") -> some View {
        contextMenu {
            Button {
                UIPasteboard.general.string = value
                BitLocalHaptics.success()
            } label: {
                Label(title, systemImage: "doc.on.doc")
            }
        }
    }
}
