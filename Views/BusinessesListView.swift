import SwiftUI
import MapKit

struct BusinessesListView: View {
    
    var locations: [Location] = LocationList.locations
    
    var body: some View {
        NavigationView {
            // Get location list from the LocationList array.
            List(locations, id: \.id) { location in
                
                // Wrap the LocationCell in a navigation link that brings the user to the BusinessDetailView
                NavigationLink(destination: BusinessDetailView(location: location), label: {
                    // LocationCell struct
                    LocationCell(location: location)
                })
            }  
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// LocationCell defines the cell for the location.
struct LocationCell: View {
    
    var location: Location
    
    var body: some View {
        // Location cell(s)
        VStack(alignment: .leading, spacing: 2) {
            
            HStack {
                // Business Name
                Text(location.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Miles from current location.
                // TODO: Get location and miles to business.
                // TODO: Do something to only display up to three characters (eg 2.1 or 999)
                // TODO: Play around with max width
                Text("2.1 Miles")
                    .frame(maxWidth: 70, alignment: .trailing)
            }
            
            // Business Street
            Text("\(location.street) \(location.street2)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                // Business city, state, zip
                Text("\(location.city), \(location.state) \(location.zip)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Accepts Bitcoin/Lightning logo
                // If accpets Bitcoin only
                if location.acceptsBitcoin == true && location.acceptsLightning == false {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                } 
                // If accepts Bitcoin and Lightning
                else if location.acceptsBitcoin == true && location.acceptsLightning == true {
                    
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.orange)
                        .frame(alignment: .trailing)
                    
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                } 
                // If accepts Lightning only
                else if location.acceptsBitcoin == false && location.acceptsLightning == true {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}



struct BusinessesListView_Previews: PreviewProvider {
    static var previews: some View {
        BusinessesListView()
    }
}
