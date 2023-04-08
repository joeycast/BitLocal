import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    var elements: [Element]
    var userLocation: CLLocation?
    
    var body: some View {
        NavigationView {
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

                
                // Accepts Bitcoin (details regarding on chain/lightning/contactless lightning not available)
                if (acceptsBitcoin(element: viewModel.element)) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                }
                
                // Accepts Bitcoin on Chain only
                else if (acceptsBitcoinOnChain(element: viewModel.element) && 
                    !acceptsLightning(element: viewModel.element) &&
                    !acceptsContactlessLightning(element: viewModel.element)) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                }
                // Accepts Bitcoin on Chain and Lightning
                else if (acceptsBitcoinOnChain(element: viewModel.element) && 
                         acceptsLightning(element: viewModel.element) &&
                         !acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                }
                // Accepts Bitcoin on Chain, Lightning, and Contactless Lightning
                else if (acceptsBitcoinOnChain(element: viewModel.element) && 
                         acceptsLightning(element: viewModel.element) &&
                         acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                    
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.orange)
                }
                // Accepts Lightning only
                else if (!acceptsBitcoinOnChain(element: viewModel.element) && 
                         acceptsLightning(element: viewModel.element) &&
                         !acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Accepts Lightning and Contactless Lightning
                else if (!acceptsBitcoinOnChain(element: viewModel.element) && 
                         acceptsLightning(element: viewModel.element) &&
                         acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.orange)
                }
                // Accepts Bitcoin on Chain and Contactless Lightning
                else if (acceptsBitcoinOnChain(element: viewModel.element) && 
                         !acceptsLightning(element: viewModel.element) &&
                         acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                    
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.orange)
                }
                // Accepts Contactless Lightning only
                else if (!acceptsBitcoinOnChain(element: viewModel.element) && 
                         !acceptsLightning(element: viewModel.element) &&
                         acceptsContactlessLightning(element: viewModel.element)) {
                    
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                }
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
