import SwiftUI

// MARK: - Element
struct Element: Codable, Identifiable {
    //let UUID = UUID()
    let id: String
    let osmJSON: OsmJSON?
    let tags: Tags?
    let createdAt: String
    let updatedAt, deletedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case osmJSON = "osm_json"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
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
                let elements = try JSONDecoder().decode([Element].self, from: data)
                completion(elements)
            } catch let error {
                print(error)
                completion(nil)
            }
        }.resume()
    }
}

struct BtcMapAPIView: View {
    @State public var elements: [Element]?
    let apiManager = APIManager()
    
    var body: some View {
        VStack {
            if let elements = elements {
                List(elements, id: \.id) { element in
                    VStack(alignment: .leading) {
                        Text("Element ID: \(element.id)")
                            .font(.headline)
                        Text("Created At: \(element.createdAt)")
                        Text("Latitude: \(element.osmJSON?.lat ?? 0.0)")
                        Text("Longitude: \(element.osmJSON?.lon ?? 0.0)")
                        Text("Longitude: \(element.osmJSON?.tags)" as String)
                        //                        Text("Tags: \(element.tags)" as String)
                        if let osmJSON = element.osmJSON, let tags = osmJSON.tags, tags["payment:lightning_contactless"] == "yes" {
                            Text("Accepts Lightning Contactless")
                        } else {
                        }
                        
                    }
                }
            } else {
                Text("Loading...")
            }
        }
        .onAppear {
            apiManager.getElements { elements in
                DispatchQueue.main.async {
                    self.elements = elements
                }
            }
        }
    }
}
