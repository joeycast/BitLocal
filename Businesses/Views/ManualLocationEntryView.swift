import SwiftUI
import CoreLocation

@available(iOS 17.0, *)
struct ManualLocationEntryView: View {
    @Binding var submission: BusinessSubmission
    let onSave: (CLLocationCoordinate2D) -> Void
    let onCancel: () -> Void

    @State private var isGeocoding = false

    var body: some View {
        NavigationView {
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
                        ForEach(CountryList.allCountries, id: \.self) { country in
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
                    Button("cancel_button") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isGeocoding {
                        ProgressView()
                    } else {
                        Button("save_button") {
                            geocodeAddress()
                        }
                        .disabled(!isValid)
                    }
                }
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
        isGeocoding = true

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

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addressString) { placemarks, error in
            isGeocoding = false

            if let error = error {
                print("Geocoding error: \(error.localizedDescription)")
                // Still save even if geocoding fails, coordinates will be nil
                onSave(CLLocationCoordinate2D(latitude: 0, longitude: 0))
                return
            }

            if let coordinate = placemarks?.first?.location?.coordinate {
                onSave(coordinate)
            } else {
                // No coordinates found, but still save
                onSave(CLLocationCoordinate2D(latitude: 0, longitude: 0))
            }
        }
    }
}

struct CountryList {
    static let allCountries = [
        "Afghanistan", "Albania", "Algeria", "Andorra", "Angola", "Antigua and Barbuda",
        "Argentina", "Armenia", "Australia", "Austria", "Azerbaijan", "Bahamas", "Bahrain",
        "Bangladesh", "Barbados", "Belarus", "Belgium", "Belize", "Benin", "Bhutan",
        "Bolivia", "Bosnia and Herzegovina", "Botswana", "Brazil", "Brunei", "Bulgaria",
        "Burkina Faso", "Burundi", "Cabo Verde", "Cambodia", "Cameroon", "Canada",
        "Central African Republic", "Chad", "Chile", "China", "Colombia", "Comoros",
        "Congo", "Costa Rica", "Croatia", "Cuba", "Cyprus", "Czech Republic",
        "Democratic Republic of the Congo", "Denmark", "Djibouti", "Dominica",
        "Dominican Republic", "East Timor", "Ecuador", "Egypt", "El Salvador",
        "Equatorial Guinea", "Eritrea", "Estonia", "Eswatini", "Ethiopia", "Fiji",
        "Finland", "France", "Gabon", "Gambia", "Georgia", "Germany", "Ghana", "Greece",
        "Grenada", "Guatemala", "Guinea", "Guinea-Bissau", "Guyana", "Haiti", "Honduras",
        "Hungary", "Iceland", "India", "Indonesia", "Iran", "Iraq", "Ireland", "Israel",
        "Italy", "Ivory Coast", "Jamaica", "Japan", "Jordan", "Kazakhstan", "Kenya",
        "Kiribati", "Kosovo", "Kuwait", "Kyrgyzstan", "Laos", "Latvia", "Lebanon",
        "Lesotho", "Liberia", "Libya", "Liechtenstein", "Lithuania", "Luxembourg",
        "Madagascar", "Malawi", "Malaysia", "Maldives", "Mali", "Malta", "Marshall Islands",
        "Mauritania", "Mauritius", "Mexico", "Micronesia", "Moldova", "Monaco", "Mongolia",
        "Montenegro", "Morocco", "Mozambique", "Myanmar", "Namibia", "Nauru", "Nepal",
        "Netherlands", "New Zealand", "Nicaragua", "Niger", "Nigeria", "North Korea",
        "North Macedonia", "Norway", "Oman", "Pakistan", "Palau", "Palestine", "Panama",
        "Papua New Guinea", "Paraguay", "Peru", "Philippines", "Poland", "Portugal",
        "Qatar", "Romania", "Russia", "Rwanda", "Saint Kitts and Nevis", "Saint Lucia",
        "Saint Vincent and the Grenadines", "Samoa", "San Marino", "Sao Tome and Principe",
        "Saudi Arabia", "Senegal", "Serbia", "Seychelles", "Sierra Leone", "Singapore",
        "Slovakia", "Slovenia", "Solomon Islands", "Somalia", "South Africa", "South Korea",
        "South Sudan", "Spain", "Sri Lanka", "Sudan", "Suriname", "Sweden", "Switzerland",
        "Syria", "Taiwan", "Tajikistan", "Tanzania", "Thailand", "Togo", "Tonga",
        "Trinidad and Tobago", "Tunisia", "Turkey", "Turkmenistan", "Tuvalu", "Uganda",
        "Ukraine", "United Arab Emirates", "United Kingdom", "United States", "Uruguay",
        "Uzbekistan", "Vanuatu", "Vatican City", "Venezuela", "Vietnam", "Yemen", "Zambia",
        "Zimbabwe"
    ]
}
