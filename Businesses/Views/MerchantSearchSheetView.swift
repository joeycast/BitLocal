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
                summarySection
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

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Find merchants by name, provider, or map radius", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))

                Text("Results open the merchant detail and recenter the map.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(emptyResultsTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(emptyResultsSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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

    private var emptyResultsTitle: String {
        if viewModel.merchantSearchIsLoading { return "Searching…" }
        if hasEnteredSearchInputs { return "No matching merchants" }
        return "Start a search"
    }

    private var emptyResultsSubtitle: String {
        if hasEnteredSearchInputs {
            return "Try a different name, provider tag, or radius."
        }
        return "Enter at least 3 letters, a provider tag, or search near the current map center."
    }

    private var hasEnteredSearchInputs: Bool {
        let name = viewModel.merchantSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = viewModel.merchantSearchProviderFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty || !provider.isEmpty || viewModel.merchantSearchUseMapCenter
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
        .contentShape(.rect)
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

@available(iOS 17.0, *)
struct BTCMapEventsSheetView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bitcoin meetups and events from BTCMap", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                        Text("Selecting an event centers the map when coordinates are available.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Options") {
                    Toggle("Include past events", isOn: $viewModel.eventsIncludePast)
                        .onChange(of: viewModel.eventsIncludePast) { _, _ in
                            viewModel.loadBTCMapEvents()
                        }
                }

                if viewModel.eventsIsLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading events…")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let error = viewModel.eventsError, !error.isEmpty {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Events") {
                    if viewModel.eventsResults.isEmpty, !viewModel.eventsIsLoading {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No events found")
                                .font(.subheadline.weight(.semibold))
                            Text("Try enabling past events or refresh again later.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.eventsResults) { event in
                            Button {
                                viewModel.selectEvent(event)
                                dismiss()
                            } label: {
                                BTCMapEventRow(event: event)
                            }
                            .buttonStyle(.plain)
                            .disabled(event.lat == nil || event.lon == nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("BTCMap Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        viewModel.isEventsPresented = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        viewModel.loadBTCMapEvents()
                    }
                }
            }
        }
        .onAppear {
            if viewModel.eventsResults.isEmpty {
                viewModel.loadBTCMapEvents()
            }
        }
    }
}

@available(iOS 17.0, *)
private struct BTCMapEventRow: View {
    let event: V4EventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
                if event.lat != nil, event.lon != nil {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            if let starts = formattedEventDate(event.startsAt) {
                Text("Starts: \(starts)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let ends = formattedEventDate(event.endsAt) {
                Text("Ends: \(ends)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let website = event.website, !website.isEmpty {
                Text(website)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .opacity((event.lat == nil || event.lon == nil) ? 0.6 : 1.0)
    }

    private func formattedEventDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("1970-01-01") {
            return nil
        }
        if let date = btcMapISO8601WithFractional.date(from: raw) ?? btcMapISO8601Basic.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }
}

private let btcMapISO8601WithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let btcMapISO8601Basic: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

@available(iOS 17.0, *)
struct BTCMapAreasSheetView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Browse BTCMap regions and coverage areas", systemImage: "globe.americas")
                            .font(.subheadline.weight(.semibold))
                        Text("Selecting an area recenters the map and fetches an area element count.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Search Areas") {
                    TextField("City / region / country", text: $viewModel.areaBrowserQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if let selectedAreaID = viewModel.selectedAreaID {
                        HStack {
                            Text("Selected Area ID")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(selectedAreaID))
                        }
                        if let count = viewModel.selectedAreaElementCount {
                            HStack {
                                Text("Area Elements")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(count))
                            }
                        }
                    }
                }

                if viewModel.areaBrowserIsLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading BTCMap areas…")
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let error = viewModel.areaBrowserError, !error.isEmpty {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Areas") {
                    let areas = viewModel.filteredAreaBrowserAreas()
                    if areas.isEmpty, !viewModel.areaBrowserIsLoading {
                        Text("No areas found")
                            .foregroundColor(.secondary)
                    } else {
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
            .navigationTitle("BTCMap Areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        viewModel.isAreaBrowserPresented = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        viewModel.loadAreaBrowserAreas()
                    }
                }
            }
        }
        .onAppear {
            if viewModel.areaBrowserAreas.isEmpty {
                viewModel.loadAreaBrowserAreas()
            }
        }
    }
}

@available(iOS 17.0, *)
private struct BTCMapAreaRow: View {
    let area: V3AreaRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(area.displayName)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let adminLevel = area.tags?["admin_level"], !adminLevel.isEmpty {
                    areaBadge("admin \(adminLevel)", tint: .blue)
                }
                if let boundary = area.tags?["boundary"], !boundary.isEmpty {
                    areaBadge(boundary, tint: .green)
                }
                if let place = area.tags?["place"], !place.isEmpty {
                    areaBadge(place, tint: .orange)
                }
            }

            if let alias = area.urlAlias, !alias.isEmpty {
                Text(alias)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private func areaBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }
}
