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

    @State private var savedDetent: PresentationDetent?

    var body: some View {
        GeometryReader { geometry in
            VStack {
                NavigationStack(path: $viewModel.path) {
                    Group {
                        if viewModel.mapDisplayMode == .communities {
                            CommunitiesListView()
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
                    .clearNavigationContainerBackgroundIfAvailable()
                }
                .sheet(item: $viewModel.presentedCommunityArea) { area in
                    NavigationStack {
                        CommunityDetailView(area: area)
                            .environmentObject(viewModel)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close") {
                                        viewModel.presentedCommunityArea = nil
                                    }
                                }
                            }
                    }
                }
                .onChange(of: viewModel.unifiedSearchText) { _, _ in
                    viewModel.performUnifiedSearch()
                }
                .onChange(of: viewModel.isSearchActive) { _, isActive in
                    if isActive {
                        savedDetent = currentDetent
                        currentDetent = .large
                    } else {
                        if let saved = savedDetent {
                            currentDetent = saved
                        }
                        savedDetent = nil
                        viewModel.unifiedSearchText = ""
                        viewModel.performUnifiedSearch()
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                DispatchQueue.main.async {
                    let bottomSheetHeight = geometry.size.height
                    if viewModel.bottomPadding != bottomSheetHeight {
                        viewModel.bottomPadding = bottomSheetHeight
                        Debug.log("Accurate Bottom Sheet Height: \(bottomSheetHeight)")
                    }
                }
            }
            .onChange(of: geometry.size.height) { _, newHeight in
                viewModel.bottomPadding = newHeight
                Debug.log("BottomSheetContentView height updated: \(newHeight)")
            }
            .onChange(of: viewModel.path) { _, newPath in
                Debug.log("BottomSheet path changed (iPhone scenario)")
                if let selectedElement = newPath.last {
                    if viewModel.consumeSelectionSource() == .mapAnnotation {
                        viewModel.zoomToElement(selectedElement)
                    }
                    viewModel.selectedElement = selectedElement
                } else {
                    viewModel.deselectAnnotation()
                }
            }
        }
    }
}

@available(iOS 17.0, *)
struct CommunitiesListView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @State private var filterText = ""

    var body: some View {
        List {
            if let selected = viewModel.selectedCommunityArea {
                Section {
                    Button {
                        viewModel.clearSelectedCommunity()
                    } label: {
                        Label("Show All Communities", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.displayName)
                            .font(.headline)
                        if viewModel.communityMembersIsLoading {
                            Label("Loading community merchants…", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let error = viewModel.communityMembersError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("\(viewModel.communityMemberElements.count) merchants on map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if viewModel.communityMapAreasIsLoading && filteredCommunities.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading communities…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Communities") {
                ForEach(filteredCommunities) { area in
                    Button {
                        viewModel.selectCommunity(area)
                    } label: {
                        CommunityRow(area: area)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $filterText, prompt: "Search communities…")
        .onAppear {
            viewModel.ensureCommunityMapAreasLoaded()
        }
    }

    private var filteredCommunities: [V2AreaRecord] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.communityListAreas }
        return viewModel.communityListAreas.filter { area in
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

@available(iOS 17.0, *)
struct CommunityDetailView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    let area: V2AreaRecord

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
                        Button {
                            viewModel.presentedCommunityArea = nil
                            viewModel.setSelectionSource(.list)
                            viewModel.selectAnnotation(for: element, animated: true)
                            viewModel.path = [element]
                        } label: {
                            ZStack(alignment: .trailing) {
                                ElementCell(viewModel: cellViewModel(for: element))
                                    .padding(.trailing, 18)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.gray.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
            let lhs = $0.osmJSON?.tags?.name ?? $0.id
            let rhs = $1.osmJSON?.tags?.name ?? $1.id
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
}
