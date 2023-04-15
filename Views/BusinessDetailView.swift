import SwiftUI
import CoreLocation

struct BusinessDetailView: View {
    
    var element: Element
    var userLocation: CLLocation?
    
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
                
                // TODO: Fix display issues when certain address elements are nil
                Link(destination: URL(string: "maps://?saddr=&daddr=\(element.osmJSON?.lat ?? 0.0),\(element.osmJSON?.lon ?? 0.0)")!) {
                    Text("\(elementCellViewModel.address?.streetNumber ?? "") \(elementCellViewModel.address?.streetName ?? "")\n\(elementCellViewModel.address?.cityOrTownName ?? ""), \(elementCellViewModel.address?.regionOrStateName ?? "") \(elementCellViewModel.address?.postalCode ?? "")")
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
