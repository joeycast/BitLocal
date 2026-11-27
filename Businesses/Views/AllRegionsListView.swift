import SwiftUI

// MARK: - All Regions List (pushed onto NavigationStack)

struct AllRegionsListView: View {
    @Environment(ContentViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filterText = ""

    var body: some View {
        List {
            if viewModel.areaBrowserIsLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading regions…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = viewModel.areaBrowserError, !error.isEmpty {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            let areas = filteredAreas
            if areas.isEmpty && !viewModel.areaBrowserIsLoading {
                Section {
                    if !filterText.isEmpty {
                        ContentUnavailableView.search(text: filterText)
                    } else {
                        ContentUnavailableView("No Regions Found", systemImage: "globe")
                    }
                }
            } else {
                Section {
                    ForEach(areas) { area in
                        Button {
                            viewModel.selectArea(area)
                            dismiss()
                        } label: {
                            BTCMapAreaRow(area: area)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Regions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filterText, prompt: "Filter regions…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh regions", systemImage: "arrow.clockwise", action: viewModel.loadAreaBrowserAreas)
            }
        }
        .onAppear {
            if viewModel.areaBrowserAreas.isEmpty { viewModel.loadAreaBrowserAreas() }
        }
    }

    private var filteredAreas: [V3AreaRecord] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.areaBrowserAreas }
        return viewModel.areaBrowserAreas.filter { area in
            area.displayName.localizedStandardContains(q) ||
            (area.urlAlias?.localizedStandardContains(q) ?? false) ||
            (area.tags?["name:en"]?.localizedStandardContains(q) ?? false)
        }
    }
}
