// BusinessDetailView.swift

import SwiftUI
import CoreLocation
import MapKit
import Foundation

@available(iOS 17.0, *)
struct BusinessDetailView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var region = MKCoordinateRegion()
    @StateObject var elementCellViewModel: ElementCellViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    var element: Element
    var userLocation: CLLocation?
    
    init(element: Element, userLocation: CLLocation?, contentViewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self._elementCellViewModel = StateObject(wrappedValue: ElementCellViewModel(element: element, userLocation: userLocation, viewModel: contentViewModel))
    }
    
    fileprivate func localizedDistanceString() -> String? {
        guard let userLocation = userLocation, let coord = element.mapCoordinate else { return nil }
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
            return String(format: "%.1f km", km)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }
    
    var body: some View {
        List {
            BusinessDescriptionSection(element: element)
            BusinessDetailsSection(element: element, elementCellViewModel: elementCellViewModel)
            PaymentDetailsSection(element: element)
            BusinessMapSection(element: element)
        }
        .onAppear {
            Debug.log("BusinessDetailView appeared for element: \(element.id)")
            Debug.log("ElementCellViewModel address: \(elementCellViewModel.address?.streetName ?? "nil")")
            elementCellViewModel.updateAddress()
        }
        .listStyle(InsetGroupedListStyle()) // Consistent list style
        .navigationTitle(element.osmJSON?.tags?.name ?? element.osmJSON?.tags?.operator ?? NSLocalizedString("name_not_available", comment: "Fallback name when no name is available"))
        .navigationBarTitleDisplayMode(horizontalSizeClass == .compact ? .inline : .inline)    }
}

// BusinessDescriptionSection
struct BusinessDescriptionSection: View {
    var element: Element
    
    var body: some View {
        if let description = element.osmJSON?.tags?.description ?? element.osmJSON?.tags?.descriptionEn {
            Section(header: Text(NSLocalizedString("business_description_section", comment: "Section header for business description"))) {
                Text(description)
            }
        } else {
        }
    }
}

// Business Details Section
@available(iOS 17.0, *)
struct BusinessDetailsSection: View {
    var element: Element
    @ObservedObject var elementCellViewModel: ElementCellViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("business_details_section", comment: "Section header for business details"))) {
            
            // TO DO: Determine necessity of this block of code
            if let distance = BusinessDetailView(element: element, userLocation: nil, contentViewModel: ContentViewModel()).localizedDistanceString() {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.blue)
                    Text(distance)
                        .font(.subheadline)
                }
            }
            
            // Business Address
            VStack (alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("address_label", comment: "Label for address"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let coord = element.mapCoordinate {
                    Link(destination: URL(string: "maps://?saddr=&daddr=\(coord.latitude),\(coord.longitude)")!) {
                        Text("\(elementCellViewModel.address?.streetNumber != nil && !elementCellViewModel.address!.streetNumber!.isEmpty ? elementCellViewModel.address!.streetNumber! + " " : "")\(elementCellViewModel.address?.streetName ?? "")\n\(elementCellViewModel.address?.cityOrTownName ?? "")\(elementCellViewModel.address?.cityOrTownName != nil && elementCellViewModel.address?.cityOrTownName != "" ? ", " : "")\(elementCellViewModel.address?.regionOrStateName ?? "") \(elementCellViewModel.address?.postalCode ?? "")")
                    }
                }
            }
            
            // Business Website - Only show if valid
            if let website = element.osmJSON?.tags?.website ?? element.osmJSON?.tags?.contactWebsite,
               let validURL = website.cleanedWebsiteURL() {
                
                VStack (alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("website_label", comment: "Label for website"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Link(destination: validURL) {
                        Text(website.cleanedForDisplay())
                            .lineLimit(1)
                    }
                }
            }
            
            // Business Phone - Simple worldwide approach
            if let phone = element.osmJSON?.tags?.phone ?? element.osmJSON?.tags?.contactPhone {
                let (cleanPhone, isValid) = phone.cleanedPhoneNumber()
                
                if isValid, let url = URL(string: "tel:\(cleanPhone)") {
                    VStack (alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("phone_label", comment: "Label for phone"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Link(destination: url) {
                            Text(phone.displayablePhoneNumber()) // Show original with minimal cleanup
                                .lineLimit(1)
                        }
                    }
                } else {
                    let _ = Debug.log("Invalid phone number: '\(phone)'")
                }
            }
            
            // Opening Hours
            if let openingHours = element.osmJSON?.tags?.openingHours {
                VStack (alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(openingHours)
                }
            }
        }
    }
}


// Payment Details Section
struct PaymentDetailsSection: View {
    var element: Element
    
    var body: some View {
        Section(header: Text(NSLocalizedString("payment_details_section", comment: "Section header for payment details"))) {
            // Accepts Bitcoin (details regarding on chain/lightning/contactless lightning not available)
            if acceptsBitcoin(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            
            // Business Accepts Bitcoin
            if acceptsBitcoinOnChain(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin_onchain", comment: "Label for accepting Bitcoin on Chain"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            
            // Business Accepts Lightning
            if acceptsLightning(element: element) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin_lightning", comment: "Label for accepting Bitcoin over Lightning"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            if acceptsContactlessLightning(element: element) {
                HStack {
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_contactless_lightning", comment: "Label for accepting Contactless Lightning"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }
}

// BusinessMapSection
struct BusinessMapSection: View {
    var element: Element
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        BusinessMiniMapView(element: element)
            .frame(height: horizontalSizeClass == .compact ? 200 : 300) // Adjust height based on device
            .cornerRadius(10)
    }
}

// Map View
// TODO: Refactor to reuse annotation customization code from ContentViewModel
struct BusinessMiniMapView: UIViewRepresentable {
    var element: Element
    
    // Read the persisted map type using AppStorage.
    // This value is stored as an Int (the rawValue of MKMapType)
    @AppStorage("selectedMapType") private var storedMapType: Int = Int(MKMapType.standard.rawValue)
    
    // Convert the stored integer back to MKMapType
    var mapType: MKMapType {
        MKMapType(rawValue: UInt(storedMapType)) ?? .standard
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Set the map type based on the persisted value
        mapView.mapType = mapType
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update map type if it has changed
        if uiView.mapType != mapType {
            uiView.mapType = mapType
        }
        updateAnnotations(from: uiView)
    }
    
    private func updateAnnotations(from mapView: MKMapView) {
        mapView.removeAnnotations(mapView.annotations)
        
        let annotation = Annotation(element: element)
        mapView.addAnnotation(annotation)
        
        let coordinate = annotation.coordinate
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        mapView.setRegion(region, animated: true)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: BusinessMiniMapView
        
        init(_ parent: BusinessMiniMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let reuseIdentifier = "AnnotationView"
            var view: MKMarkerAnnotationView?
            
            if let annotation = annotation as? Annotation {
                view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                view?.canShowCallout = true
                view?.markerTintColor = UIColor(named: "MarkerColor")
                view?.glyphText = nil
                view?.glyphTintColor = .white
                if let element = annotation.element {
                    let symbolName = ElementCategorySymbols.symbolName(for: element)
                    Debug.logMap("MiniMap: Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                    view?.glyphImage = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                }
                view?.displayPriority = .required
            }
            return view
        }
    }
}

// Troubleshooting Section
//struct TroubleshootingSection: View {
//    var element: Element
//
//    var body: some View {
//        Section(header: Text("Troubleshooting")) {
//            Text("ID: \(element.id)")
//            Text("Created at: \(element.createdAt)")
//            Text("Updated at: \(element.updatedAt ?? "")")
//            Text("Deleted at: \(element.deletedAt ?? "")")
//            Text("Description: \(element.osmJSON?.tags?.description ?? "")")
//            Text("Phone: \(element.osmJSON?.tags?.phone ?? "")")
//            Text("Contact:Phone: \(element.osmJSON?.tags?.contactPhone ?? "")")
//            Text("Website: \(element.osmJSON?.tags?.website ?? "")")
//            Text("Contact:Website: \(element.osmJSON?.tags?.contactWebsite ?? "")")
//            Text("Opening Hours: \(element.osmJSON?.tags?.openingHours ?? "")")
//            Text("Accepts payment:bitcoin: \(element.osmJSON?.tags?.paymentBitcoin ?? "no")")
//            Text("Accepts currency:XBT: \(element.osmJSON?.tags?.currencyXBT ?? "no")")
//            Text("Accepts Bitcoin on Chain: \(element.osmJSON?.tags?.paymentOnchain ?? "no")")
//            Text("Accepts Lightning: \(element.osmJSON?.tags?.paymentLightning ?? "no")")
//            Text("Accepts Contactless Lightning: \(element.osmJSON?.tags?.paymentLightningContactless ?? "no")")
//            Text("House Number: \(element.osmJSON?.tags?.addrHousenumber ?? "")")
//            Text("Street: \(element.osmJSON?.tags?.addrStreet ?? "")")
//            Text("City: \(element.osmJSON?.tags?.addrCity ?? "")")
//            Text("State: \(element.osmJSON?.tags?.addrState ?? "")")
//            Text("Post Code: \(element.osmJSON?.tags?.addrPostcode ?? "")")
//        }
//    }
//}
