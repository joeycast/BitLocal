//
//  Element.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/25/25.
//


import Contacts
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
    var v4Metadata: ElementV4Metadata?

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
        case v4Metadata = "v4_metadata"
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
        v4Metadata = try container.decodeIfPresent(ElementV4Metadata.self, forKey: .v4Metadata)
        
        address = Self.address(from: osmJSON?.tags)
    }

    init(
        id: String,
        osmJSON: OsmJSON?,
        tags: Tags?,
        createdAt: String,
        updatedAt: String?,
        deletedAt: String?,
        address: Address? = nil,
        v4Metadata: ElementV4Metadata? = nil
    ) {
        self.id = id
        self.uuid = UUID()
        self.osmJSON = osmJSON
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.v4Metadata = v4Metadata

        self.address = address ?? Self.address(from: osmJSON?.tags)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayName: String? {
        let name = osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !Self.isInvalidPrimaryName(name) {
            return name
        }

        let brandName = osmJSON?.tags?.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !brandName.isEmpty {
            return brandName
        }

        let operatorName = osmJSON?.tags?.operator?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !operatorName.isEmpty {
            return operatorName
        }

        return nil
    }

    static func isInvalidPrimaryName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if isPlaceholderName(trimmed) { return true }
        return trimmed.lowercased() == "unnamed"
    }

    static func isPlaceholderName(_ value: String) -> Bool {
        value.hasPrefix("BTC Map Place #")
    }

    private static func address(from osmTags: OsmTags?) -> Address? {
        guard let osmTags else { return nil }

        let country = Address.countryComponents(from: osmTags.addrCountry)
        let hasStructuredFields = [
            osmTags.addrHousenumber,
            osmTags.addrStreet,
            osmTags.addrCity,
            osmTags.addrState,
            osmTags.addrPostcode,
            country.countryName,
            country.countryCode
        ]
        .contains { Address.normalizedAddressComponent($0) != nil }

        guard hasStructuredFields else { return nil }

        return Address(
            streetNumber: osmTags.addrHousenumber,
            streetName: osmTags.addrStreet,
            cityOrTownName: osmTags.addrCity,
            postalCode: Address.normalizedPostalCode(
                osmTags.addrPostcode,
                countryName: country.countryName,
                countryCode: country.countryCode,
                regionOrStateName: osmTags.addrState
            ),
            regionOrStateName: osmTags.addrState,
            countryName: country.countryName,
            countryCode: country.countryCode
        )
    }

    var boostExpirationDate: Date? {
        BTCMapDateParser.parse(v4Metadata?.boostedUntil) ?? BTCMapDateParser.parse(tags?.boostExpires)
    }

    func isCurrentlyBoosted(referenceDate: Date = Date()) -> Bool {
        guard let boostExpirationDate else { return false }
        return boostExpirationDate > referenceDate
    }
}

// MARK: - Address
struct Address: Codable {
    let streetNumber: String?
    let streetName: String?
    let cityOrTownName: String?
    let postalCode: String?
    let regionOrStateName: String?
    let countryName: String?
    let countryCode: String?

    init(
        streetNumber: String?,
        streetName: String?,
        cityOrTownName: String?,
        postalCode: String?,
        regionOrStateName: String?,
        countryName: String?,
        countryCode: String? = nil
    ) {
        self.streetNumber = streetNumber
        self.streetName = streetName
        self.cityOrTownName = cityOrTownName
        self.postalCode = postalCode
        self.regionOrStateName = regionOrStateName
        self.countryName = countryName
        self.countryCode = Address.normalizedCountryCode(countryCode)
    }
}

extension Address {
    private static let unitedStatesAliases: Set<String> = [
        "united states",
        "united states of america",
        "usa",
        "u.s.a.",
        "us",
        "u.s."
    ]

    private static let unitedStatesStateAbbreviations: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA",
        "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
        "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX",
        "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    struct CountryComponents {
        let countryName: String?
        let countryCode: String?
    }

    static func normalizedAddressComponent(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func normalizedCountryCode(_ value: String?) -> String? {
        guard let value = normalizedAddressComponent(value) else { return nil }
        let uppercased = value.uppercased()
        guard uppercased.count == 2 else { return nil }
        return uppercased
    }

    static func countryComponents(from rawCountry: String?) -> CountryComponents {
        guard let country = normalizedAddressComponent(rawCountry) else {
            return CountryComponents(countryName: nil, countryCode: nil)
        }

        if let countryCode = normalizedCountryCode(country) {
            return CountryComponents(countryName: nil, countryCode: countryCode)
        }

        return CountryComponents(countryName: country, countryCode: nil)
    }

    static func normalizedPostalCode(
        _ value: String?,
        countryName: String?,
        countryCode: String? = nil,
        regionOrStateName: String? = nil
    ) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        if shouldStripZipExtension(
            value: trimmed,
            countryName: countryName,
            countryCode: countryCode,
            regionOrStateName: regionOrStateName
        ) {
            return String(trimmed.prefix(5))
        }
        return trimmed
    }

    private static func shouldStripZipExtension(
        value: String,
        countryName: String?,
        countryCode: String?,
        regionOrStateName: String?
    ) -> Bool {
        let zipPlus4Pattern = #"^\d{5}-\d{4}$"#
        guard value.range(of: zipPlus4Pattern, options: .regularExpression) != nil else {
            return false
        }
        if isClearlyUnitedStates(countryName: countryName, countryCode: countryCode, regionOrStateName: regionOrStateName) {
            return true
        }
        return false
    }

    private static func isClearlyUnitedStates(
        countryName: String?,
        countryCode: String?,
        regionOrStateName: String?
    ) -> Bool {
        if normalizedCountryCode(countryCode) == "US" {
            return true
        }

        if let countryName = normalizedAddressComponent(countryName)?.lowercased(),
           unitedStatesAliases.contains(countryName) {
            return true
        }

        if let region = normalizedAddressComponent(regionOrStateName)?.uppercased(),
           unitedStatesStateAbbreviations.contains(region) {
            return true
        }

        return false
    }

    var hasStructuredDisplayFields: Bool {
        [
            streetNumber,
            streetName,
            cityOrTownName,
            postalCode,
            regionOrStateName,
            countryName,
            countryCode
        ]
        .contains { Address.normalizedAddressComponent($0) != nil }
    }

    var streetLine: String? {
        let components = [streetNumber, streetName]
            .compactMap { Address.normalizedAddressComponent($0) }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: " ")
    }

    var localizedCountryName: String? {
        if let countryName = Address.normalizedAddressComponent(countryName) {
            return countryName
        }

        guard let countryCode = Address.normalizedCountryCode(countryCode) else {
            return nil
        }
        return Locale.autoupdatingCurrent.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    func matches(regionCode: String?) -> Bool {
        guard let regionCode = Address.normalizedCountryCode(regionCode) else { return false }
        if Address.normalizedCountryCode(countryCode) == regionCode {
            return true
        }

        guard let countryName = Address.normalizedAddressComponent(countryName)?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent),
              let localizedRegion = Locale.autoupdatingCurrent.localizedString(forRegionCode: regionCode)?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent) else {
            return false
        }
        return countryName == localizedRegion
    }

    var isClearlyUnitedStates: Bool {
        Address.isClearlyUnitedStates(
            countryName: countryName,
            countryCode: countryCode,
            regionOrStateName: regionOrStateName
        )
    }

    static func merged(preferred: Address?, fallback: Address?) -> Address? {
        guard preferred != nil || fallback != nil else { return nil }

        func pick(_ preferredValue: String?, _ fallbackValue: String?) -> String? {
            normalizedAddressComponent(preferredValue) ?? normalizedAddressComponent(fallbackValue)
        }

        return Address(
            streetNumber: pick(preferred?.streetNumber, fallback?.streetNumber),
            streetName: pick(preferred?.streetName, fallback?.streetName),
            cityOrTownName: pick(preferred?.cityOrTownName, fallback?.cityOrTownName),
            postalCode: normalizedPostalCode(
                pick(preferred?.postalCode, fallback?.postalCode),
                countryName: pick(preferred?.countryName, fallback?.countryName),
                countryCode: pick(preferred?.countryCode, fallback?.countryCode),
                regionOrStateName: pick(preferred?.regionOrStateName, fallback?.regionOrStateName)
            ),
            regionOrStateName: pick(preferred?.regionOrStateName, fallback?.regionOrStateName),
            countryName: pick(preferred?.countryName, fallback?.countryName),
            countryCode: pick(preferred?.countryCode, fallback?.countryCode)
        )
    }

    static func needsEnrichment(_ address: Address?) -> Bool {
        guard let address else { return true }
        guard address.hasStructuredDisplayFields else { return true }

        return normalizedAddressComponent(address.cityOrTownName) == nil ||
            normalizedAddressComponent(address.regionOrStateName) == nil ||
            (normalizedAddressComponent(address.countryName) == nil &&
             normalizedAddressComponent(address.countryCode) == nil)
    }

    func postalAddress(includeCountry: Bool) -> CNPostalAddress? {
        guard hasStructuredDisplayFields else { return nil }

        let postalAddress = CNMutablePostalAddress()
        postalAddress.street = streetLine ?? ""
        postalAddress.city = Address.normalizedAddressComponent(cityOrTownName) ?? ""
        postalAddress.state = Address.normalizedAddressComponent(regionOrStateName) ?? ""
        postalAddress.postalCode = Address.normalizedAddressComponent(postalCode) ?? ""

        if includeCountry {
            postalAddress.country = localizedCountryName ?? ""
        }

        if let countryCode = Address.normalizedCountryCode(countryCode) {
            postalAddress.isoCountryCode = countryCode
        }

        return postalAddress
    }
}

struct FormattedAddress {
    let primaryLine: String?
    let secondaryLine: String?
    let multiline: String?
    let singleLine: String?
}

enum AddressDisplayStyle {
    case compact(referenceRegionCode: String?)
    case detail(includeCountry: Bool)
    case singleLine(includeCountry: Bool)
}

enum AddressDisplayFormatter {
    static func format(address: Address?, rawAddress: String?, style: AddressDisplayStyle) -> FormattedAddress? {
        if let address, address.hasStructuredDisplayFields {
            return formatStructured(address: address, style: style)
        }

        guard let rawAddress = Address.normalizedAddressComponent(rawAddress) else { return nil }
        return formatRaw(rawAddress, style: style)
    }

    private static func formatStructured(address: Address, style: AddressDisplayStyle) -> FormattedAddress? {
        let includeCountry: Bool
        switch style {
        case .compact(let referenceRegionCode):
            _ = referenceRegionCode
            includeCountry = false
        case .detail(let value), .singleLine(let value):
            includeCountry = value
        }

        let lines = postalLines(for: address, includeCountry: includeCountry)
        guard !lines.isEmpty else { return nil }

        switch style {
        case .compact:
            let adjustedLines = adjustedCompactLines(lines, address: address, includeCountry: includeCountry)
            let primaryLine = adjustedLines.first
            let secondaryLine = joinedLines(Array(adjustedLines.dropFirst()), separator: ", ")
            return FormattedAddress(
                primaryLine: primaryLine,
                secondaryLine: secondaryLine,
                multiline: joinedLines(adjustedLines, separator: "\n"),
                singleLine: joinedLines(adjustedLines, separator: ", ")
            )
        case .detail:
            let adjustedLines = adjustedDetailLines(lines, address: address, includeCountry: includeCountry)
            return FormattedAddress(
                primaryLine: adjustedLines.first,
                secondaryLine: joinedLines(Array(adjustedLines.dropFirst()), separator: "\n"),
                multiline: joinedLines(adjustedLines, separator: "\n"),
                singleLine: joinedLines(adjustedLines, separator: ", ")
            )
        case .singleLine:
            let adjustedLines = adjustedSingleLineLines(lines, address: address, includeCountry: includeCountry)
            let singleLine = joinedLines(adjustedLines, separator: ", ")
            return FormattedAddress(
                primaryLine: singleLine,
                secondaryLine: nil,
                multiline: singleLine,
                singleLine: singleLine
            )
        }
    }

    private static func postalLines(for address: Address, includeCountry: Bool) -> [String] {
        guard let postalAddress = address.postalAddress(includeCountry: includeCountry) else {
            return []
        }

        let formatted = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
        return formatted
            .components(separatedBy: .newlines)
            .compactMap(Address.normalizedAddressComponent)
    }

    private static func adjustedCompactLines(_ lines: [String], address: Address, includeCountry: Bool) -> [String] {
        guard address.isClearlyUnitedStates, !lines.isEmpty else { return lines }

        let primaryLine = Address.normalizedAddressComponent(address.streetLine)
        let city = Address.normalizedAddressComponent(address.cityOrTownName)
        let state = Address.normalizedAddressComponent(address.regionOrStateName)
        let postalCode = Address.normalizedAddressComponent(address.postalCode)
        let country = includeCountry ? Address.normalizedAddressComponent(address.localizedCountryName) : nil

        var localityParts: [String] = []
        if let city, let state {
            localityParts.append("\(city), \(state)")
        } else {
            localityParts.append(contentsOf: [city, state].compactMap { $0 })
        }
        if let postalCode {
            localityParts.append(postalCode)
        }

        let localityLine = joinedLines(localityParts, separator: " ")
        var adjusted: [String] = []
        if let primaryLine {
            adjusted.append(primaryLine)
        }
        if let localityLine {
            adjusted.append(localityLine)
        }
        if let country {
            adjusted.append(country)
        }
        return adjusted.isEmpty ? lines : adjusted
    }

    private static func adjustedDetailLines(_ lines: [String], address: Address, includeCountry: Bool) -> [String] {
        guard address.isClearlyUnitedStates, !lines.isEmpty else { return lines }
        return adjustedUnitedStatesLines(address: address, includeCountry: includeCountry, fallback: lines)
    }

    private static func adjustedSingleLineLines(_ lines: [String], address: Address, includeCountry: Bool) -> [String] {
        guard address.isClearlyUnitedStates, !lines.isEmpty else { return lines }
        return adjustedUnitedStatesLines(address: address, includeCountry: includeCountry, fallback: lines)
    }

    private static func adjustedUnitedStatesLines(address: Address, includeCountry: Bool, fallback: [String]) -> [String] {
        let primaryLine = Address.normalizedAddressComponent(address.streetLine)
        let city = Address.normalizedAddressComponent(address.cityOrTownName)
        let state = Address.normalizedAddressComponent(address.regionOrStateName)
        let postalCode = Address.normalizedAddressComponent(address.postalCode)
        let country = includeCountry ? Address.normalizedAddressComponent(address.localizedCountryName) : nil

        var localityParts: [String] = []
        if let city, let state {
            localityParts.append("\(city), \(state)")
        } else {
            localityParts.append(contentsOf: [city, state].compactMap { $0 })
        }
        if let postalCode {
            localityParts.append(postalCode)
        }

        let localityLine = joinedLines(localityParts, separator: " ")
        var adjusted: [String] = []
        if let primaryLine {
            adjusted.append(primaryLine)
        }
        if let localityLine {
            adjusted.append(localityLine)
        }
        if let country {
            adjusted.append(country)
        }
        return adjusted.isEmpty ? fallback : adjusted
    }

    private static func formatRaw(_ rawAddress: String, style: AddressDisplayStyle) -> FormattedAddress {
        let lines = rawAddress
            .components(separatedBy: .newlines)
            .compactMap(Address.normalizedAddressComponent)
        let collapsed = joinedLines(lines, separator: ", ") ?? rawAddress

        switch style {
        case .compact:
            return FormattedAddress(
                primaryLine: lines.first ?? rawAddress,
                secondaryLine: joinedLines(Array(lines.dropFirst()), separator: ", "),
                multiline: joinedLines(lines, separator: "\n") ?? rawAddress,
                singleLine: collapsed
            )
        case .detail:
            return FormattedAddress(
                primaryLine: lines.first ?? rawAddress,
                secondaryLine: joinedLines(Array(lines.dropFirst()), separator: "\n"),
                multiline: joinedLines(lines, separator: "\n") ?? rawAddress,
                singleLine: collapsed
            )
        case .singleLine:
            return FormattedAddress(
                primaryLine: collapsed,
                secondaryLine: nil,
                multiline: collapsed,
                singleLine: collapsed
            )
        }
    }

    private static func joinedLines(_ lines: [String], separator: String) -> String? {
        let filtered = lines.compactMap(Address.normalizedAddressComponent)
        guard !filtered.isEmpty else { return nil }
        return filtered.joined(separator: separator)
    }
}

extension Element {
    var rawAddress: String? {
        Address.normalizedAddressComponent(v4Metadata?.rawAddress)
    }

    func updatingAddress(_ address: Address?) -> Element {
        Element(
            id: id,
            osmJSON: osmJSON,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            address: address,
            v4Metadata: v4Metadata
        )
    }

    func formattedAddress(using resolvedAddress: Address?, style: AddressDisplayStyle) -> FormattedAddress? {
        if let address, address.hasStructuredDisplayFields {
            return AddressDisplayFormatter.format(address: resolvedAddress ?? address, rawAddress: nil, style: style)
        }

        if let rawAddress {
            return AddressDisplayFormatter.format(address: nil, rawAddress: rawAddress, style: style)
        }

        return AddressDisplayFormatter.format(address: resolvedAddress, rawAddress: nil, style: style)
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
    let addrCity, addrCountry, addrHousenumber, addrPostcode, addrState, addrStreet: String?
    let paymentBitcoin, currencyXBT, paymentOnchain, paymentLightning, paymentLightningContactless: String?
    let name, `operator`: String?
    let brand: String?
    let brandWikidata: String?
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
        case addrCountry = "addr:country"
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
        case brand
        case brandWikidata = "brand:wikidata"
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
