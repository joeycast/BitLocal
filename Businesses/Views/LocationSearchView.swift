import MapKit
import Observation
import SwiftUI

struct LocationSearchView: View {
    @Binding var submission: BusinessSubmission

    @State private var searchViewModel = LocationSearchViewModel()
    @State private var showingManualEntry = false
    @State private var mapType: MKMapType = .hybrid
    @State private var selectedLocation: SearchLocation? {
        didSet {
            // Automatically save location data to submission when selected
            if let location = selectedLocation {
                submission.businessName = location.title
                submission.streetNumber = location.addressComponents.streetNumber
                submission.streetName = location.addressComponents.streetName
                submission.city = location.addressComponents.city
                submission.stateProvince = location.addressComponents.stateProvince
                submission.country = location.addressComponents.country
                submission.postalCode = location.addressComponents.postalCode
                submission.latitude = location.coordinate.latitude
                submission.longitude = location.coordinate.longitude

                if submission.phoneNumber.isEmpty, !location.addressComponents.phoneNumber.isEmpty {
                    submission.phoneNumber = location.addressComponents.phoneNumber
                    submission.phoneCountryCode = location.addressComponents.phoneCountryCode
                }
                if submission.website.isEmpty, !location.addressComponents.website.isEmpty {
                    submission.website = location.addressComponents.website
                }
                if submission.osmFeatureType == .unset, location.addressComponents.osmFeatureType != .unset {
                    submission.osmFeatureType = location.addressComponents.osmFeatureType
                }
                if !submission.weeklyHours.hasAnyOpen, location.addressComponents.weeklyHours.hasAnyOpen {
                    submission.weeklyHours = location.addressComponents.weeklyHours
                }
            }
        }
    }

    var body: some View {
        ZStack {
            if selectedLocation == nil {
                searchView
            } else {
                locationDetailView
            }
        }
        .onDisappear {
            searchViewModel.cancelPendingSearch()
        }
        .alert("Search Error", isPresented: $searchViewModel.showingSearchError) {
        } message: {
            if let errorMessage = searchViewModel.searchErrorMessage {
                Text(errorMessage)
            }
        }
    }

    private var searchView: some View {
        ZStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search for location...", text: $searchViewModel.searchText)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("step_location_header")
                }

                if searchViewModel.isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if !searchViewModel.searchResults.isEmpty {
                    Section {
                        ForEach(searchViewModel.searchResults) { result in
                            Button {
                                Task {
                                    if let location = await searchViewModel.selectLocation(result) {
                                        selectedLocation = location
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("search_results_header")
                    }
                }

                Section {
                    Button {
                        showingManualEntry = true
                    } label: {
                        Label("manual_entry_button", systemImage: "keyboard")
                    }
                } footer: {
                    Text("manual_entry_footer")
                }

            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualLocationEntryView(
                submission: $submission,
                onSave: { coordinate in
                    showingManualEntry = false
                    // Convert to SearchLocation for preview
                    selectedLocation = SearchLocation(
                        title: submission.businessName.isEmpty ? "Manual Entry" : submission.businessName,
                        subtitle: "\(submission.city), \(submission.stateProvince)",
                        coordinate: coordinate,
                        addressComponents: submission
                    )
                },
                onCancel: { showingManualEntry = false }
            )
        }
    }

    private var locationDetailView: some View {
        ZStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedLocation?.title ?? "")
                            .font(.headline)
                        Text(selectedLocation?.subtitle ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("selected_location_header")
                }

                Section {
                    MapPreviewView(
                        coordinate: selectedLocation?.coordinate ?? CLLocationCoordinate2D(),
                        mapType: mapType,
                        onCoordinateChange: { newCoordinate in
                            submission.latitude = newCoordinate.latitude
                            submission.longitude = newCoordinate.longitude
                            if let currentLocation = selectedLocation {
                                selectedLocation = SearchLocation(
                                    title: currentLocation.title,
                                    subtitle: currentLocation.subtitle,
                                    coordinate: newCoordinate,
                                    addressComponents: currentLocation.addressComponents
                                )
                            }
                        }
                    )
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .overlay(alignment: .bottomTrailing) {
                        Button(
                            mapType == .standard ? "Switch to Hybrid Map" : "Switch to Standard Map",
                            systemImage: mapType == .standard ? "globe.americas.fill" : "map.fill"
                        ) {
                            mapType = (mapType == .standard) ? .hybrid : .standard
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(MapTypeToggleButtonStyle())
                        .padding(10)
                    }
                } header: {
                    Text("map_preview_header")
                } footer: {
                    Text("map_preview_footer")
                }

                Section {
                    if let location = selectedLocation {
                        LabeledContent("street_number_label", value: location.addressComponents.streetNumber)
                        LabeledContent("street_name_label", value: location.addressComponents.streetName)
                        LabeledContent("city_label", value: location.addressComponents.city)
                        LabeledContent("state_province_label", value: location.addressComponents.stateProvince)
                        LabeledContent("country_label", value: location.addressComponents.country)
                        if !location.addressComponents.postalCode.isEmpty {
                            LabeledContent("postal_code_label", value: location.addressComponents.postalCode)
                        }
                    }
                } header: {
                    Text("address_section_header")
                }

                Section {
                    Button {
                        selectedLocation = nil
                    } label: {
                        Label("search_different_location", systemImage: "magnifyingglass")
                    }
                }
            }
        }
    }
}

private struct MapTypeToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .background(.accent, in: .circle)
            .shadow(radius: 2)
            .contentShape(.circle)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Search Location Model
struct SearchLocation: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let addressComponents: BusinessSubmission
}

// MARK: - Search Result Model
struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}

// MARK: - Location Search ViewModel
@MainActor
@Observable
final class LocationSearchViewModel: NSObject {
    var searchText = "" {
        didSet {
            scheduleSearch(for: searchText)
        }
    }
    var searchResults: [SearchResult] = []
    var isSearching = false
    var searchErrorMessage: String?
    var showingSearchError = false

    @ObservationIgnored private let searchCompleter = MKLocalSearchCompleter()
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?

    override init() {
        super.init()
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.pointOfInterest]
        searchCompleter.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .cafe, .restaurant, .store, .bakery, .brewery, .winery,
            .foodMarket, .museum, .theater, .movieTheater, .bank,
            .atm, .hotel, .laundry, .pharmacy, .library, .school,
            .stadium, .park, .campground, .fitnessCenter, .nightlife,
            .gasStation, .evCharger, .publicTransport, .parking
        ])
    }

    func cancelPendingSearch() {
        searchDebounceTask?.cancel()
    }

    private func scheduleSearch(for query: String) {
        searchDebounceTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.performSearch(query)
        }
    }

    private func performSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchCompleter.queryFragment = query
    }

    func selectLocation(_ result: SearchResult) async -> SearchLocation? {
        isSearching = true
        searchErrorMessage = nil
        defer { isSearching = false }

        let searchRequest = MKLocalSearch.Request(completion: result.completion)
        let search = MKLocalSearch(request: searchRequest)

        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first else {
                searchErrorMessage = String(localized: "Unable to find details for the selected location.")
                showingSearchError = true
                return nil
            }

            let placemark = mapItem.placemark
            var addressComponents = BusinessSubmission()

            addressComponents.streetNumber = placemark.subThoroughfare ?? ""
            addressComponents.streetName = placemark.thoroughfare ?? ""
            addressComponents.city = placemark.locality ?? ""
            addressComponents.stateProvince = placemark.administrativeArea ?? ""
            addressComponents.country = placemark.country ?? ""
            addressComponents.postalCode = placemark.postalCode ?? ""
            applyMapItemDetails(mapItem, to: &addressComponents)

            return SearchLocation(
                title: mapItem.name ?? result.title,
                subtitle: result.subtitle,
                coordinate: placemark.coordinate,
                addressComponents: addressComponents
            )
        } catch {
            if !Task.isCancelled {
                searchErrorMessage = error.localizedDescription
                showingSearchError = true
            }
            return nil
        }
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (SearchLocation) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let requestKey = "location-search:\(ReverseGeocodingSpatialKey.key(for: coordinate))"

        Geocoder.shared.reverseGeocode(location: location, requestKey: requestKey) { placemark in
            guard let placemark else { return }

            Task { @MainActor in
                var addressComponents = BusinessSubmission()

                addressComponents.streetNumber = placemark.subThoroughfare ?? ""
                addressComponents.streetName = placemark.thoroughfare ?? ""
                addressComponents.city = placemark.locality ?? ""
                addressComponents.stateProvince = placemark.administrativeArea ?? ""
                addressComponents.country = placemark.country ?? ""
                addressComponents.postalCode = placemark.postalCode ?? ""

                let searchLocation = SearchLocation(
                    title: placemark.name ?? "Dropped Pin",
                    subtitle: [placemark.locality, placemark.administrativeArea].compactMap { $0 }.joined(separator: ", "),
                    coordinate: coordinate,
                    addressComponents: addressComponents
                )

                completion(searchLocation)
            }
        }
    }

    private func applyMapItemDetails(_ mapItem: MKMapItem, to submission: inout BusinessSubmission) {
        if let phoneNumber = mapItem.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phoneNumber.isEmpty {
            applyPhoneNumber(phoneNumber, to: &submission)
        }

        if let url = mapItem.url?.absoluteString, !url.isEmpty {
            submission.website = url
        }

        if submission.osmFeatureType == .unset,
           let category = mapItem.pointOfInterestCategory,
           let featureType = osmFeatureType(from: category) {
            submission.osmFeatureType = featureType
        }
    }

    private func applyPhoneNumber(_ phoneNumber: String, to submission: inout BusinessSubmission) {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("+") else {
            submission.phoneNumber = trimmed
            return
        }

        let digits = trimmed.dropFirst().prefix { $0.isNumber }
        if !digits.isEmpty {
            submission.phoneCountryCode = "+\(digits)"
            let remainingIndex = trimmed.index(trimmed.startIndex, offsetBy: digits.count + 1)
            let remaining = trimmed[remainingIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            submission.phoneNumber = remaining.isEmpty ? trimmed : String(remaining)
        } else {
            submission.phoneNumber = trimmed
        }
    }

    private func osmFeatureType(from category: MKPointOfInterestCategory) -> OSMFeatureType? {
        switch category {
        case .cafe: return .amenityCafe
        case .restaurant: return .amenityRestaurant
        case .bakery: return .shopBakery
        case .brewery: return .craftBrewery
        case .winery: return .craftWinery
        case .foodMarket: return .shopSupermarket
        case .store: return .shopConvenience
        case .museum: return .tourismMuseum
        case .theater: return .amenityTheatre
        case .movieTheater: return .amenityCinema
        case .bank: return .amenityBank
        case .atm: return .amenityAtm
        case .hotel: return .tourismHotel
        case .laundry: return .shopLaundry
        case .pharmacy: return .amenityPharmacy
        case .library: return .amenityLibrary
        case .school: return .amenitySchool
        case .stadium: return .leisureStadium
        case .park: return .leisurePark
        case .campground: return .tourismCampSite
        case .fitnessCenter: return .leisureFitnessCentre
        case .nightlife: return .amenityNightclub
        case .gasStation: return .amenityFuel
        case .evCharger: return .amenityChargingStation
        case .parking: return .amenityParking
        default:
            return nil
        }
    }

}

// MARK: - MKLocalSearchCompleterDelegate
extension LocationSearchViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.searchResults = self.searchCompleter.results.map { completion in
                SearchResult(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    completion: completion
                )
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.searchErrorMessage = message
            self?.showingSearchError = true
        }
    }
}
