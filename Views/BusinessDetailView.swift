import SwiftUI
import CoreLocation
import MapKit

struct BusinessDetailView: View {
    
    var element: Element
    var userLocation: CLLocation?
    
    @State private var region = MKCoordinateRegion()
    @StateObject var elementCellViewModel: ElementCellViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    init(element: Element, userLocation: CLLocation?, contentViewModel: ContentViewModel) {
        self.element = element
        self.userLocation = userLocation
        self._elementCellViewModel = StateObject(wrappedValue: ElementCellViewModel(element: element, userLocation: userLocation, viewModel: contentViewModel))
    }
    
    var body: some View {
        List {
            BusinessDescriptionSection(element: element)
            BusinessDetailsSection(element: element, elementCellViewModel: elementCellViewModel)
            PaymentDetailsSection(element: element)
            BusinessMapSection(element: element)         
            TroubleshootingSection(element: element)
        }
        .onAppear {
            elementCellViewModel.updateAddress()
        }
        .navigationTitle(element.osmJSON?.tags?["name"] ?? element.osmJSON?.tags?["operator"] ?? "Name not available")
        .navigationBarTitleDisplayMode(.large)
    }
}

// BusinessDescriptionSection
struct BusinessDescriptionSection: View {
    var element: Element
    
    var body: some View {
        if let description = element.osmJSON?.tags?["description"] ?? element.osmJSON?.tags?["description:en"] {
            Section(header: Text("Description")) {
                Text(description)   
            }
        } else {
        }
    }
}


// Business Details Section
struct BusinessDetailsSection: View {
    var element: Element
    @ObservedObject var elementCellViewModel: ElementCellViewModel
    
    var body: some View {
        Section(header: Text("Business Details")) {
            // Business Address
            VStack (alignment: .leading, spacing: 3) {
                Text("Address")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Link(destination: URL(string: "maps://?saddr=&daddr=\(element.osmJSON?.lat ?? 0.0),\(element.osmJSON?.lon ?? 0.0)")!) {
                    Text("\(elementCellViewModel.address?.streetNumber ?? "") \(elementCellViewModel.address?.streetName ?? "")\n\(elementCellViewModel.address?.cityOrTownName ?? "")\(elementCellViewModel.address?.cityOrTownName != nil && elementCellViewModel.address?.cityOrTownName != "" ? ", " : "")\(elementCellViewModel.address?.regionOrStateName ?? "") \(elementCellViewModel.address?.postalCode ?? "")")
                }
            }
            
            // Business Website
            // TODO: Remove leading "https:.//www."?
            VStack (alignment: .leading, spacing: 3) {
                Text("Website")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let website = element.osmJSON?.tags?["website"] ?? element.osmJSON?.tags?["contact:website"] {
                    Link(destination: URL(string: website)!) {
                        Text(website)
                            .lineLimit(1)
                    }
                } else {
                    Text("No website available.")
                }
            }
            
            // Business Phone
            VStack (alignment: .leading, spacing: 3) {
                Text("Phone")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // TODO: Apply formatting to phone
                // TODO: Strip the junk out of phone numbers before storing instead of here.
                if let phone = element.osmJSON?.tags?["phone"] ?? element.osmJSON?.tags?["contact:phone"], let url = URL(string:"tel://\(phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""))") {
                    Link(destination: url) {
                        Text(phone)
                            .lineLimit(1)
                    }
                } else {
                    Text("No phone number available.")
                }
            }
            VStack (alignment: .leading, spacing: 3) {
                Text("Opening Hours")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let openingHours = element.osmJSON?.tags?["opening_hours"] {
                    Text(openingHours)
                } else {
                    Text("No opening hours data available.")
                }
            }
        }
    }
}

// Payment Details Section
struct PaymentDetailsSection: View {
    var element: Element
    
    var body: some View {
        Section(header: Text("Payment Details")) {
            // Accepts Bitcoin (details regarding on chain/lightning/contactless lightning not available)
            if acceptsBitcoin(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                    Text("Accepts Bitcoin")
                }
            }
            
            // Business Accepts Bitcoin
            if acceptsBitcoinOnChain(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                    Text("Accepts Bitcoin on Chain")
                }
            }
            
            // Business Accepts Lightning
            if acceptsLightning(element: element) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                    Text("Accepts Bitcoin over Lightning")
                }
            }  
            if acceptsContactlessLightning(element: element) {
                HStack {
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.orange)
                    Text("Accepts Contactless Lightning")
                }
            }  
        }
    }
}

// BusinessMapSection
struct BusinessMapSection: View {
    var element: Element
    
    var body: some View {
        MapView(element: element)
            .frame(height: 200)
            .cornerRadius(10)
    }
}

// Map View
// TODO: Refactor to reuse annotation customization code from ContentViewModel
struct MapView: UIViewRepresentable {
    var element: Element
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        updateAnnotations(from: uiView)
    }
    
    private func updateAnnotations(from mapView: MKMapView) {
        mapView.removeAnnotations(mapView.annotations)
        
        let annotation = MKPointAnnotation()
        if let latitude = element.osmJSON?.lat,
           let longitude = element.osmJSON?.lon {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            annotation.coordinate = coordinate
            annotation.title = element.osmJSON?.tags?["name"] ?? element.osmJSON?.tags?["operator"] ?? "Name not available"
            
            mapView.addAnnotation(annotation)
            
            let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
            mapView.setRegion(region, animated: true)
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            
            let identifier = "customPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                // Set the glyph image to "location.circle.fill"
                annotationView?.glyphImage = UIImage(systemName: "location.circle.fill")
                // Set the marker tint color to orange
                annotationView?.markerTintColor = .orange
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
    }
}

// Troubleshooting Section
struct TroubleshootingSection: View {
    var element: Element
    
    var body: some View {
        Section(header: Text("Troubleshooting")) {
            Text("ID: \(element.id)")
            Text("Created at: \(element.createdAt)")
            Text("Updated at: \(element.updatedAt ?? "")")
            Text("Deleted at: \(element.deletedAt ?? "")")
            //Text("Description: \(element.osmJSON?.tags?["description"] ?? "")")                
            //Text("Phone: \(element.osmJSON?.tags?["phone"] ?? "")")
            //Text("Contact:Phone: \(element.osmJSON?.tags?["contact:phone"] ?? "")")
            //Text("Website: \(element.osmJSON?.tags?["website"] ?? "")")
            //Text("Contact:Website: \(element.osmJSON?.tags?["contact:website"] ?? "")")
            //Text("Opening Hours: \(element.osmJSON?.tags?["opening_hours"] ?? "")")
            //Text("Accepts payment:bitcoin: \(element.osmJSON?.tags?["payment:bitcoin"] ?? "no")")
            //Text("Accepts currency:XBT: \(element.osmJSON?.tags?["currency:XBT"] ?? "no")")
            Text("Accepts payment:bitcoin: \(element.osmJSON?.tags?["payment:bitcoin"] ?? "no")")
            Text("Accepts currency:XBT: \(element.osmJSON?.tags?["currency:XBT"] ?? "no")")
            Text("Accepts Bitcoin on Chain: \(element.osmJSON?.tags?["payment:onchain"] ?? "no")")
            Text("Accepts Lightning: \(element.osmJSON?.tags?["payment:lightning"] ?? "no")")
            Text("Accepts Contactless Lightning: \(element.osmJSON?.tags?["payment:lightning_contactless"] ?? "no")")
        }
    }
}
