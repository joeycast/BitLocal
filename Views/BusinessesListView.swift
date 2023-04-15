import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    var elements: [Element]
    var userLocation: CLLocation?
    
    var body: some View {
        NavigationView {
            if elements.isEmpty {
                Text("No locations found.")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(elements.prefix(100), id: \.uuid) { element in
                    let viewModel = ElementCellViewModel(element: element, userLocation: userLocation)
                    NavigationLink(destination: BusinessDetailView(element: element, userLocation: userLocation), label: {
                        ElementCell(viewModel: viewModel)
                            .onAppear {
                                viewModel.updateAddress()
                            }
                    })
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ElementCell: View {
    
    @ObservedObject var viewModel: ElementCellViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            HStack {
                // Business Name
                Text(viewModel.element.osmJSON?.tags?["name"] ?? "name not available")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Distance from location
//                Text("2.1 Miles")
//                    .frame(maxWidth: 70, alignment: .trailing)
                if let userLocation = viewModel.userLocation,
                   let lat = viewModel.element.osmJSON?.lat,
                   let lon = viewModel.element.osmJSON?.lon {
                    let location = CLLocation(latitude: lat, longitude: lon)
                    let distanceInMeters = userLocation.distance(from: location)
                    let distanceInKilometers = distanceInMeters / 1000
                    Text("\(distanceInKilometers, specifier: "%.2f") km")
                        .font(.footnote)
                }
            }
            
            // Street number and name
            if let streetNumber = viewModel.address?.streetNumber {
                Text("\(streetNumber) \(viewModel.address?.streetName ?? "")".trimmingCharacters(in: .whitespaces))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.address?.streetName ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(viewModel.address?.cityOrTownName ?? ""), \(viewModel.address?.regionOrStateName ?? "") \(viewModel.address?.postalCode ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PaymentIcons(element: viewModel.element)
            }
        }
        .onAppear {
            viewModel.updateAddress()
        }
    }
}

class ElementCellViewModel: ObservableObject {
    
    let element: Element
    @Published var address: Address?
    @Published var userLocation: CLLocation?
    
    private let geocoder = CLGeocoder()
    
    init(element: Element, userLocation: CLLocation?) {
        self.element = element
        self.userLocation = userLocation
    }
    
    func updateAddress() {
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            if let placemark = placemarks?.first {
                let streetNumber = placemark.subThoroughfare ?? ""
                let streetName = placemark.thoroughfare ?? ""
                let cityOrTownName = placemark.locality ?? ""
                let postalCode = placemark.postalCode ?? ""
                let regionOrStateName = placemark.administrativeArea ?? ""
                let countryName = placemark.country ?? ""
                
                let address = Address(
                    streetNumber: streetNumber,
                    streetName: streetName,
                    cityOrTownName: cityOrTownName,
                    postalCode: postalCode,
                    regionOrStateName: regionOrStateName,
                    countryName: countryName
                )
                
                DispatchQueue.main.async {
                    self.address = address
                }
            }
        }
    }
}

// Payment icons
struct PaymentIcons: View {
    let element: Element
    
    var body: some View {
        HStack {
            if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundColor(.orange)
            }
            
            if acceptsLightning(element: element) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.orange)
            }
            
            if acceptsContactlessLightning(element: element) {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}
