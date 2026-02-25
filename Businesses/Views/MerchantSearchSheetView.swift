import SwiftUI
import CoreLocation

@available(iOS 17.0, *)
struct MerchantSearchSheetView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var debounceTask: Task<Void, Never>?

    private let radiusOptions: [Double] = [5, 20, 50]

    var body: some View {
        NavigationStack {
            List {
                querySection
                statusSection
                resultsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search Merchants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        viewModel.isMerchantSearchPresented = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") {
                        triggerImmediateSearch()
                    }
                    .disabled(isSearchActionDisabled)
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private var querySection: some View {
        Section("Query") {
            TextField("Merchant name (min 3 chars)", text: $viewModel.merchantSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onChange(of: viewModel.merchantSearchText) { _, _ in
                    scheduleSearch()
                }

            TextField("Provider tag (e.g. coinos or payment:coinos)", text: $viewModel.merchantSearchProviderFilter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onChange(of: viewModel.merchantSearchProviderFilter) { _, _ in
                    scheduleSearch()
                }

            Toggle("Search near current map center", isOn: $viewModel.merchantSearchUseMapCenter)
                .onChange(of: viewModel.merchantSearchUseMapCenter) { _, _ in
                    scheduleSearch()
                }

            if viewModel.merchantSearchUseMapCenter {
                Picker("Radius", selection: $viewModel.merchantSearchRadiusKM) {
                    ForEach(radiusOptions, id: \.self) { radius in
                        Text("\(Int(radius)) km").tag(radius)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.merchantSearchRadiusKM) { _, _ in
                    scheduleSearch()
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if viewModel.merchantSearchIsLoading {
            Section {
                HStack {
                    ProgressView()
                    Text("Searching…")
                        .foregroundColor(.secondary)
                }
            }
        } else if let error = viewModel.merchantSearchError, !error.isEmpty {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        Section("Results") {
            if viewModel.merchantSearchResults.isEmpty {
                Text("No results yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.merchantSearchResults) { result in
                    Button {
                        triggerResultSelection(result)
                    } label: {
                        MerchantSearchResultRow(
                            result: result,
                            referenceLocation: searchReferenceLocation
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchReferenceLocation: CLLocation? {
        if let userLocation = viewModel.userLocation {
            return userLocation
        }
        let center = viewModel.region.center
        return CLLocation(latitude: center.latitude, longitude: center.longitude)
    }

    private var isSearchActionDisabled: Bool {
        let nameCount = viewModel.merchantSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count
        let hasProvider = !viewModel.merchantSearchProviderFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArea = viewModel.merchantSearchUseMapCenter
        return !(nameCount >= 3 || hasProvider || hasArea)
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                viewModel.performMerchantSearch()
            }
        }
    }

    private func triggerImmediateSearch() {
        debounceTask?.cancel()
        viewModel.performMerchantSearch()
    }

    private func triggerResultSelection(_ result: V4PlaceRecord) {
        debounceTask?.cancel()
        viewModel.selectMerchantSearchResult(result)
    }
}

@available(iOS 17.0, *)
struct MerchantSearchResultRow: View {
    let result: V4PlaceRecord
    let referenceLocation: CLLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()

                if let distanceText {
                    Text(distanceText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let address = result.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let verifiedAt = result.verifiedAt, !verifiedAt.isEmpty {
                    badge("Verified \(shortVerifiedDate(verifiedAt))", color: .green)
                }
                if let comments = result.comments, comments > 0 {
                    badge("\(comments) comments", color: .blue)
                }
                if let boostedUntil = result.boostedUntil, !boostedUntil.isEmpty {
                    badge("Boosted", color: .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var distanceText: String? {
        guard let referenceLocation,
              let lat = result.lat,
              let lon = result.lon else { return nil }

        let target = CLLocation(latitude: lat, longitude: lon)
        let meters = referenceLocation.distance(from: target)
        let useMetric = Locale.current.measurementSystem == .metric

        if useMetric {
            let km = meters / 1000
            return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
        } else {
            let miles = meters / 1609.34
            return miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
        }
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func shortVerifiedDate(_ raw: String) -> String {
        if raw.count >= 10 {
            return String(raw.prefix(10))
        }
        return raw
    }
}

