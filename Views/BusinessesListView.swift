import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    @EnvironmentObject var viewModel: ContentViewModel
    
    let maxListResults = 25
    
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
                List {
                    Section(footer: footerView) {
                        ForEach(sortedElements.prefix(maxListResults), id: \.uuid) { element in
                            let cellViewModel = ElementCellViewModel(element: element, userLocation: viewModel.userLocation, viewModel: viewModel)
                            NavigationLink(destination: BusinessDetailView(element: element, userLocation: viewModel.userLocation, contentViewModel: viewModel), label: { 
                                ElementCell(viewModel: cellViewModel)
                            })
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(UUID())
            }
        }
    }
    
    private var footerView: some View {
        Group {
            if sortedElements.count > maxListResults {
                VStack {
                    Text("\(sortedElements.count) locations returned on the map. The top \(min(sortedElements.count, maxListResults)) are displayed in the list.")
                }
            } else {
                Text("Showing \(sortedElements.count) of \(sortedElements.count) locations.")
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }
}

struct ElementCell: View {
    
    @ObservedObject var viewModel: ElementCellViewModel
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            HStack {
                // Business Name
                Text(viewModel.element.osmJSON?.tags?.name ?? viewModel.element.osmJSON?.tags?.operator ?? "Name not available")
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
                Text("\(viewModel.address?.cityOrTownName ?? "")\(viewModel.address?.cityOrTownName != nil && viewModel.address?.cityOrTownName != "" ? ", " : "")\(viewModel.address?.regionOrStateName ?? "") \(viewModel.address?.postalCode ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                PaymentIcons(element: viewModel.element)
            }
        }
        .onAppear {
            viewModel.onCellAppear()
        }
        .onChange(of: viewModel.viewModel.userLocation) { _ in
            viewModel.onCellAppear()
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
            .padding(.trailing, 3)
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
    
    static var geocodingCache: [String: Address] = [:]
    
    private let geocoder = CLGeocoder()
    let viewModel: ContentViewModel
    
    init(element: Element, userLocation: CLLocation?, viewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self.viewModel = viewModel
        self.address = viewModel.geocodingCache.getValue(forKey: "\(element.osmJSON?.lat ?? 0),\(element.osmJSON?.lon ?? 0)")
    }
    
    func onCellAppear() {
        if address == nil {
            updateAddress()
        }
    }
    
    private func getCachedAddress() -> Address? {
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return nil
        }
        let cacheKey = "\(lat),\(lon)"
        return viewModel.geocodingCache.getValue(forKey: cacheKey)
    }
    
    private func setCachedAddress(_ address: Address) {
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return
        }
        let cacheKey = "\(lat),\(lon)"
        viewModel.geocodingCache.setValue(address, forKey: cacheKey)
    }
    
    func updateAddress() {
        // Check if the address is already cached
        if let cachedAddress = getCachedAddress() {
            self.address = cachedAddress
            return
        }
        
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return
        }
        
        // Check the cache before making a geocoding request
        let cacheKey = "\(lat),\(lon)"
        if let cachedAddress = ElementCellViewModel.geocodingCache[cacheKey] {
            self.address = cachedAddress
            return
        }
        
        let location = CLLocation(latitude: lat, longitude: lon)
        
        // Throttle geocoding requests
        DispatchQueue.global(qos: .userInitiated).async {
            self.viewModel.geocoder.reverseGeocode(location: location) { placemark in
                if let placemark = placemark {
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
                        ElementCellViewModel.geocodingCache[cacheKey] = address // Update the cache with the new geocoded result
                    }
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

class Geocoder {
    private let geocoder = CLGeocoder()
    private let semaphore: DispatchSemaphore
    
    init(maxConcurrentRequests: Int = 1) {
        semaphore = DispatchSemaphore(value: maxConcurrentRequests)
    }
    
    func reverseGeocode(location: CLLocation, completion: @escaping (CLPlacemark?) -> Void) {
        semaphore.wait() // Wait for a free slot
        
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            defer {
                self.semaphore.signal() // Release the slot
            }
            
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            completion(placemark)
        }
    }
}
