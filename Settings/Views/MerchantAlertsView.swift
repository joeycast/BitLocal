import MapKit
import SwiftUI

@available(iOS 17.0, *)
struct MerchantAlertsView: View {
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingCityPicker = false
    @StateObject private var citySearchModel = MerchantAlertCitySearchModel()

    var body: some View {
        NavigationStack {
            List {
                statusSection
                subscriptionSection
                latestDigestSection
                setupSection
            }
            .navigationTitle("Merchant Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCityPicker) {
                MerchantAlertCityPickerView(model: citySearchModel) { choice in
                    Task {
                        await merchantAlertsManager.enableNotifications(for: choice)
                    }
                }
            }
            .task {
                await merchantAlertsManager.refreshStatus()
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack {
                Label(
                    merchantAlertsManager.isCloudKitAvailable ? "iCloud Ready" : "iCloud Required",
                    systemImage: merchantAlertsManager.isCloudKitAvailable ? "checkmark.icloud.fill" : "icloud.slash"
                )
                Spacer()
            }

            Text(merchantAlertsManager.cloudKitStatusSummary)
                .foregroundStyle(.secondary)

            if let notificationSettings = merchantAlertsManager.notificationSettings {
                Text(notificationStatusText(notificationSettings.authorizationStatus))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if merchantAlertsManager.notificationSettings?.authorizationStatus == .denied {
                Button("Open Notification Settings") {
                    merchantAlertsManager.openSystemSettings()
                }
            }
        }
    }

    private var subscriptionSection: some View {
        Section("City") {
            if let subscription = merchantAlertsManager.currentSubscription {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.displayName)
                        .font(.headline)
                    Text("Daily CloudKit digests are enabled for this city.")
                        .foregroundStyle(.secondary)
                }

                Button("Change City") {
                    citySearchModel.prepare()
                    showingCityPicker = true
                }

                Button("Turn Off Alerts", role: .destructive) {
                    Task {
                        await merchantAlertsManager.disableNotifications()
                    }
                }
            } else {
                Text("Choose a city and BitLocal will subscribe this device to daily new-merchant digests for that location.")
                    .foregroundStyle(.secondary)

                Button("Choose City") {
                    citySearchModel.prepare()
                    showingCityPicker = true
                }
                .disabled(!merchantAlertsManager.canEnableAlerts)
            }
        }
    }

    private var latestDigestSection: some View {
        Section("Latest Digest") {
            if let digest = merchantAlertsManager.lastDigest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(digest.cityDisplayName)
                        .font(.headline)
                    Text(digest.summaryLine)
                        .foregroundStyle(.secondary)
                    if let digestWindowEnd = digest.digestWindowEnd {
                        Text("Received \(digestWindowEnd.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Open Digest") {
                    merchantAlertsManager.presentLastDigest()
                }
            } else {
                Text("No city digests have been received on this device yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupSection: some View {
        Section("How It Works") {
            Text("BitLocal stores daily city digests in CloudKit’s public database, then uses a CloudKit query subscription to notify devices that follow a matching city.")
                .foregroundStyle(.secondary)
            Text("This version requires iCloud and standard notification permission. Users who are not signed in to iCloud can still browse the app, but they cannot enable merchant alerts.")
                .foregroundStyle(.secondary)
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Notifications are enabled for merchant alerts."
        case .provisional:
            return "Notifications are provisionally allowed."
        case .denied:
            return "Notifications are disabled for BitLocal."
        case .notDetermined:
            return "BitLocal has not requested notification permission yet."
        case .ephemeral:
            return "Notifications are temporarily available."
        @unknown default:
            return "Notification permission status is unknown."
        }
    }
}

@available(iOS 17.0, *)
struct MerchantAlertDigestView: View {
    let digest: CityDigest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("City") {
                    Text(digest.cityDisplayName)
                        .font(.headline)
                    Text("\(digest.merchantCount) new merchants")
                        .foregroundStyle(.secondary)
                }

                if !digest.topMerchantNames.isEmpty {
                    Section("Highlights") {
                        ForEach(digest.topMerchantNames, id: \.self) { name in
                            Text(name)
                        }
                    }
                }

                if !digest.merchantIDs.isEmpty {
                    Section("Merchant IDs") {
                        ForEach(digest.merchantIDs, id: \.self) { id in
                            Text(id)
                                .font(.footnote.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("City Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct MerchantAlertCityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MerchantAlertCitySearchModel
    @FocusState private var isSearchFieldFocused: Bool

    let onSelection: (MerchantAlertCityChoice) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search for a city", text: $model.searchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isSearchFieldFocused)
                }

                if model.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if !model.results.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { result in
                            Button {
                                Task {
                                    if let choice = await model.resolve(result) {
                                        onSelection(choice)
                                        dismiss()
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.isLoading {
                    Section {
                        Text("No locality-level matches found yet. Try a city name like Austin, Berlin, or Nashville.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                model.prepare()
                DispatchQueue.main.async {
                    isSearchFieldFocused = true
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private final class MerchantAlertCitySearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText = ""
    @Published private(set) var results: [MerchantAlertCitySearchResult] = []
    @Published private(set) var isLoading = false

    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var resolvedChoices: [String: MerchantAlertCityChoice] = [:]
    private var hasPrepared = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .query]

        Task { @MainActor in
            for await value in $searchText.values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                searchTask?.cancel()

                guard trimmed.count >= 2 else {
                    results = []
                    isLoading = false
                    continue
                }

                searchTask = Task { @MainActor in
                    isLoading = true
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    completer.queryFragment = trimmed
                }
            }
        }
    }

    func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        _ = completer.results.count
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(8)).map {
            MerchantAlertCitySearchResult(
                title: $0.title,
                subtitle: $0.subtitle,
                completion: $0
            )
        }
        isLoading = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Debug.log("Merchant alert city search failed: \(error.localizedDescription)")
        isLoading = false
    }

    func resolve(_ result: MerchantAlertCitySearchResult) async -> MerchantAlertCityChoice? {
        let cacheKey = "\(result.title)|\(result.subtitle)"
        if let cached = resolvedChoices[cacheKey] {
            return cached
        }

        let request = MKLocalSearch.Request(completion: result.completion)

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else { return nil }
            let placemark = mapItem.placemark

            let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name ?? result.title
            let region = placemark.administrativeArea ?? placemark.subAdministrativeArea ?? ""
            let country = placemark.country ?? ""

            guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let choice = MerchantAlertCityChoice(city: city, region: region, country: country)
            resolvedChoices[cacheKey] = choice
            return choice
        } catch {
            Debug.log("Merchant alert city resolve failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct MerchantAlertCitySearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}
