import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    var elements: [Element]
    
    var body: some View {
        NavigationView {
            List(elements.prefix(100), id: \.uuid) { element in
                let viewModel = ElementCellViewModel(element: element)
                ElementCell(viewModel: viewModel)
                    .onAppear {
                        viewModel.updateAddress()
                    }
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
                
                if (viewModel.element.osmJSON?.tags?["payment:onchain"] == "yes" || viewModel.element.osmJSON?.tags?["payment:bitcoin"] == "yes") && viewModel.element.osmJSON?.tags?["payment:lightning"] == nil {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                }
                else if (viewModel.element.osmJSON?.tags?["payment:onchain"] == "yes" || viewModel.element.osmJSON?.tags?["payment:bitcoin"] == "yes") && viewModel.element.osmJSON?.tags?["payment:lightning"] == "yes" {
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                }
                else if (viewModel.element.osmJSON?.tags?["payment:onchain"] == nil || viewModel.element.osmJSON?.tags?["payment:bitcoin"] == nil ) && viewModel.element.osmJSON?.tags?["payment:lightning"] == "yes" {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                    cityOrTownName: placemark.locality,
                    postalCode: placemark.postalCode,
                    regionOrStateName: placemark.administrativeArea,
                    countryName: placemark.country
                )
                DispatchQueue.main.async {
                    self.address = address
                }
            }
        }
    }
}

//struct BusinessesListView_Previews: PreviewProvider {
//    static var previews: some View {
//        let elements = [Element](repeating: Element(id: UUID().uuidString, 
//                                                    uuid: UUID(), 
//                                                    osmJSON: nil, 
//                                                    tags: nil, 
//                                                    createdAt: "", 
//                                                    updatedAt: "", 
//                                                    deletedAt: "", 
//                                                    address: Address(street: "", city: "", zip: "", state: "", country: "")), 
//                                                     count: 100)
//        return BusinessesListView(elements: elements)
//    }
//}

