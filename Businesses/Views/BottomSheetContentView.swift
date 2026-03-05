//
//  BottomSheetContentView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import SwiftUI
import Foundation // for Debug logging

@available(iOS 17.0, *)
struct BottomSheetContentView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    var visibleElements: [Element]
    @Binding var currentDetent: PresentationDetent

    var body: some View {
        GeometryReader { geometry in
            VStack {
                NavigationStack(path: $viewModel.path) {
                    Group {
                        if viewModel.mapDisplayMode == .communities {
                            CommunitiesListView(currentDetent: currentDetent)
                                .environmentObject(viewModel)
                        } else {
                            BusinessesListView(
                                elements: visibleElements,
                                currentDetent: currentDetent
                            )
                            .environmentObject(viewModel)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Element.self) { element in
                        BusinessDetailView(
                            element: element,
                            userLocation: viewModel.userLocation,
                            contentViewModel: viewModel,
                            currentDetent: currentDetent
                        )
                        .id(element.id)
                        .clearNavigationContainerBackgroundIfAvailable()
                    }
                    .navigationDestination(isPresented: communityDetailBindingIsPresented) {
                        if let area = viewModel.presentedCommunityArea {
                            CommunityDetailView(
                                area: area,
                                currentDetent: currentDetent
                            )
                                .environmentObject(viewModel)
                                .clearNavigationContainerBackgroundIfAvailable()
                        }
                    }
                    .clearNavigationContainerBackgroundIfAvailable()
                }
                .onChange(of: viewModel.unifiedSearchText) { _, _ in
                    guard viewModel.mapDisplayMode != .communities else { return }
                    viewModel.performUnifiedSearch()
                }
                .onChange(of: viewModel.isSearchActive) { _, isActive in
                    guard viewModel.mapDisplayMode != .communities else { return }
                    if isActive {
                        promoteSheetToLargeIfNeeded()
                    } else {
                        viewModel.unifiedSearchText = ""
                        viewModel.performUnifiedSearch()
                    }
                }
                .onChange(of: viewModel.selectedCommunityArea?.id) { _, selectedID in
                    guard selectedID != nil else { return }
                    setSheetToDefaultDetent()
                }
                .onChange(of: viewModel.presentedCommunityArea?.id) { _, presentedID in
                    guard presentedID != nil else { return }
                    setSheetToDefaultDetent()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onChange(of: geometry.size.height) { _, newHeight in
                viewModel.bottomPadding = newHeight
                Debug.log("BottomSheetContentView height updated: \(newHeight)")
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

    private func promoteSheetToLargeIfNeeded() {
        guard currentDetent != .large else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentDetent = .large
        }
    }

    private func setSheetToDefaultDetent() {
        let defaultDetent: PresentationDetent = .fraction(0.3)
        guard currentDetent != defaultDetent else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentDetent = defaultDetent
        }
    }
}

@available(iOS 17.0, *)
struct CommunitiesListView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    var currentDetent: PresentationDetent? = nil
    @State private var filterText = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.top, 20)
                .padding(.bottom, 2)

            List {
                if viewModel.communityMapAreasIsLoading &&
                    viewModel.communityMapAreas.isEmpty &&
                    viewModel.areaBrowserAreas.isEmpty &&
                    filteredCommunities.isEmpty {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading communities…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Communities") {
                    if filteredCommunities.isEmpty {
                        Text("No communities in current map view")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredCommunities) { area in
                            NavigationLink {
                                CommunityDetailView(
                                    area: area,
                                    currentDetent: currentDetent
                                )
                                    .environmentObject(viewModel)
                                    .onAppear {
                                        viewModel.selectCommunity(area, presentDetail: false)
                                    }
                            } label: {
                                CommunityRow(area: area)
                            }
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
        let baseAreas = viewModel.visibleCommunityListAreas
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return baseAreas }
        return baseAreas.filter { area in
            area.displayName.localizedStandardContains(q) ||
            (area.tags?["organization"]?.localizedStandardContains(q) ?? false) ||
            (area.tags?["continent"]?.localizedStandardContains(q) ?? false)
        }
    }
}

@available(iOS 17.0, *)
private struct CommunityRow: View {
    let area: V2AreaRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if let org = area.tags?["organization"], !org.isEmpty {
                        Text(org)
                    }
                    if let continent = area.tags?["continent"], !continent.isEmpty {
                        Text(continent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(.rect)
    }
}

@available(iOS 17.0, *)
struct CommunityDetailView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let area: V2AreaRecord
    var currentDetent: PresentationDetent? = nil

    var body: some View {
        List {
            // MARK: Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(area.displayName)
                        .font(.title2.weight(.bold))

                    if let description = area.tags?["description"], !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Label(
                        "\(memberElements.count) merchants",
                        systemImage: "storefront"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.accent)
                }
                .padding(.vertical, 4)
            }

            // MARK: About
            if hasAboutData {
                Section("About") {
                    if let org = area.tags?["organization"], !org.isEmpty {
                        detailRow(icon: "building.2", text: org)
                    }
                    if let continent = area.tags?["continent"], !continent.isEmpty {
                        detailRow(icon: "globe", text: continent)
                    }
                    if let language = area.tags?["language"], !language.isEmpty {
                        detailRow(icon: "character.book.closed", text: language)
                    }
                    if let website = area.tags?["contact:website"], !website.isEmpty,
                       let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
                        Link(destination: url) {
                            detailRow(icon: "link", text: cleanedURL(website))
                        }
                    }
                    if let telegram = area.tags?["contact:telegram"], !telegram.isEmpty,
                       let url = URL(string: "https://t.me/\(telegram.replacingOccurrences(of: "@", with: ""))") {
                        Link(destination: url) {
                            detailRow(icon: "paperplane", text: telegram)
                        }
                    }
                    if let twitter = area.tags?["contact:twitter"], !twitter.isEmpty,
                       let url = URL(string: "https://x.com/\(twitter.replacingOccurrences(of: "@", with: ""))") {
                        Link(destination: url) {
                            detailRow(icon: "at", text: twitter)
                        }
                    }
                }
            }

            // MARK: Merchants
            Section("Merchants") {
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
                                currentDetent: currentDetent
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
            }
        }
        .opacity(shouldShowCollapsedHeaderOnly ? 0 : 1)
        .allowsHitTesting(!shouldShowCollapsedHeaderOnly)
        .accessibilityHidden(shouldShowCollapsedHeaderOnly)
        .listStyle(.insetGrouped)
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: area.id) {
            if viewModel.selectedCommunityArea?.id != area.id || viewModel.communityMemberElements.isEmpty {
                viewModel.selectCommunity(area, presentDetail: false)
            }
        }
    }

    // MARK: - Helpers

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            Text(text)
                .font(.body)
        }
    }

    private func cleanedURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
           .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var hasAboutData: Bool {
        let tags = area.tags ?? [:]
        let keys = ["organization", "continent", "language", "contact:website", "contact:telegram", "contact:twitter"]
        return keys.contains { key in
            if let val = tags[key], !val.isEmpty { return true }
            return false
        }
    }

    private var sameSelectedCommunity: Bool {
        viewModel.selectedCommunityArea?.id == area.id
    }

    private var memberElements: [Element] {
        guard sameSelectedCommunity else { return [] }
        return viewModel.communityMemberElements.sorted {
            let lhs = $0.displayName ?? $0.id
            let rhs = $1.displayName ?? $1.id
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
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

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }
}
