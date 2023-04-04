import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    var elements: [Element]
    
    var body: some View {
        NavigationView {
            List(elements.prefix(100), id: \.uuid) { element in
                let viewModel = ElementCellViewModel(element: element)
                NavigationLink(destination: BusinessDetailView(element: element), label: {
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
                Text(viewModel.element.osmJSON?.tags?["name"] ?? "name not available")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("2.1 Miles")
                    .frame(maxWidth: 70, alignment: .trailing)
            }
            
            Text(viewModel.address?.streetNameAndNumber ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
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
    
    private let geocoder = CLGeocoder()
    
    init(element: Element) {
        self.element = element
    }
    
    func updateAddress() {
        guard let lat = element.osmJSON?.lat, let lon = element.osmJSON?.lon else {
            return
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            if let placemark = placemarks?.first {
                let address = Address(
                    streetNameAndNumber: (placemark.subThoroughfare ?? "") + " " + (placemark.thoroughfare ?? ""),
                    cityOrTownName: placemark.locality ?? "",
                    postalCode: placemark.postalCode ?? "",
                    regionOrStateName: placemark.administrativeArea ?? "",
                    countryName: placemark.country ?? ""
                )
                DispatchQueue.main.async {
                    self.address = address
                }
            }
        }
    }
}
