import SwiftUI

struct BusinessDetailView: View {
    
    var location: Location
    
    var body: some View {
        List {
            // Business Description Section
            Text(location.businessDescription)
            
            // Business Details Section
            // TODO: Allow Business Detail elements to be copied.
            Section(header: Text("Business Details")) {
                
                // Business Address
                VStack (alignment: .leading, spacing: 3) {
                    Text("Address")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        // TODO: Add country?
                        Link(destination: URL(string: "maps://?saddr=&daddr=\(location.coordinate.latitude),\(location.coordinate.longitude)")!) {
                            Text("\(location.street) \(location.street2)\n\(location.city), \(location.state) \(location.zip)")
                        }
                    }
                }
                
                // Business Website
                // TODO: Remove leading "https:.//www."?
                VStack (alignment: .leading, spacing: 3) {
                    Text("Website")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Link(destination: URL(string:"\(location.website)")!) {
                        Text(location.website)
                            .lineLimit(1)
                    }
                }
                
                // Business Phone
                VStack (alignment: .leading, spacing: 3) {
                    Text("Phone")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // TODO: Apply formatting to phone
                    Link(destination: URL(string:"tel://\(location.phone)")!) {
                        Text(location.phone)
                    }
                }
            }
            
            // Payment Details Section
            Section(header: Text("Payment Details")) {
                // Business Accepts Bitcoin
                if location.acceptsBitcoin == true {
                    HStack {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundColor(.orange)
                        Text("Accepts Bitcoin")
                    }
                }
                
                // Business Accepts Lightning
                if location.acceptsLightning == true {
                    HStack {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(.orange)
                        Text("Accepts Bitcoin over Lightning")
                    }
                }  
            }
        }
        // Business Name
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.large)
        //.listStyle(.grouped)
    }
}

struct BusinessDetailView_Previews: PreviewProvider {
    static var previews: some View {
        BusinessDetailView(location: LocationList.locations.first!)
    }
}
