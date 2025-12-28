import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct LocationSearchView: View {
    @Binding var submission: BusinessSubmission

    @StateObject private var searchViewModel = LocationSearchViewModel()
    @State private var showingManualEntry = false
    @State private var mapType: MKMapType = .standard
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
    }

    private var searchView: some View {
        ZStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search for location...", text: $searchViewModel.searchText)
                            .autocapitalization(.words)
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
                            Button(action: {
                                searchViewModel.selectLocation(result) { location in
                                    selectedLocation = location
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("search_results_header")
                    }
                }

                Section {
                    Button(action: { showingManualEntry = true }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text("manual_entry_button")
                        }
                    }
                } footer: {
                    Text("manual_entry_footer")
                }

            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 96)
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
                            .foregroundColor(.secondary)
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
                            searchViewModel.reverseGeocode(coordinate: newCoordinate) { location in
                                selectedLocation = location
                            }
                        }
                    )
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .overlay(alignment: .bottomTrailing) {
                        Button(action: {
                            mapType = (mapType == .standard) ? .hybrid : .standard
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .shadow(radius: 2)
                                Image(mapType == .standard ? "globe-hemisphere-west-fill" : "map-trifold-fill")
                                    .aboutIconStyle(size: 16, color: .white)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
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
                    Button(action: {
                        selectedLocation = nil
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("search_different_location")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 96)
        }
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
@available(iOS 17.0, *)
class LocationSearchViewModel: NSObject, ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false

    private let searchCompleter = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?

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

        // Debounced search
        Task { @MainActor in
            for await searchText in $searchText.values {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard !Task.isCancelled else { return }
                    await performSearch(searchText)
                }
            }
        }
    }

    @MainActor
    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchCompleter.queryFragment = query
    }

    func selectLocation(_ result: SearchResult, completion: @escaping (SearchLocation) -> Void) {
        isSearching = true

        let searchRequest = MKLocalSearch.Request(completion: result.completion)
        let search = MKLocalSearch(request: searchRequest)

        search.start { [weak self] response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isSearching = false

                guard let mapItem = response?.mapItems.first else { return }

                let placemark = mapItem.placemark
                var addressComponents = BusinessSubmission()

                addressComponents.streetNumber = placemark.subThoroughfare ?? ""
                addressComponents.streetName = placemark.thoroughfare ?? ""
                addressComponents.city = placemark.locality ?? ""
                addressComponents.stateProvince = placemark.administrativeArea ?? ""
                addressComponents.country = placemark.country ?? ""
                addressComponents.postalCode = placemark.postalCode ?? ""
                self.applyMapItemDetails(mapItem, to: &addressComponents)

                let location = SearchLocation(
                    title: mapItem.name ?? result.title,
                    subtitle: result.subtitle,
                    coordinate: placemark.coordinate,
                    addressComponents: addressComponents
                )

                completion(location)
            }
        }
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (SearchLocation) -> Void) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first else { return }

            DispatchQueue.main.async {
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
@available(iOS 17.0, *)
extension LocationSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.searchResults = completer.results.map { completion in
                SearchResult(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    completion: completion
                )
            }
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
    }
}
