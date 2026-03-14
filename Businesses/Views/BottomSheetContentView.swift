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

struct BottomSheetContentView: View {
    private static let sheetHeightPublishThreshold: CGFloat = 24
    private static let sheetHeightBucketSize: CGFloat = 24

    @EnvironmentObject var viewModel: ContentViewModel
    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent

    var body: some View {
        GeometryReader { geometry in
            VStack {
                navigationStack(sheetHeight: geometry.size.height)
                .onChange(of: viewModel.unifiedSearchText) { _, _ in
                    guard viewModel.mapDisplayMode != .communities else { return }
                    viewModel.performUnifiedSearch()
                }
                .onChange(of: viewModel.isSearchActive) { _, isActive in
                    guard viewModel.mapDisplayMode != .communities else { return }
                    if !isActive {
                        viewModel.unifiedSearchText = ""
                        viewModel.performUnifiedSearch()
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: geometry.size.height) { _, newHeight in
                let normalizedHeight = (newHeight / Self.sheetHeightBucketSize).rounded() * Self.sheetHeightBucketSize
                guard abs(viewModel.bottomPadding - normalizedHeight) >= Self.sheetHeightPublishThreshold else {
                    return
                }
                viewModel.bottomPadding = normalizedHeight
            }
            .onChange(of: viewModel.path) { _, newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if newPath.last != nil {
                    _ = viewModel.consumeSelectionSource()
                    viewModel.selectedElement = newPath.last
                } else {
                    viewModel.deselectAnnotation()
                }
            }
        }
    }

    private func navigationStack(sheetHeight: CGFloat) -> some View {
        NavigationStack(path: $viewModel.path) {
            sheetRootContent(sheetHeight: sheetHeight)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("")
                .ignoresSafeArea(.container, edges: .top)
                .navigationDestination(for: Element.self) { element in
                    businessDetailDestination(for: element)
                }
                .navigationDestination(isPresented: communityDetailBindingIsPresented) {
                    communityDetailDestination
                }
                .clearNavigationContainerBackgroundIfAvailable()
        }
    }

    @ViewBuilder
    private func sheetRootContent(sheetHeight: CGFloat) -> some View {
        if viewModel.mapDisplayMode == .communities {
            CommunitiesListView(currentDetent: currentDetent)
                .environmentObject(viewModel)
        } else {
            BusinessesListView(
                elements: visibleElements,
                currentDetent: currentDetentBinding,
                liveSheetHeight: sheetHeight
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
    }

    @ViewBuilder
    private var communityDetailDestination: some View {
        if let area = viewModel.presentedCommunityArea {
            CommunityDetailView(
                area: area,
                currentDetent: currentDetentBinding
            )
            .id(area.id)
            .environmentObject(viewModel)
            .clearNavigationContainerBackgroundIfAvailable()
        }
    }

    private var communityDetailBindingIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.presentedCommunityArea != nil },
            set: { newValue in
                if !newValue {
                    viewModel.presentedCommunityArea = nil
                }
            }
        )
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

struct CommunitiesListView: View {
    private let resultsPageSize = 15

    @EnvironmentObject private var viewModel: ContentViewModel
    @ObservedObject private var metadataStore = CommunityRowMetadataObservableStore.shared
    var currentDetent: PresentationDetent? = nil
    @State private var filterText = ""
    @State private var communityResultsLimit = 15
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        let filtered = filteredCommunities
        let displayed = Array(filtered.prefix(communityResultsLimit))
        let hasMore = filtered.count > displayed.count

        VStack(spacing: 0) {
            searchBar
                .padding(.top, 20)
                .padding(.bottom, 2)

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
                    }
                }

                Section {
                    if filtered.isEmpty {
                        Text(emptyStateMessage)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden, edges: .top)
                    } else {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, area in
                            Button {
                                viewModel.selectCommunity(area, presentDetail: true)
                            } label: {
                                ZStack(alignment: .trailing) {
                                    CommunityRow(
                                        area: area,
                                        metadata: metadataStore.metadataByAreaID[area.id]
                                    )
                                    .padding(.trailing, 18)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.gray.opacity(0.6))
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                        }

                        if hasMore {
                            Button("Load more communities") {
                                communityResultsLimit += resultsPageSize
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
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
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            TextField("Search communities…", text: $filterText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .padding(.horizontal, 16)
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
                    .font(.system(size: 10, weight: .semibold))

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
    let shape: S
    private let duration: Double = 1.5

    var body: some View {
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
private final class CommunityRowMetadataObservableStore: ObservableObject {
    static let shared = CommunityRowMetadataObservableStore()

    @Published var metadataByAreaID: [String: CommunityRowMetadata] = [:]
}

struct CommunityDetailView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var viewModel: ContentViewModel
    let area: V2AreaRecord
    @Binding private var currentDetent: PresentationDetent?
    @AppStorage("community.lastLightningWalletID") private var lastLightningWalletID: String = ""
    @State private var showLightningAlert = false
    @State private var showWalletAlert = false
    @State private var showTipsDisclaimerAlert = false
    @State private var shareItem: ShareTextItem?
    @State private var linkOpenErrorItem: CommunityLinkOpenError?
    @State private var lightningErrorMessage: String?

    init(area: V2AreaRecord, currentDetent: Binding<PresentationDetent?> = .constant(nil)) {
        self.area = area
        self._currentDetent = currentDetent
    }

    var body: some View {
        List {
            if let communityIconURL {
                HStack {
                    Spacer()
                    CommunityIconImage(url: communityIconURL, placeholderSystemName: nil, scaleToFill: false)
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.secondary.opacity(0.2), lineWidth: 1)
                        )
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
            }

            if let description = area.tags?["description"], !description.isEmpty {
                Section("Description") {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            }

//            if hasAboutData {
//                Section("About") {
//                    if let org = area.tags?["organization"], !org.isEmpty {
//                        detailRow(icon: "building.2", text: org)
//                    }
//                }
//                .groupedCardListRowBackground(if: shouldUseGlassyRows)
//            }

            if !contactInformationLinks.isEmpty {
                Section("Contact Information") {
                    ForEach(contactInformationLinks) { item in
                        linkableValueRow(item)
                    }
                }
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            }

            if !socialLinks.isEmpty {
                Section("Socials") {
                    ForEach(socialLinks) { social in
                        linkableValueRow(social)
                    }
                }
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            }

            if hasTipsData {
                Section("Tips") {
                    if let payload = payableLightningPayload {
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                showLightningAlert = true
                            } label: {
                                tipActionRow(payload: payload)
                            }
                            .buttonStyle(.plain)
                            .copyValueContextMenu(payload, title: "Copy Lightning Address")

                            Button {
                                showTipsDisclaimerAlert = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Tipping disclaimer")
                        }
                    } else if let tipFallbackURL {
                        linkableValueRow(
                            .init(
                                label: "Support This Community",
                                value: tipFallbackURL.host?.replacingOccurrences(of: "www.", with: "") ?? tipFallbackURL.absoluteString,
                                icon: "heart.text.square.fill",
                                linkTarget: .web(tipFallbackURL)
                            )
                        )
                    }
                }
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            }

            Section("Verification") {
                if let verificationStatus {
                    detailRow(
                        icon: verificationStatus.icon,
                        tint: verificationStatus.tint,
                        label: verificationStatus.title,
                        value: verificationStatus.statusText
                    )
                    Text(verificationStatus.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    detailRow(
                        icon: "questionmark.circle.fill",
                        tint: .secondary,
                        label: "Not Yet Verified",
                        value: "No verification date is available for this community."
                    )
                }
            }
            .groupedCardListRowBackground(if: shouldUseGlassyRows)

            // MARK: Merchants
            Section {
                if viewModel.communityMembersIsLoading && sameSelectedCommunity {
                    HStack {
                        ProgressView()
                        Text("Loading merchants…")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = viewModel.communityMembersError, !error.isEmpty, sameSelectedCommunity {
                    Text(error)
                        .foregroundStyle(.red)
                } else if memberElements.isEmpty {
                    Text("No merchants found for this community")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memberElements, id: \.id) { element in
                        NavigationLink {
                            BusinessDetailView(
                                element: element,
                                userLocation: viewModel.userLocation,
                                contentViewModel: viewModel,
                                currentDetent: $currentDetent
                            )
                            .onAppear {
                                viewModel.setSelectionSource(.list)
                                viewModel.selectAnnotationForListSelection(
                                    element,
                                    animated: true,
                                    allowCameraMovement: !isLargeSheet
                                )
                                viewModel.selectedElement = element
                            }
                        } label: {
                            ElementCell(viewModel: cellViewModel(for: element))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Merchants")
                    Spacer()
                    Text("\(memberElements.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
            .groupedCardListRowBackground(if: shouldUseGlassyRows)
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.automatic)
        .navigationTitle(area.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
            Button("OK", role: .cancel) {}
        } message: {
            Text("BitLocal does not process, custody, or guarantee tip transactions. We only open your selected wallet or link and help copy/share the Lightning address.")
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.text])
        }
        .alert("Unable to Open Wallet", isPresented: Binding(
            get: { lightningErrorMessage != nil },
            set: { newValue in
                if !newValue { lightningErrorMessage = nil }
            })
        ) {
            Button("OK", role: .cancel) {}
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
                }
            }
            Button("OK") {}
        } message: {
            Text(linkOpenErrorItem?.message ?? "")
        }
        .opacity(shouldShowCollapsedHeaderOnly ? 0 : 1)
        .allowsHitTesting(!shouldShowCollapsedHeaderOnly)
        .accessibilityHidden(shouldShowCollapsedHeaderOnly)
    }

    // MARK: - Helpers

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 22)
            Text(text)
                .font(.body)
        }
    }

    private func detailRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func linkableValueRow(_ item: CommunitySocialLink) -> some View {
        Group {
            if item.isInteractive {
                Button {
                    openCommunityLink(item)
                } label: {
                    platformLinkRow(icon: item.icon, label: item.label, value: item.value)
                }
                .buttonStyle(.plain)
            } else {
                platformLinkRow(icon: item.icon, label: item.label, value: item.value)
            }
        }
        .copyValueContextMenu(
            item.value,
            title: String(format: NSLocalizedString("Copy %@", comment: "Context menu title to copy a labeled value"), item.label)
        )
    }

    private func platformLinkRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.accent)
                if !value.isEmpty, value != label {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func tipActionRow(payload: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tip This Community")
                    .foregroundStyle(.accent)
                Text("Support this community over Lightning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(payload)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

//    private var hasAboutData: Bool {
//        if let val = area.tags?["organization"], !val.isEmpty { return true }
//        return false
//    }

    private var socialLinks: [CommunitySocialLink] {
        let tags = area.tags ?? [:]
        let candidates: [(label: String, icon: String, keys: [String], base: String?)] = [
            ("X", "xmark.circle.fill", ["contact:x", "contact:twitter", "twitter"], "https://x.com/"),
            ("Facebook", "f.cursive.circle.fill", ["contact:facebook", "facebook"], "https://facebook.com/"),
            ("Instagram", "camera.circle.fill", ["contact:instagram", "instagram"], "https://instagram.com/"),
            ("Telegram", "paperplane.circle.fill", ["contact:telegram", "telegram"], "https://t.me/"),
            ("GitHub", "chevron.left.forwardslash.chevron.right", ["contact:github"], "https://github.com/"),
            ("LinkedIn", "briefcase.circle.fill", ["contact:linkedin"], "https://linkedin.com/in/"),
            ("YouTube", "play.rectangle.fill", ["contact:youtube"], "https://youtube.com/"),
            ("Reddit", "bubble.left.and.bubble.right.fill", ["contact:reddit"], "https://reddit.com/"),
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
            ("Email", "envelope.fill", "contact:email"),
            ("Phone", "phone.fill", "contact:phone"),
            ("Discord", "message.circle.fill", "contact:discord"),
            ("Eventbrite", "ticket.fill", "contact:eventbrite"),
            ("Geyser", "bolt.circle.fill", "contact:geyser"),
            ("Matrix", "square.grid.3x3.fill", "contact:matrix"),
            ("Meetup", "person.3.fill", "contact:meetup"),
            ("RSS", "dot.radiowaves.right", "contact:rss"),
            ("Satlantis", "sparkles.square.filled.on.square", "contact:satlantis"),
            ("Signal", "message.badge.filled.fill", "contact:signal"),
            ("SimpleX", "ellipsis.bubble.fill", "contact:simplex"),
            ("WhatsApp", "phone.circle.fill", "contact:whatsapp")
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

    private var hasTipsData: Bool {
        !tipValuesInPriority.isEmpty
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
              let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) else {
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
        if let fullISO = ISO8601DateFormatter.communityFullPrecision.date(from: raw) {
            return fullISO
        }
        if let basicISO = ISO8601DateFormatter().date(from: raw) {
            return basicISO
        }
        return CommunityBTCMapDateParsers.dateOnly.date(from: raw)
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

    @State private var memberElements: [Element] = []

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
        if let vm = viewModel.cellViewModels[element.id] {
            return vm
        }
        let newVM = ElementCellViewModel(
            element: element,
            userLocation: viewModel.userLocation,
            viewModel: viewModel
        )
        DispatchQueue.main.async {
            viewModel.cellViewModels[element.id] = newVM
        }
        return newVM
    }

    private var shouldShowCollapsedHeaderOnly: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("fraction 0.11")
    }

    private var isLargeSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("large")
    }

    private var shouldUseGlassyRows: Bool {
        false
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
    let text: String
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
                    .if(scaleToFill) { view in
                        view.scaledToFill()
                    }
                    .if(!scaleToFill) { view in
                        view.scaledToFit()
                    }
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
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base.appendingPathComponent("CommunityIconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let fileURL = directoryURL.appendingPathComponent(fileName(for: url))
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

private extension ISO8601DateFormatter {
    static let communityFullPrecision: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private enum CommunityBTCMapDateParsers {
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension View {
    func copyValueContextMenu(_ value: String, title: String = "Copy") -> some View {
        contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label(title, systemImage: "doc.on.doc")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
