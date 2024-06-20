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
        
        if let osmTags = osmJSON?.tags {
            address = Address(streetNumber: osmTags.addrHousenumber,
                              streetName: osmTags.addrStreet,
                              cityOrTownName: osmTags.addrCity,
                              postalCode: osmTags.addrPostcode,
                              regionOrStateName: osmTags.addrState,
                              countryName: nil) // Country is not present in the given JSON
        } else {
            address = nil
        }
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
    let tags: OsmTags?
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

// MARK: - OsmTags
struct OsmTags: Codable {
    let addrCity, addrHousenumber, addrPostcode, addrState, addrStreet: String?
    let paymentBitcoin, currencyXBT, paymentOnchain, paymentLightning, paymentLightningContactless: String?
    let name, `operator`: String?
    let description, descriptionEn, website, contactWebsite, phone, contactPhone, openingHours: String?
    
    enum CodingKeys: String, CodingKey {
        case addrCity = "addr:city"
        case addrHousenumber = "addr:housenumber"
        case addrPostcode = "addr:postcode"
        case addrState = "addr:state"
        case addrStreet = "addr:street"
        case paymentBitcoin = "payment:bitcoin"
        case currencyXBT = "currency:XBT"
        case paymentOnchain = "payment:onchain"
        case paymentLightning = "payment:lightning"
        case paymentLightningContactless = "payment:lightning_contactless"
        case name
        case `operator`
        case description
        case descriptionEn = "description:en"
        case website
        case contactWebsite = "contact:website"
        case phone
        case contactPhone = "contact:phone"
        case openingHours = "opening_hours"
    }
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

enum Role: Codable {
    case empty
    case inner
    case outer
    case other(String)
    
    var rawValue: String {
        switch self {
        case .empty: return ""
        case .inner: return "inner"
        case .outer: return "outer"
        case .other(let value): return value
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        switch value {
        case "":
            self = .empty
        case "inner":
            self = .inner
        case "outer":
            self = .outer
        default:
            self = .other(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TypeEnum: Codable {
    case node
    case relation
    case way
    case unknown(String)
    
    var rawValue: String {
        switch self {
        case .node: return "node"
        case .relation: return "relation"
        case .way: return "way"
        case .unknown(let value): return value
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        switch value {
        case "node": self = .node
        case "relation": self = .relation
        case "way": self = .way
        default: self = .unknown(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

enum Category: Codable {
    case atm
    case bar
    case cafe
    case hotel
    case other
    case pub
    case restaurant
    case unknown(String)
    
    var rawValue: String {
        switch self {
        case .atm: return "atm"
        case .bar: return "bar"
        case .cafe: return "cafe"
        case .hotel: return "hotel"
        case .other: return "other"
        case .pub: return "pub"
        case .restaurant: return "restaurant"
        case .unknown(let value): return value
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        switch value {
        case "atm": self = .atm
        case "bar": self = .bar
        case "cafe": self = .cafe
        case "hotel": self = .hotel
        case "other": self = .other
        case "pub": self = .pub
        case "restaurant": self = .restaurant
        default: self = .unknown(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CategoryPlural: Codable {
    case atms
    case bars
    case cafes
    case hotels
    case other
    case pubs
    case restaurants
    case unknown(String)
    
    var rawValue: String {
        switch self {
        case .atms: return "atms"
        case .bars: return "bars"
        case .cafes: return "cafes"
        case .hotels: return "hotels"
        case .other: return "other"
        case .pubs: return "pubs"
        case .restaurants: return "restaurants"
        case .unknown(let value): return value
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        switch value {
        case "atms": self = .atms
        case "bars": self = .bars
        case "cafes": self = .cafes
        case "hotels": self = .hotels
        case "other": self = .other
        case "pubs": self = .pubs
        case "restaurants": self = .restaurants
        default: self = .unknown(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
    
    let cacheKey = "cachedElements"
    let lastUpdateKey = "lastUpdate"
    
    init() {
        UserDefaults.standard.register(defaults: [lastUpdateKey: "2000-01-01T00:00:00.000Z"])
    }
    
    private func updateCacheWithFetchedElements(fetchedElements: [Element]) {
        // Since cacheKey is not optional, we can use it directly without unwrapping
        let cacheKey = self.cacheKey
        
        // Load the existing cache or initialize it if not present
        var cachedElements = UserDefaults.standard.getElements(forKey: cacheKey) ?? []
        
        // Create a dictionary for efficient lookup and merging
        var elementsDictionary = Dictionary(uniqueKeysWithValues: cachedElements.map { ($0.id, $0) })
        
        // Update existing elements or add new ones
        fetchedElements.forEach { element in
            elementsDictionary[element.id] = element
        }
        
        // Convert dictionary back to array
        cachedElements = Array(elementsDictionary.values)
        
        // Save updated cache
        UserDefaults.standard.setElements(cachedElements, forKey: cacheKey)
    }
    
    func getElements(completion: @escaping ([Element]?) -> Void) {
        let lastUpdate = UserDefaults.standard.string(forKey: lastUpdateKey) ?? ""
        let urlString = "https://api.btcmap.org/v2/elements?updated_since=\(lastUpdate)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL string: \(urlString)")
            LogManager.shared.log("Invalid URL string: \(urlString)")
            completion(nil)
            return
        }
        
        // Log the requesting URL
        print("Requesting URL: \(url.absoluteString)")
        LogManager.shared.log("Requesting URL: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            guard let data = data, error == nil else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                LogManager.shared.log("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                print("Content-Type: \(contentType ?? "Unknown")")
                LogManager.shared.log("Content-Type: \(contentType ?? "Unknown")")
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.dataDecodingStrategy = .base64 // Set the data decoding strategy to discard invalid characters
                
                let fetchedElements = try decoder.decode([Element].self, from: data)
                print("Decoded JSON: \(String(data: data, encoding: .utf8) ?? "")")
                print("Decoded Elements: \(fetchedElements)")
                // Assuming updateCacheWithFetchedElements is already correctly integrated
                self?.updateCacheWithFetchedElements(fetchedElements: fetchedElements)
                
                // Find the most recent 'updatedAt' timestamp from the fetched elements
                if let mostRecentUpdate = fetchedElements.max(by: { $0.updatedAt ?? "" < $1.updatedAt ?? "" })?.updatedAt {
                    print("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    LogManager.shared.log("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    UserDefaults.standard.setValue(mostRecentUpdate, forKey: self?.lastUpdateKey ?? "")
                    
                    // Immediately read it back for verification
                    let updatedTime = UserDefaults.standard.string(forKey: self?.lastUpdateKey ?? "")
                    print("Verified lastUpdateKey is now: \(String(describing: updatedTime))")
                    LogManager.shared.log("Verified lastUpdateKey is now: \(String(describing: updatedTime))")
                }
                
                // Fetch the updated cache to return via completion
                let updatedCache = UserDefaults.standard.getElements(forKey: self?.cacheKey ?? "")
                completion(updatedCache)
            } catch {
                print("JSON Decoding Error: \(error)")
                LogManager.shared.log("JSON Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
}

class LogManager {
    static let shared = LogManager()
    private init() {} // Private constructor ensures a single instance
    
    private(set) var logs: [String] = []
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" // ISO 8601 format
        return formatter
    }()
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        logs.append(logMessage)
    }
    
    func allLogs() -> String {
        return logs.joined(separator: "\n")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}
