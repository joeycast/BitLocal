import SwiftUI

@available(iOS 17.0, *)
struct MerchantAlertCityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MerchantAlertCityPickerModel()
    @FocusState private var isSearchFieldFocused: Bool

    let onSelection: (MerchantAlertCityChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                if model.isLoading && model.results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading cities…")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else if model.results.isEmpty {
                    ContentUnavailableView(
                        "No City Matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a city name like Austin, Berlin, or Nashville.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    Text(sectionTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        ForEach(model.results) { result in
                            Button {
                                onSelection(result.choice)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.displayName)
                                        .foregroundStyle(.primary)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                }
            }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Choose City")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            model.start()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))

            TextField("Search cities worldwide", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
                .submitLabel(.search)

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sectionTitle: String {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.count >= 2 ? "Search Results" : "Popular Cities"
    }
}

@MainActor
final class MerchantAlertCityPickerModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            scheduleSearch(for: searchText)
        }
    }
    @Published private(set) var results: [CitySearchResult] = []
    @Published private(set) var isLoading = false

    private var searchTask: Task<Void, Never>?
    private let store = CityIndexStore.shared
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true

        searchTask?.cancel()
        searchTask = Task {
            await store.preloadIfNeeded()
            guard !Task.isCancelled else { return }
            let popular = await store.popular(limit: 30)
            guard !Task.isCancelled else { return }
            results = popular
            isLoading = false
        }
    }

    private func scheduleSearch(for rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        isLoading = true

        searchTask = Task {
            await store.preloadIfNeeded()
            guard !Task.isCancelled else { return }

            let nextResults: [CitySearchResult]
            if query.count >= 2 {
                nextResults = await store.search(query: query, limit: 30)
            } else {
                nextResults = await store.popular(limit: 30)
            }

            guard !Task.isCancelled else { return }
            results = nextResults
            isLoading = false
        }
    }
}
