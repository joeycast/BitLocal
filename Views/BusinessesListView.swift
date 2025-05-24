// BusinessesListView.swift

import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation

@available(iOS 16.4, *)
struct BusinessesListView: View {
    
    @EnvironmentObject var viewModel: ContentViewModel
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
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
    
    private func localizedDistanceString(for element: Element) -> String? {
        guard let userLocation = viewModel.userLocation, let coord = element.mapCoordinate else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let useMetric: Bool
        switch distanceUnit {
        case .auto:
            useMetric = Locale.current.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        if useMetric {
            let km = distanceInMeters / 1000
            if km < 1 {
                return String(format: "%.2f km", km)
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            let miles = distanceInMeters / 1609.344
            if miles < 1 {
                return String(format: "%.2f mi", miles)
            } else {
                return String(format: "%.1f mi", miles)
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

@available(iOS 16.4, *)
struct ElementCell: View {
    
    @ObservedObject var viewModel: ElementCellViewModel
    @State private var appeared = false
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
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
        let formattedDistance: String? = {
            if let distance = localizedDistanceString(for: viewModel.element) {
                return distance
            } else {
                // fallback to miles for now
                if let distance = viewModel.viewModel.distanceInMiles(element: viewModel.element) {
                    if distance < 1 {
                        return String(format: "%.2f mi", distance)
                    } else {
                        return String(format: "%.1f mi", distance)
                    }
                }
                return nil
            }
        }()
        return Text(formattedDistance ?? "")
            .opacity(formattedDistance != nil ? 1 : 0)
            .padding(.trailing, 3)
    }
    
    private func localizedDistanceString(for element: Element) -> String? {
        guard let userLocation = viewModel.viewModel.userLocation, let coord = element.mapCoordinate else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let useMetric: Bool
        switch distanceUnit {
        case .auto:
            useMetric = Locale.current.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        if useMetric {
            let km = distanceInMeters / 1000
            if km < 1 {
                return String(format: "%.2f km", km)
            } else {
                return String(format: "%.1f km", km)
            }
        } else {
            let miles = distanceInMeters / 1609.344
            if miles < 1 {
                return String(format: "%.2f mi", miles)
            } else {
                return String(format: "%.1f mi", miles)
            }
        }
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
        guard let coord = element.mapCoordinate else {
            return ""
        }
        return "\(coord.latitude),\(coord.longitude)"
    }

    private func getCachedAddress() -> Address? {
        guard let coord = element.mapCoordinate else {
            return nil
        }
        let cacheKey = "\(coord.latitude),\(coord.longitude)"
        return viewModel.geocodingCache.getValue(forKey: cacheKey)
    }

    private func setCachedAddress(_ address: Address) {
        guard let coord = element.mapCoordinate else {
            return
        }
        let cacheKey = "\(coord.latitude),\(coord.longitude)"
        viewModel.geocodingCache.setValue(address, forKey: cacheKey)
    }

    func updateAddress() {
        // Check if the address is already cached
        if let cachedAddress = ElementCellViewModel.geocodingCache[addressCacheKey] {
            self.address = cachedAddress
            return
        }

        guard let coord = element.mapCoordinate else { return }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

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
