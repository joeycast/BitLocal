import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    @EnvironmentObject var viewModel: ContentViewModel
    
    var elements: [Element]
    var userLocation: CLLocation?
    
    private var sortedElements: [Element] {
        elements.sorted { (element1, element2) -> Bool in
            guard let distance1 = viewModel.distanceInMiles(element: element1),
                  let distance2 = viewModel.distanceInMiles(element: element2) else {
                return false
            }
            return distance1 < distance2
        }
    }
    
    var body: some View {
        NavigationView {
            if elements.isEmpty {
                Text("No locations found.")
                    .foregroundColor(.gray)
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(sortedElements.prefix(100), id: \.uuid) { element in
                    let cellViewModel = ElementCellViewModel(element: element, userLocation: viewModel.userLocation, viewModel: viewModel)
                    NavigationLink(destination: BusinessDetailView(element: element, userLocation: viewModel.userLocation, contentViewModel: viewModel), label: { 
                        ElementCell(viewModel: cellViewModel)
                            .onAppear {
                                cellViewModel.updateAddress()
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
                Text(viewModel.element.osmJSON?.tags?["name"] ?? viewModel.element.osmJSON?.tags?["operator"] ?? "Name not available")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
        
                // Distance from location
                distanceText
                    .font(.subheadline)
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
    }
    private var distanceText: some View {
        let distanceInMiles = viewModel.viewModel.distanceInMiles(element: viewModel.element)
        
        let formattedDistance: String? = {
            guard let distance = distanceInMiles else { return nil }
            
            if distance < 1 {
                return String(format: "%.2f", distance)
            } else if distance >= 1 && distance <= 50 {
                return String(format: "%.1f", distance)
            } else {
                return String(format: "%.0f", distance)
            }
        }()
        
        return Text(formattedDistance != nil ? "\(formattedDistance!) mi" : "")
            .opacity(formattedDistance != nil ? 1 : 0)
    }
}

class ElementCellViewModel: ObservableObject {
    
    let element: Element
    @Published var address: Address?
    @Published var userLocation: CLLocation? {
        didSet {
            print("User location set: \(userLocation?.coordinate.latitude ?? 0), \(userLocation?.coordinate.longitude ?? 0)")
        }
    }
    
    private let geocoder = CLGeocoder()
    
    let viewModel: ContentViewModel
    
    init(element: Element, userLocation: CLLocation?, viewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self.viewModel = viewModel
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
