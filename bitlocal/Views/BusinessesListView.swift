// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine

@available(iOS 16.4, *)
struct BusinessesListView: View {
    
    @EnvironmentObject var viewModel: ContentViewModel
    
    let maxListResults = 25
    
    var elements: [Element]
    var userLocation: CLLocation?
    
    @State private var cellViewModels: [String: ElementCellViewModel] = [:] // Keyed by Element ID
    
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
        // In BusinessesListView
        if elements.isEmpty {
            Text("No locations found.")
                .foregroundColor(.gray)
                .font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            List {
                Section(footer: footerView) {
                    ForEach(sortedElements.prefix(maxListResults), id: \.id) { element in
                        let cellViewModel = self.cellViewModel(for: element)
                        NavigationLink(value: element) {
                            ElementCell(viewModel: cellViewModel)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .navigationBarTitleDisplayMode(.inline)
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.path) { newPath in
                if let element = newPath.last {
                    // Delay zoom until after navigation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        viewModel.zoomToElement(element)
                    }
                }
            }
        }
    }
    
    private func cellViewModel(for element: Element) -> ElementCellViewModel {
        if let vm = viewModel.cellViewModels[element.id] {
            return vm
        } else {
            let newVM = ElementCellViewModel(element: element, userLocation: viewModel.userLocation, viewModel: viewModel)
            viewModel.cellViewModels[element.id] = newVM
            return newVM
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

@available(iOS 16.4, *)
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

@available(iOS 16.4, *)
class ElementCellViewModel: ObservableObject {
    
    let element: Element
    let viewModel: ContentViewModel
    @Published var address: Address?
    @Published var userLocation: CLLocation? {
        didSet {
            print("User location set: \(userLocation?.coordinate.latitude ?? 0), \(userLocation?.coordinate.longitude ?? 0)")
        }
    }
    static var geocodingCache: [String: Address] = [:]
    private let geocoder = CLGeocoder()
    private var userLocationCancellable: AnyCancellable?
    
    init(element: Element, userLocation: CLLocation?, viewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self.viewModel = viewModel
        
        // Observe changes to userLocation if needed
        self.userLocationCancellable = viewModel.$userLocation.sink { [weak self] newLocation in
            self?.userLocation = newLocation
            // Perform any updates needed when userLocation changes
        }
        
        // Attempt to retrieve cached address
        if let cachedAddress = ElementCellViewModel.geocodingCache[addressCacheKey] {
            self.address = cachedAddress
        } else {
            // Start geocoding immediately
            self.updateAddress()
        }
    }
    
    deinit {
        // Cancel the subscription when the view model is deallocated
        userLocationCancellable?.cancel()
    }
    
    func onCellAppear() {
        if address == nil {
            updateAddress()
        }
    }
    
    private var addressCacheKey: String {
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return ""
        }
        return "\(lat),\(lon)"
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
        if let cachedAddress = ElementCellViewModel.geocodingCache[addressCacheKey] {
            self.address = cachedAddress
            return
        }
        
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else { return }
        let location = CLLocation(latitude: lat, longitude: lon)
        
        // Perform geocoding
        geocoder.reverseGeocodeLocation(location) { [weak self] (placemarks, error) in
            guard let self = self, let placemark = placemarks?.first else { return }
            let address = Address(
                streetNumber: placemark.subThoroughfare ?? "",
                streetName: placemark.thoroughfare ?? "",
                cityOrTownName: placemark.locality ?? "",
                postalCode: placemark.postalCode ?? "",
                regionOrStateName: placemark.administrativeArea ?? "",
                countryName: placemark.country ?? ""
            )
            DispatchQueue.main.async {
                self.address = address
                ElementCellViewModel.geocodingCache[self.addressCacheKey] = address
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
