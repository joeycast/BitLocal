import SwiftUI
import CoreLocation

// MARK: - Element
struct Element: Codable, Identifiable {
    let id: String
    let uuid: UUID
    let osmJSON: OsmJSON?
    let tags: Tags?
    let createdAt: String
    let updatedAt, deletedAt: String?
    var address: Address?
    
    enum CodingKeys: String, CodingKey {
        case id
        case uuid 
        case osmJSON = "osm_json"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        uuid = UUID() // generate UUID during initialization
        osmJSON = try container.decodeIfPresent(OsmJSON.self, forKey: .osmJSON)
        tags = try container.decodeIfPresent(Tags.self, forKey: .tags)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

// MARK: - Address
struct Address {
    let streetNumber: String?
    let streetName: String?
    let cityOrTownName: String?
    let postalCode: String?
    let regionOrStateName: String?
    let countryName: String?
    
    init(streetNumber: String?, streetName: String?, cityOrTownName: String?, postalCode: String?, regionOrStateName: String?, countryName: String?) {
        self.streetNumber = streetNumber
        self.streetName = streetName
        self.cityOrTownName = cityOrTownName
        self.postalCode = postalCode
        self.regionOrStateName = regionOrStateName
        self.countryName = countryName
    }
}

// MARK: - OsmJSON
struct OsmJSON: Codable {
    let changeset, id: Int?
    let lat, lon: Double?
    let tags: [String: String]?
    let timestamp: String?
    let type: TypeEnum?
    let uid: Int?
    let user: String?
    let version: Int?
    let bounds: Bounds?
    let geometry: [Geometry]?
    let nodes: [Int]?
    let members: [Member]?
}

// MARK: - Bounds
struct Bounds: Codable {
    let maxlat, maxlon, minlat, minlon: Double?
}

// MARK: - Geometry
struct Geometry: Codable {
    let lat, lon: Double?
}

// MARK: - Member
struct Member: Codable {
    let geometry: [Geometry]?
    let ref: Int?
    let role: Role?
    let type: TypeEnum?
}

enum Role: String, Codable {
    case empty = ""
    case inner = "inner"
    case outer = "outer"
}

enum TypeEnum: String, Codable {
    case node = "node"
    case relation = "relation"
    case way = "way"
}

// MARK: - Tags
struct Tags: Codable {
    let category: Category?
    let iconAndroid, paymentCoinos, paymentPouch, boostExpires: String?
    let categoryPlural: CategoryPlural?
    let paymentProvider: String?
    let paymentURI: String?
    
    // TODO: Add more here, like bitcoin/lightning/phone/website?
    enum CodingKeys: String, CodingKey {
        case category
        case iconAndroid = "icon:android"
        case paymentCoinos = "payment:coinos"
        case paymentPouch = "payment:pouch"
        case boostExpires = "boost:expires"
        case categoryPlural = "category:plural"
        case paymentProvider = "payment:provider"
        case paymentURI = "payment:uri"
    }
}

enum Category: String, Codable {
    case atm = "atm"
    case bar = "bar"
    case cafe = "cafe"
    case hotel = "hotel"
    case other = "other"
    case pub = "pub"
    case restaurant = "restaurant"
}

enum CategoryPlural: String, Codable {
    case atms = "atms"
    case bars = "bars"
    case cafes = "cafes"
    case hotels = "hotels"
    case other = "other"
    case pubs = "pubs"
    case restaurants = "restaurants"
}

@propertyWrapper public struct NilOnFail<T: Codable>: Codable {
    
    public let wrappedValue: T?
    public init(from decoder: Decoder) throws {
        wrappedValue = try? T(from: decoder)
    }
    public init(_ wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
}

class APIManager {
    
    private let geocoder = CLGeocoder()
    
    func getElements(completion: @escaping ([Element]?) -> Void) {
        guard let url = URL(string: "https://api.btcmap.org/v2/elements/") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { (data, _, error) in
            guard let data = data else {
                completion(nil)
                return
            }
            do {
                var elements = try JSONDecoder().decode([Element].self, from: data)
                
                // Determine the address based on the coordinates and store in the address field of the array
                for index in 0..<elements.count {
                    guard let lat = elements[index].osmJSON?.lat, let lon = elements[index].osmJSON?.lon else {
                        continue
                    }
                    let location = CLLocation(latitude: lat, longitude: lon)
                    self.geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
                        if let placemark = placemarks?.first {
                            let streetNumber = placemark.subThoroughfare
                            let streetName = placemark.thoroughfare
                            let cityOrTownName = placemark.locality
                            let postalCode = placemark.postalCode
                            let regionOrStateName = placemark.administrativeArea
                            let countryName = placemark.country
                            
                            let address = Address(
                                streetNumber: streetNumber,
                                streetName: streetName,
                                cityOrTownName: cityOrTownName,
                                postalCode: postalCode,
                                regionOrStateName: regionOrStateName,
                                countryName: countryName
                            )
                            
                            elements[index].address = address
                        }
                    }
                }
                completion(elements)
            } catch let error {
                print(error)
                completion(nil)
            }
        }.resume()
    }
}

