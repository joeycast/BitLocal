import SwiftUI

// MARK: - All Regions List (pushed onto NavigationStack)

@available(iOS 17.0, *)
struct AllRegionsListView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
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
                    Text("No regions found")
                        .foregroundStyle(.secondary)
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
                Button {
                    viewModel.loadAreaBrowserAreas()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh regions")
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
