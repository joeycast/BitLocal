//
//  Element.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/25/25.
//


import Foundation

// MARK: - Element
struct Element: Codable, Identifiable, Hashable {
    let id: String
    let uuid: UUID
    let osmJSON: OsmJSON?
    let tags: Tags?
    let createdAt: String
    let updatedAt, deletedAt: String?
    var address: Address?

    /// A convenience dictionary of OSM tags (e.g. "cuisine", "shop", "amenity"), suitable for lookup in ElementCategorySymbols.
    var osmTagsDict: [String: String]? {
        guard let osmTags = osmJSON?.tags else { return nil }
        var dict: [String: String] = [:]
        if let cuisine = osmTags.cuisine {
            dict["cuisine"] = cuisine
        }
        if let shop = osmTags.shop {
            dict["shop"] = shop
        }
        if let sport = osmTags.sport {
            dict["sport"] = sport
        }
        if let tourism = osmTags.tourism {
            dict["tourism"] = tourism
        }
        if let healthcare = osmTags.healthcare {
            dict["healthcare"] = healthcare
        }
        if let craft = osmTags.craft {
            dict["craft"] = craft
        }
        if let amenity = osmTags.amenity {
            dict["amenity"] = amenity
        }
        if let place = osmTags.place {
            dict["place"] = place
        }
        if let leisure = osmTags.leisure {
            dict["leisure"] = leisure
        }
        if let office = osmTags.office {
            dict["office"] = office
        }
        if let building = osmTags.building {
            dict["building"] = building
        }
        if let company = osmTags.company {
            dict["company"] = company
        }
        return dict.isEmpty ? nil : dict
    }
    
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
        uuid = UUID()
        osmJSON = try container.decodeIfPresent(OsmJSON.self, forKey: .osmJSON)
        tags = try container.decodeIfPresent(Tags.self, forKey: .tags)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        
        if let osmTags = osmJSON?.tags {
            address = Address(
                streetNumber: osmTags.addrHousenumber,
                streetName: osmTags.addrStreet,
                cityOrTownName: osmTags.addrCity,
                postalCode: osmTags.addrPostcode,
                regionOrStateName: osmTags.addrState,
                countryName: nil
            )
        } else {
            address = nil
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
    let cuisine: String?
    let shop: String?
    let sport: String?
    let tourism: String?
    let healthcare: String?
    let craft: String?
    let amenity: String?
    let place: String?
    let leisure: String?
    let office: String?
    let building: String?
    let company: String?
    
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
        case cuisine
        case shop
        case sport
        case tourism
        case healthcare
        case craft
        case amenity
        case place
        case leisure
        case office
        case building
        case company
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
        case "": self = .empty
        case "inner": self = .inner
        case "outer": self = .outer
        default: self = .other(value)
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
