import SwiftUI
import CoreLocation

struct ManualLocationEntryView: View {
    @Environment(\.locale) private var locale
    @Binding var submission: BusinessSubmission
    let onSave: (CLLocationCoordinate2D) -> Void
    let onCancel: () -> Void

    @State private var isGeocoding = false
    @State private var geocodingErrorMessage: String?
    @State private var showingGeocodingError = false
    @State private var geocodingTask: Task<Void, Never>?

    private var localizedCountries: [String] {
        CountryList.localizedCountries(for: locale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $submission.businessName) {
                        Text("business_name_label")
                    }
                } header: {
                    Text("business_name_label")
                }

                Section {
                    HStack(spacing: 8) {
                        TextField(text: $submission.streetNumber) {
                            Text("street_number_label")
                        }
                        .keyboardType(.numbersAndPunctuation)
                        .frame(maxWidth: 80)

                        TextField(text: $submission.streetName) {
                            Text("street_name_label")
                        }
                    }

                    TextField(text: $submission.city) {
                        Text("city_label")
                    }

                    TextField(text: $submission.stateProvince) {
                        Text("state_province_label")
                    }

                    Picker(selection: $submission.country) {
                        Text("Select Country").tag("")
                        ForEach(localizedCountries, id: \.self) { country in
                            Text(country).tag(country)
                        }
                    } label: {
                        Text("country_label")
                    }

                    TextField(text: $submission.postalCode) {
                        Text("postal_code_label")
                    }
                    .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("address_section_header")
                }
            }
            .navigationTitle("manual_entry_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isGeocoding {
                        ProgressView()
                    } else {
                        Button("save_button", action: geocodeAddress)
                            .disabled(!isValid)
                    }
                }
            }
            .alert("Unable to Locate Address", isPresented: $showingGeocodingError) {
                Button("Try Again", action: geocodeAddress)
                Button("cancel_button", role: .cancel) { }
            } message: {
                if let geocodingErrorMessage {
                    Text(geocodingErrorMessage)
                }
            }
            .onDisappear {
                geocodingTask?.cancel()
            }
        }
    }

    private var isValid: Bool {
        !submission.businessName.isEmpty &&
        !submission.streetNumber.isEmpty &&
        !submission.streetName.isEmpty &&
        !submission.city.isEmpty &&
        !submission.stateProvince.isEmpty &&
        !submission.country.isEmpty
    }

    private func geocodeAddress() {
        geocodingTask?.cancel()
        isGeocoding = true
        geocodingErrorMessage = nil

        // Construct full address string
        let addressComponents = [
            submission.streetNumber,
            submission.streetName,
            submission.city,
            submission.stateProvince,
            submission.postalCode,
            submission.country
        ].filter { !$0.isEmpty }

        let addressString = addressComponents.joined(separator: ", ")

        geocodingTask = Task {
            defer { isGeocoding = false }
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(addressString)
                guard !Task.isCancelled else { return }

                if let coordinate = placemarks.first?.location?.coordinate {
                    onSave(coordinate)
                } else {
                    geocodingErrorMessage = String(
                        localized: "We couldn’t find coordinates for this address. Please double-check the address and try again."
                    )
                    showingGeocodingError = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                geocodingErrorMessage = error.localizedDescription
                showingGeocodingError = true
            }
        }
    }
}

enum CountryList {
    static var allCountries: [String] {
        localizedCountries(for: .current)
    }

    static func localizedCountries(for locale: Locale) -> [String] {
        let names = Locale.Region.isoRegions.compactMap { region -> String? in
            let code = region.identifier
            guard code.count == 2,
                  code.allSatisfy(\.isLetter),
                  region.subRegions.isEmpty else {
                return nil
            }
            return locale.localizedString(forRegionCode: code)
        }
        return Array(Set(names)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
