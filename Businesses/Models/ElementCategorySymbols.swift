//
//  ElementCategorySymbols.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/31/25.
//
//  Adapted from BTC Map's ElementSystemImages.swift https://github.com/teambtcmap/btcmap-ios/blob/main/BTCMap/ElementSystemImages.swift
//


import SwiftUI

/// A helper that returns a SwiftUI Image (SF Symbol) for a given Element’s OSM tags,
/// falling back to a generic location/bitcoin symbol if nothing else matches.
struct ElementCategorySymbols {
    // MARK: - Mapping Dictionaries

    private static let cuisine: [String: String] = [
        "wok": "fork.knife.circle.fill",
        "sushi": "fork.knife.circle.fill",
        "burger": "fork.knife.circle.fill",
        "hot_dog": "fork.knife.circle.fill",
        "pizza": "fork.knife.circle.fill",
        "coffee_shop": "fork.knife.circle.fill",
        "coffee": "fork.knife.circle.fill",
        "chicken": "fork.knife.circle.fill",
        "italian": "fork.knife.circle.fill",
        "sandwich": "fork.knife.circle.fill",
        "japanese": "fork.knife.circle.fill",
        "curry": "fork.knife.circle.fill",
        "raw_food": "fork.knife.circle.fill",
        "organic": "fork.knife.circle.fill",
        "american": "fork.knife.circle.fill",
        "crepe": "fork.knife.circle.fill",
        "kebab": "fork.knife.circle.fill",
        "juice": "fork.knife.circle.fill",
        "ice_cream": "fork.knife.circle.fill",
        "barbecue": "fork.knife.circle.fill",
        "dessert": "fork.knife.circle.fill",
        "donut": "fork.knife.circle.fill",
        "doughnut": "fork.knife.circle.fill",
        "noodle": "fork.knife.circle.fill",
        "pasta": "fork.knife.circle.fill",
        "bakery": "fork.knife.circle.fill",
        "snacks": "fork.knife.circle.fill",
        "cupcake": "fork.knife.circle.fill",
        "bagel": "fork.knife.circle.fill",
        "bagel_shop": "fork.knife.circle.fill",
        "russian": "fork.knife.circle.fill",
        "steak_house": "fork.knife.circle.fill",
        "steak": "fork.knife.circle.fill",
        "chinese": "fork.knife.circle.fill",
        "thai": "fork.knife.circle.fill",
        "asian": "fork.knife.circle.fill",
        "mexican": "fork.knife.circle.fill",
        "breakfast": "fork.knife.circle.fill",
    ]

    private static let shop: [String: String] = [
        "computer": "tv.circle.fill",
        "clothes": "bag.circle",
        "jewelry": "location.circle.fill",
        "hairdresser": "scissors.circle.fill",
        "yes": "bag.circle",
        "electronics": "tv.circle.fill",
        "supermarket": "cart.circle.fill",
        "beauty": "mouth.fill",
        "car_repair": "minus.plus.batteryblock.exclamationmark.fill",
        "books": "books.vertical.fill",
        "convenience": "bag.circle",
        "furniture": "sofa.fill",
        "travel_agency": "globe.americas.fill",
        "gift": "gift.fill",
        "mobile_phone": "iphone.circle",
        "pastry": "fork.knife.circle.fill",
        "cosmetics": "location.circle.fill",
        "coffee": "cup.and.saucer.fill",
        "beverages": "fork.knife.circle.fill",
        "stationery": "paperclip.circle.fill",
        "department_store": "bag.circle",
        "chocolate": "fork.knife.circle.fill",
        "scuba_diving": "water.waves",
        "video": "video.circle",
        "motorcycle": "figure.outdoor.cycle",
        "seafood": "fork.knife.circle.fill",
        "surf": "figure.surfing",
        "grocery": "cart.circle.fill",
        "car": "car.circle.fill",
        "tobacco": "location.circle.fill",
        "bakery": "birthday.cake.fill",
        "massage": "location.circle.fill",
        "florist": "camera.macro",
        "e-cigarette": "location.circle.fill",
        "optician": "eyeglasses",
        "photo": "camera.circle.fill",
        "farm": "carrot.fill",
        "sports": "tennis.racket.circle.fill",
        "music": "music.mic.circle.fill",
        "art": "paintpalette.fill",
        "shoes": "bag.circle",
        "wine": "wineglass",
        "hardware": "screwdriver.fill",
        "car_parts": "car.circle.fill",
        "toys": "teddybear.fill",
        "cannabis": "leaf.circle.fill",
        "alcohol": "wineglass",
        "pet": "pawprint.fill",
        "kiosk": "location.circle.fill",
        "laundry": "washer.fill"
    ]

    private static let sport: [String: String] = [
        "basketball": "sportscourt.fill",
        "swimming": "drop.circle.fill",
        "gymnastics": "figure.gymnastic.flowers",
        "boxing": "figure.boxing",
        "mma": "figure.boxing",
        "ice_hockey": "hockey.puck.circle.fill",
        "roller_skating": "figure.outdoor.cycle", // substitute
        "baseball": "figure.baseball",
        "cricket": "figure.cricket",
        "rugby": "sportscourt.fill",
        "volleyball": "sportscourt.fill",
        "running": "figure.run",
        "bodybuilding": "figure.strengthtraining.traditional",
        "skiing": "figure.skiing.crosscountry",
        "snowboarding": "figure.snowboarding",
        "fitness": "figure.run.circle.fill",
        "crossfit": "figure.run.circle.fill",
        "yoga": "figure.run.circle.fill",
        "equestrian": "figure.equestrian.sports",
        "scuba_diving": "water.waves",
        "paragliding": "cloud.fill",
        "parachuting": "cloud.fill",
        "shooting": "figure.hunting",
        "climbing": "figure.climbing",
        "soccer": "soccerball",
        "football": "soccerball",
        "darts": "trophy.fill",
        "billiards": "trophy.fill",
        "surfing": "figure.surfing",
        "skateboard": "figure.skating",
        "jiu-jitsu": "figure.martial.arts",
        "golf": "figure.golf",
        "cycling": "figure.outdoor.cycle",
        "tennis": "tennisball.fill",
    ]

    private static let tourism: [String: String] = [
        "hotel": "bed.double.circle.fill",
        "apartment": "bed.double.circle.fill",
        "chalet": "bed.double.circle.fill",
        "camp_site": "tent.2.circle.fill",
        "motel": "bed.double.circle.fill",
        "apartments": "bed.double.circle.fill",
        "guest_house": "bed.double.circle.fill",
        "hostel": "bed.double.circle.fill",
        "attraction": "location.circle.fill",
        "artwork": "photo.circle",
        "information": "info.circle",
        "gallery": "paintpalette.fill"
    ]

    private static let office: [String: String] = [
        "coworking": "building.2.crop.circle"
    ]

    private static let healthcare: [String: String] = [
        "dentist": "cross.circle.fill",
        "doctor": "cross.circle.fill",
        "alternative": "leaf.circle.fill",
        "clinic": "cross.circle.fill",
        "pharmacy": "pill.circle.fill",
        "psychotherapist": "cross.case.circle.fill",
        "hospital": "cross.circle.fill",
        "physiotherapist": "cross.circle.fill",
        "counselling": "cross.case.circle.fill",
        "optometrist": "eye.circle.fill",
        "sample_collection": "cross.vial.fill",
        "cosmetic_surgery": "nose.fill",
        "therapist": "cross.case.circle.fill"
    ]

    private static let craft: [String: String] = [
        "photographer": "camera.circle.fill",
        "electronics_repair": "tv.circle.fill",
        "electrician": "poweroutlet.type.g.fill",
        "painter": "photo.circle",
        "carpenter": "hammer.fill",
        "sculptor": "person.bust.fill",
        "plumber": "wrench.adjustable.fill",
        "jeweller": "location.circle.fill",
        "glaziery": "location.circle.fill",
        "shoemaker": "location.circle.fill"
    ]

    private static let company: [String: String] = [
        "transport": "bus.fill",
        "farm": "carrot.fill"
    ]

    private static let amenity: [String: String] = [
        "restaurant": "fork.knife.circle.fill",
        "atm": "bitcoinsign.circle.fill",
        "cafe": "cup.and.saucer.fill",
        "bar": "wineglass",
        "bureau_de_change": "bitcoinsign.circle.fill",
        "fast_food": "fork.knife.circle.fill",
        "bank": "bitcoinsign.circle.fill",
        "dentist": "location.circle.fill",
        "pub": "fork.knife.circle.fill",
        "fuel": "fuelpump.fill",
        "doctors": "cross.circle.fill",
        "pharmacy": "pill.fill",
        "taxi": "car.side.fill",
        "clinic": "cross.circle.fill",
        "car_rental": "car.circle.fill",
        "casino": "bitcoinsign.circle.fill",
        "notary": "location.circle.fill",
        "dancing_school": "figure.socialdance",
        "stripclub": "figure.dance",
        "nightclub": "figure.socialdance",
        "motorcycle_rental": "figure.outdoor.cycle",
        "payment_terminal": "bitcoinsign.circle.fill",
        "charging_station": "car.circle.fill",
        "training": "figure.strengthtraining.traditional",
        "bitcoin_office": "bitcoinsign.circle.fill",
        "office": "building.2.crop.circle",
        "language_school": "globe.americas.fill",
        "community_centre": "person.2.circle.fill",
        "school": "graduationcap.fill",
        "veterinary": "pawprint.fill",
        "ice_cream": "fork.knife.circle.fill",
        "hospital": "cross.circle.fill",
        "boat_rental": "sailboat.fill",
        "money_transfer": "bitcoinsign.circle.fill",
        "marketplace": "bag.circle",
        "arts_centre": "paintpalette.fill",
        "college": "graduationcap.fill",
        "coworking_space": "building.2.crop.circle",
        "car_wash": "car.circle.fill",
        "university": "graduationcap.fill",
        "spa": "location.circle.fill",
        "post_office": "envelope.fill",
        "swingerclub": "party.popper.fill",
        "cinema": "popcorn.fill",
        "bicycle.circle.fill_rental": "bicycle.circle.fill",
        "theatre": "theatermasks.fill",
        "recycling": "tree.circle",
        "library": "books.vertical.fill",
        "parking": "parkingsign.circle",
        "police": "location.circle.fill"
    ]

    private static let place: [String: String] = [
        "farm": "carrot.fill"
    ]

    private static let leisure: [String: String] = [
        "park": "tree.circle"
    ]

    private static let building: [String: String] = [
        "farm": "carrot.fill",
        "church": "location.circle.fill"
    ]

    // Material-style v4 icon aliases -> OSM-like category keys used by this mapper.
    private static let categoryIconAliases: [String: String] = [
        "local_cafe": "cafe",
        "coffee": "cafe",
        "restaurant": "restaurant",
        "lunch_dining": "restaurant",
        "local_pizza": "pizza",
        "bakery_dining": "bakery",
        "local_bar": "bar",
        "sports_bar": "bar",
        "wine_bar": "bar",
        "hotel": "hotel",
        "chalet": "chalet",
        "local_atm": "atm",
        "currency_exchange": "bureau_de_change",
        "account_balance": "bank",
        "local_grocery_store": "grocery",
        "local_mall": "department_store",
        "storefront": "yes",
        "computer": "computer",
        "business": "office",
        "medical_services": "clinic",
        "local_pharmacy": "pharmacy",
        "spa": "spa",
        "content_cut": "hairdresser",
        "fitness_center": "fitness",
        "sports": "sports",
        "pedal_bike": "cycling",
        "two_wheeler": "motorcycle",
        "directions_car": "car",
        "car_repair": "car_repair",
        "local_car_wash": "car_wash",
        "local_gas_station": "fuel",
        "liquor": "alcohol",
        "icecream": "ice_cream",
        "local_florist": "florist",
        "hardware": "hardware",
        "pets": "pet",
        "photo_camera": "photo",
        "smartphone": "mobile_phone",
        "chair": "furniture",
        "card_giftcard": "gift",
        "palette": "art",
        "music_note": "music",
        "school": "school",
        "group": "community_centre",
        "tour": "travel_agency",
        "camping": "camp_site",
        "grass": "park",
        "factory": "transport"
    ]

    // MARK: - Internal Lookup

    /// Iterates over the components of a semicolon-separated tag value
    /// and returns the first matching Image found in `map`.
    private static func lookupSymbolName(in map: [String: String], forTagValue value: String) -> String? {
        let components = value.lowercased().components(separatedBy: ";")
        for component in components {
            let key = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if let symbolName = map[key] {
                return symbolName
            }
        }
        return nil
    }

    /// Resolve a BTC Map category/icon slug into an OSM tag key/value pair
    /// that this symbol mapper can use (for example `("amenity", "cafe")`).
    static func osmTagAssignment(forCategoryIcon icon: String?) -> (tagKey: String, tagValue: String)? {
        guard let icon else { return nil }
        let baseCandidates = icon
            .lowercased()
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var candidates = baseCandidates
        for candidate in baseCandidates {
            if let alias = categoryIconAliases[candidate], !alias.isEmpty {
                candidates.append(alias)
            }
        }

        for candidate in candidates {
            if cuisine[candidate] != nil { return ("cuisine", candidate) }
            if shop[candidate] != nil { return ("shop", candidate) }
            if sport[candidate] != nil { return ("sport", candidate) }
            if tourism[candidate] != nil { return ("tourism", candidate) }
            if healthcare[candidate] != nil { return ("healthcare", candidate) }
            if craft[candidate] != nil { return ("craft", candidate) }
            if amenity[candidate] != nil { return ("amenity", candidate) }
            if office[candidate] != nil { return ("office", candidate) }
            if place[candidate] != nil { return ("place", candidate) }
            if leisure[candidate] != nil { return ("leisure", candidate) }
            if building[candidate] != nil { return ("building", candidate) }
            if company[candidate] != nil { return ("company", candidate) }
        }

        return nil
    }

    static func symbolName(forCategoryIcon icon: String?) -> String? {
        guard let assignment = osmTagAssignment(forCategoryIcon: icon) else { return nil }
        switch assignment.tagKey {
        case "cuisine": return lookupSymbolName(in: cuisine, forTagValue: assignment.tagValue)
        case "shop": return lookupSymbolName(in: shop, forTagValue: assignment.tagValue)
        case "sport": return lookupSymbolName(in: sport, forTagValue: assignment.tagValue)
        case "tourism": return lookupSymbolName(in: tourism, forTagValue: assignment.tagValue)
        case "healthcare": return lookupSymbolName(in: healthcare, forTagValue: assignment.tagValue)
        case "craft": return lookupSymbolName(in: craft, forTagValue: assignment.tagValue)
        case "amenity": return lookupSymbolName(in: amenity, forTagValue: assignment.tagValue)
        case "office": return lookupSymbolName(in: office, forTagValue: assignment.tagValue)
        case "place": return lookupSymbolName(in: place, forTagValue: assignment.tagValue)
        case "leisure": return lookupSymbolName(in: leisure, forTagValue: assignment.tagValue)
        case "building": return lookupSymbolName(in: building, forTagValue: assignment.tagValue)
        case "company": return lookupSymbolName(in: company, forTagValue: assignment.tagValue)
        default: return nil
        }
    }

    /// Returns a SwiftUI Image for an Element based on its OSM tags.
    static func image(for element: Element, renderingMode: Image.TemplateRenderingMode = .original) -> Image {
        let tags = element.osmTagsDict

        if let cuisineValue = tags?["cuisine"],
           let symbol = lookupSymbolName(in: cuisine, forTagValue: cuisineValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let shopValue = tags?["shop"],
           let symbol = lookupSymbolName(in: shop, forTagValue: shopValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let sportValue = tags?["sport"],
           let symbol = lookupSymbolName(in: sport, forTagValue: sportValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let tourismValue = tags?["tourism"],
           let symbol = lookupSymbolName(in: tourism, forTagValue: tourismValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let healthcareValue = tags?["healthcare"],
           let symbol = lookupSymbolName(in: healthcare, forTagValue: healthcareValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let craftValue = tags?["craft"],
           let symbol = lookupSymbolName(in: craft, forTagValue: craftValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let amenityValue = tags?["amenity"],
           let symbol = lookupSymbolName(in: amenity, forTagValue: amenityValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let officeValue = tags?["office"],
           let symbol = lookupSymbolName(in: office, forTagValue: officeValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let placeValue = tags?["place"],
           let symbol = lookupSymbolName(in: place, forTagValue: placeValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let leisureValue = tags?["leisure"],
           let symbol = lookupSymbolName(in: leisure, forTagValue: leisureValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let buildingValue = tags?["building"],
           let symbol = lookupSymbolName(in: building, forTagValue: buildingValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let companyValue = tags?["company"],
           let symbol = lookupSymbolName(in: company, forTagValue: companyValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let iconSymbol = symbolName(forCategoryIcon: element.v4Metadata?.icon ?? element.tags?.iconAndroid) {
            return Image(systemName: iconSymbol).renderingMode(renderingMode)
        }

        // Fallback if nothing matched:
        return Image(systemName: "bitcoinsign.circle.fill").renderingMode(renderingMode)
    }

    /// Returns the SF Symbol name for an Element by inspecting its OSM tags.
    static func symbolName(for element: Element) -> String {
        let tagsDict = element.osmTagsDict
        // 1) cuisine
        if let cuisineValue = tagsDict?["cuisine"],
           let name = lookupSymbolName(in: cuisine, forTagValue: cuisineValue) {
            return name
        }
        // 2) shop
        if let shopValue = tagsDict?["shop"],
           let name = lookupSymbolName(in: shop, forTagValue: shopValue) {
            return name
        }
        // 3) sport
        if let sportValue = tagsDict?["sport"],
           let name = lookupSymbolName(in: sport, forTagValue: sportValue) {
            return name
        }
        // 4) tourism
        if let tourismValue = tagsDict?["tourism"],
           let name = lookupSymbolName(in: tourism, forTagValue: tourismValue) {
            return name
        }
        // 5) healthcare
        if let healthcareValue = tagsDict?["healthcare"],
           let name = lookupSymbolName(in: healthcare, forTagValue: healthcareValue) {
            return name
        }
        // 6) craft
        if let craftValue = tagsDict?["craft"],
           let name = lookupSymbolName(in: craft, forTagValue: craftValue) {
            return name
        }
        // 7) amenity
        if let amenityValue = tagsDict?["amenity"],
           let name = lookupSymbolName(in: amenity, forTagValue: amenityValue) {
            return name
        }
        // 8) office
        if let officeValue = tagsDict?["office"],
           let name = lookupSymbolName(in: office, forTagValue: officeValue) {
            return name
        }
        // 9) place
        if let placeValue = tagsDict?["place"],
           let name = lookupSymbolName(in: place, forTagValue: placeValue) {
            return name
        }
        // 10) leisure
        if let leisureValue = tagsDict?["leisure"],
           let name = lookupSymbolName(in: leisure, forTagValue: leisureValue) {
            return name
        }
        // 11) building
        if let buildingValue = tagsDict?["building"],
           let name = lookupSymbolName(in: building, forTagValue: buildingValue) {
            return name
        }
        // 12) company
        if let companyValue = tagsDict?["company"],
           let name = lookupSymbolName(in: company, forTagValue: companyValue) {
            return name
        }
        if let iconSymbol = symbolName(forCategoryIcon: element.v4Metadata?.icon ?? element.tags?.iconAndroid) {
            return iconSymbol
        }
        // Fallback
        return "bitcoinsign.circle.fill"
    }
}
