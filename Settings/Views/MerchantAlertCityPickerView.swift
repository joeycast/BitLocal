import CoreLocation
import SwiftUI

struct MerchantAlertCityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var contentViewModel: ContentViewModel
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @Binding var currentDetent: PresentationDetent
    @StateObject private var model = MerchantAlertCityPickerModel()

    let onSelection: (MerchantAlertCityChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                    headerCard

                    if model.isShowingSearchResults {
                        searchResultsSection
                    } else {
                        browseSections
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .clearNavigationContainerBackgroundIfAvailable()
        .background(shouldHideSheetBackground ? Color.clear : Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Choose City")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if isLocationAuthorized, contentViewModel.userLocation == nil {
                contentViewModel.requestWhenInUseLocationPermission()
            }
        }
        .task(id: contextRefreshID) {
            await model.syncContext(
                userLocation: contentViewModel.userLocation,
                authorizationStatus: contentViewModel.locationManager.authorizationStatus,
                activeSubscription: merchantAlertsManager.currentSubscription
            )
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
        .cityPickerSearchBackground(glassy: shouldUseGlassyBackground)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a city")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("We’ll send a notification when new merchants start accepting Bitcoin there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var browseSections: some View {
        if model.isLoadingBrowseContent {
            loadingState("Finding cities near you…")
        } else {
            if let activeAlertCity = model.activeAlertCity {
                sectionHeader("Current Selection")
                selectionCard(
                    title: activeAlertCity.city,
                    subtitle: activeAlertCity.displayName,
                    badge: "Already Selected",
                    systemImage: "bell.badge.fill",
                    accent: .orange,
                    choice: activeAlertCity
                )
            }

            if let currentLocationCity = model.currentLocationCity {
                sectionHeader("Near You")
                selectionCard(
                    title: currentLocationCity.choice.city,
                    subtitle: currentLocationCity.displayName,
                    badge: "Current Location",
                    systemImage: "location.fill",
                    accent: .blue,
                    choice: currentLocationCity.choice
                )
            }

            if !model.recommendedCities.isEmpty {
                sectionHeader("Other Popular Cities")

                ForEach(model.recommendedCities) { result in
                    selectionCard(
                        title: result.city,
                        subtitle: result.displayName,
                        badge: nil,
                        systemImage: "sparkles",
                        accent: .accentColor,
                        choice: result.choice
                    )
                }
            }

            if model.shouldShowBrowseEmptyState {
                ContentUnavailableView(
                    "Search for a City",
                    systemImage: "location.magnifyingglass",
                    description: Text("Turn on location to pin your current city, or search any city worldwide.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if model.isLoading && model.results.isEmpty {
            loadingState("Searching cities…")
        } else if model.results.isEmpty {
            ContentUnavailableView(
                "No City Matches",
                systemImage: "magnifyingglass",
                description: Text("Try a city name, state, or country.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else {
            sectionHeader("Search Results")

            ForEach(model.results) { result in
                selectionCard(
                    title: result.city,
                    subtitle: result.displayName,
                    badge: nil,
                    systemImage: "mappin.circle.fill",
                    accent: .accentColor,
                    choice: result.choice
                )
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 6)
    }

    private func selectionCard(
        title: String,
        subtitle: String,
        badge: String?,
        systemImage: String,
        accent: Color,
        choice: MerchantAlertCityChoice
    ) -> some View {
        Button {
            onSelection(choice)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, badge == nil ? 0 : 132)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("Use this city")
                            .font(.footnote.weight(.semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(accent)
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cityPickerResultBackground(glassy: shouldUseGlassyBackground)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private func loadingState(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.horizontal, 16)
    }

    private var contextRefreshID: String {
        let locationKey = contentViewModel.userLocation.map {
            ReverseGeocodingSpatialKey.key(for: $0.coordinate, precision: 3)
        } ?? "no-location"

        let subscriptionKey = merchantAlertsManager.currentSubscription?.locationID ?? "no-subscription"
        return "\(contentViewModel.locationManager.authorizationStatus.rawValue)|\(locationKey)|\(subscriptionKey)"
    }

    private var isLocationAuthorized: Bool {
        let status = contentViewModel.locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private var shouldHideSheetBackground: Bool {
        currentDetent != .large
    }

    private var shouldUseGlassyBackground: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return currentDetent != .large
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
    @Published private(set) var currentLocationCity: CityPickerContextCity?
    @Published private(set) var activeAlertCity: MerchantAlertCityChoice?
    @Published private(set) var recommendedCities: [CitySearchResult] = []
    @Published private(set) var isLoadingBrowseContent = false

    private var searchTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private let store = CityIndexStore.shared
    private var latestLocationKey: String?

    var isShowingSearchResults: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var shouldShowBrowseEmptyState: Bool {
        currentLocationCity == nil && activeAlertCity == nil && recommendedCities.isEmpty
    }

    func syncContext(
        userLocation: CLLocation?,
        authorizationStatus: CLAuthorizationStatus,
        activeSubscription: CitySubscription?
    ) async {
        activeAlertCity = activeSubscription.map {
            MerchantAlertCityChoice(
                locationID: $0.locationID,
                city: $0.city,
                region: $0.region,
                country: $0.country
            )
        }

        await store.preloadIfNeeded()
        await refreshCurrentLocation(userLocation: userLocation, authorizationStatus: authorizationStatus)

        if !isShowingSearchResults {
            await loadBrowseRecommendations()
        }
    }

    private func scheduleSearch(for rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        locationTask?.cancel()

        if query.count < 2 {
            results = []
            isLoading = false
            isLoadingBrowseContent = true

            searchTask = Task {
                await store.preloadIfNeeded()
                guard !Task.isCancelled else { return }
                await loadBrowseRecommendations()
            }
            return
        }

        isLoading = true
        isLoadingBrowseContent = false

        searchTask = Task {
            await store.preloadIfNeeded()
            guard !Task.isCancelled else { return }

            let nextResults = await store.search(query: query, limit: 30)

            guard !Task.isCancelled else { return }
            results = nextResults
            isLoading = false
        }
    }

    private func refreshCurrentLocation(
        userLocation: CLLocation?,
        authorizationStatus: CLAuthorizationStatus
    ) async {
        let isAuthorized = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse

        guard isAuthorized else {
            currentLocationCity = nil
            latestLocationKey = nil
            return
        }

        guard let userLocation else {
            currentLocationCity = nil
            return
        }

        let locationKey = ReverseGeocodingSpatialKey.key(for: userLocation.coordinate, precision: 3)
        guard locationKey != latestLocationKey else { return }

        latestLocationKey = locationKey
        isLoadingBrowseContent = true
        locationTask?.cancel()

        locationTask = Task {
            let placemark = await reverseGeocode(userLocation, requestKey: locationKey)
            guard !Task.isCancelled else { return }

            let city = placemark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let region = placemark?.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let country = placemark?.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !city.isEmpty else {
                currentLocationCity = nil
                isLoadingBrowseContent = false
                return
            }

            let choice = MerchantAlertCityChoice(
                locationID: "legacy:\(MerchantAlertsCityNormalizer.cityKey(city: city, region: region, country: country))",
                city: city,
                region: region,
                country: country
            )
            let matchedResult = await store.result(forCityKey: choice.cityKey)
            guard !Task.isCancelled else { return }

            let resolvedLocationCity = CityPickerContextCity(
                choice: matchedResult?.choice ?? choice,
                displayName: matchedResult?.displayName ?? choice.displayName
            )

            if resolvedLocationCity.choice.locationID == activeAlertCity?.locationID {
                currentLocationCity = nil
            } else {
                currentLocationCity = resolvedLocationCity
            }
            isLoadingBrowseContent = false
        }

        await locationTask?.value
    }

    private func loadBrowseRecommendations() async {
        defer { isLoadingBrowseContent = false }

        let anchor = currentLocationCity?.choice ?? activeAlertCity
        guard let anchor else {
            recommendedCities = []
            return
        }

        var excludedKeys: Set<String> = []
        if let currentLocationCity {
            excludedKeys.insert(currentLocationCity.choice.locationID)
        }
        if let activeAlertCity {
            excludedKeys.insert(activeAlertCity.locationID)
        }

        recommendedCities = await store.recommendedCities(
            near: anchor,
            excluding: excludedKeys,
            limit: 10
        )
    }

    private func reverseGeocode(_ location: CLLocation, requestKey: String) async -> CLPlacemark? {
        await withCheckedContinuation { continuation in
            Geocoder.shared.reverseGeocode(location: location, requestKey: requestKey) { placemark in
                continuation.resume(returning: placemark)
            }
        }
    }
}

struct CityPickerContextCity: Equatable {
    let choice: MerchantAlertCityChoice
    let displayName: String
}
