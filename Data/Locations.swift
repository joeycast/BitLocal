import SwiftUI
import MapKit

// **** Locations ****
// Define location array.
struct Location: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let street: String
    let street2: String
    let city: String
    let state: String
    let zip: String
    let country: String
    let website: String
    let phone: String
    let acceptsBitcoin: Bool
    let acceptsLightning: Bool
    let businessDescription: String
}

// Locations
struct LocationList {
    
    static let locations = [
        Location(
            name: "Bitcoin Park", 
            coordinate: CLLocationCoordinate2D(latitude: 36.13478, longitude: -86.80079),
            street: "1910 21st Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37212",
            country: "US",
            website: "https://www.meetup.com/bitcoinpark/",
            phone: "15555555555",
            acceptsBitcoin: true,
            acceptsLightning: false,
            businessDescription: "A community supported campus in Nashville focused on grassroots bitcoin adoption and a home for bitcoiners to work, learn, collaborate, and build."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        ),
        Location(
            name: "Bitcoin Magazine Art Gallery ", 
            coordinate: CLLocationCoordinate2D(latitude: 36.14534, longitude: -86.76662),
            street: "1132 4th Ave S",
            street2: "",
            city: "Nashville",
            state: "TN",
            zip: "37210",
            country: "US",
            website: "https://bitcoinmagazine.com/press-releases/bitcoin-magazine-art-gallery-opening",
            phone: "5555555555",
            acceptsBitcoin: true,
            acceptsLightning: true,
            businessDescription: "Bitcoin Magazine Art Gallery (BMAG) is a display space and storefront featuring Bitcoin-related clothing, hardware, and the print edition of Bitcoin Magazine, while the art gallery features exclusive visuals from the leading creatives in the Bitcoin space as well as new artists to showcase their work."
        )
    ]  
}

