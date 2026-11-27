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

    static let cuisine: [String: String] = [
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

    static let shop: [String: String] = [
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

    static let sport: [String: String] = [
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

    static let tourism: [String: String] = [
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

    static let office: [String: String] = [
        "coworking": "building.2.crop.circle"
    ]

    static let healthcare: [String: String] = [
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

    static let craft: [String: String] = [
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

    static let company: [String: String] = [
        "transport": "bus.fill",
        "farm": "carrot.fill"
    ]

    static let amenity: [String: String] = [
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

    static let place: [String: String] = [
        "farm": "carrot.fill"
    ]

    static let leisure: [String: String] = [
        "park": "tree.circle"
    ]

    static let building: [String: String] = [
        "farm": "carrot.fill",
        "church": "location.circle.fill"
    ]

    // Material-style v4 icon aliases -> OSM-like category keys used by this mapper.
    static let categoryIconAliases: [String: String] = [
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

    static let merchantCategoryDescriptors: [MerchantCategoryGroup: MerchantCategoryDescriptor] = [
        .coffee: MerchantCategoryDescriptor(
            group: .coffee,
            chipSymbolName: "cup.and.saucer.fill",
            priority: 0,
            searchAliases: ["cafe", "cafes", "coffee shop", "coffeehouse"],
            matchingTagValues: ["cafe", "coffee", "coffee_shop"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "cafe"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "coffee")
            ],
            iconOverrides: [],
            querySpecificTagFilters: [:]
        ),
        .food: MerchantCategoryDescriptor(
            group: .food,
            chipSymbolName: "fork.knife.circle.fill",
            priority: 1,
            searchAliases: [
                "restaurant", "restaurants", "pizza", "bakery", "bakeries",
                "pastry", "dessert", "desserts", "ice cream", "ice_cream",
                "fast food", "fast_food", "breakfast", "tapas", "cooking"
            ],
            matchingTagValues: [
                "restaurant", "pizza", "bakery", "pastry", "dessert", "ice_cream",
                "fast_food", "breakfast", "steak_house", "steak", "donut", "doughnut",
                "bagel", "bagel_shop", "sandwich", "burger", "hot_dog", "snacks",
                "cupcake", "tapas", "cooking", "seafood", "juice", "chocolate"
            ],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "restaurant"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "bakery"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "ice_cream"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "fast_food")
            ],
            iconOverrides: ["emoji_food_beverage"],
            querySpecificTagFilters: [
                "dessert": [
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "ice_cream"),
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "bakery")
                ],
                "desserts": [
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "ice_cream"),
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "bakery")
                ],
                "ice cream": [
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "ice_cream")
                ],
                "ice_cream": [
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "ice_cream")
                ],
                "bakery": [
                    MerchantCategoryTagFilter(tagKey: "shop", tagValue: "bakery")
                ],
                "pizza": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "restaurant")
                ],
                "tapas": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "restaurant")
                ]
            ]
        ),
        .bars: MerchantCategoryDescriptor(
            group: .bars,
            chipSymbolName: "wineglass",
            priority: 2,
            searchAliases: ["bar", "pub", "wine bar", "nightlife", "night club", "nightclub"],
            matchingTagValues: ["bar", "pub", "nightclub", "stripclub", "wine", "alcohol"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "bar"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "pub")
            ],
            iconOverrides: ["nightlife"],
            querySpecificTagFilters: [:]
        ),
        .groceries: MerchantCategoryDescriptor(
            group: .groceries,
            chipSymbolName: "cart.circle.fill",
            priority: 3,
            searchAliases: ["grocery", "grocery store", "supermarket", "convenience"],
            matchingTagValues: ["supermarket", "grocery", "convenience", "farm"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "supermarket"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "convenience")
            ],
            iconOverrides: ["shopping_cart"],
            querySpecificTagFilters: [:]
        ),
        .shopping: MerchantCategoryDescriptor(
            group: .shopping,
            chipSymbolName: "bag.circle",
            priority: 4,
            searchAliases: [
                "store", "stores", "retail", "mall", "gift", "jewelry",
                "pet", "pets", "diamond", "vape", "vaping", "smoking"
            ],
            matchingTagValues: [
                "yes", "department_store", "clothes", "gift", "jewelry", "computer",
                "electronics", "furniture", "mobile_phone", "photo", "books", "shoes",
                "hardware", "toys", "pet", "kiosk", "tobacco", "e-cigarette"
            ],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "yes"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "department_store")
            ],
            iconOverrides: ["diamond", "smoking_rooms", "vaping_rooms", "watch", "checkroom"],
            querySpecificTagFilters: [:]
        ),
        .finance: MerchantCategoryDescriptor(
            group: .finance,
            chipSymbolName: "bitcoinsign.circle.fill",
            priority: 5,
            searchAliases: ["atm", "atms", "bank", "banks", "exchange", "money", "cash"],
            matchingTagValues: ["atm", "bank", "bureau_de_change", "money_transfer", "payment_terminal", "bitcoin_office", "casino"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "atm"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "bank"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "bureau_de_change")
            ],
            iconOverrides: ["attach_money", "balance"],
            querySpecificTagFilters: [
                "exchange": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "bureau_de_change")
                ],
                "cash": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "atm")
                ]
            ]
        ),
        .hotels: MerchantCategoryDescriptor(
            group: .hotels,
            chipSymbolName: "bed.double.circle.fill",
            priority: 6,
            searchAliases: ["hotel", "hotels", "hostel", "guest house", "guesthouse", "motel", "camping"],
            matchingTagValues: ["hotel", "apartment", "apartments", "chalet", "camp_site", "motel", "guest_house", "hostel"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "tourism", tagValue: "hotel"),
                MerchantCategoryTagFilter(tagKey: "tourism", tagValue: "hostel")
            ],
            iconOverrides: ["luggage", "castle"],
            querySpecificTagFilters: [:]
        ),
        .beauty: MerchantCategoryDescriptor(
            group: .beauty,
            chipSymbolName: "scissors.circle.fill",
            priority: 7,
            searchAliases: ["beauty", "salon", "spa", "hair", "hairdresser", "cosmetics"],
            matchingTagValues: ["hairdresser", "beauty", "spa", "massage", "cosmetics", "cosmetic_surgery"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "hairdresser"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "beauty"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "spa")
            ],
            iconOverrides: ["colorize"],
            querySpecificTagFilters: [:]
        ),
        .health: MerchantCategoryDescriptor(
            group: .health,
            chipSymbolName: "cross.circle.fill",
            priority: 8,
            searchAliases: ["health", "clinic", "doctor", "dentist", "pharmacy", "hospital", "medical"],
            matchingTagValues: [
                "pharmacy", "clinic", "hospital", "doctor", "doctors",
                "dentist", "alternative", "physiotherapist", "therapist",
                "psychotherapist", "optometrist", "sample_collection"
            ],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "pharmacy"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "clinic"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "hospital"),
                MerchantCategoryTagFilter(tagKey: "healthcare", tagValue: "dentist")
            ],
            iconOverrides: ["dentistry"],
            querySpecificTagFilters: [
                "dentist": [
                    MerchantCategoryTagFilter(tagKey: "healthcare", tagValue: "dentist")
                ],
                "dentistry": [
                    MerchantCategoryTagFilter(tagKey: "healthcare", tagValue: "dentist")
                ],
                "pharmacy": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "pharmacy")
                ]
            ]
        ),
        .auto: MerchantCategoryDescriptor(
            group: .auto,
            chipSymbolName: "car.circle.fill",
            priority: 9,
            searchAliases: ["gas", "gas station", "fuel", "car repair", "charging", "car wash", "auto"],
            matchingTagValues: ["fuel", "car_repair", "car", "car_wash", "car_rental", "charging_station", "motorcycle", "motorcycle_rental", "boat_rental", "taxi"],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "fuel"),
                MerchantCategoryTagFilter(tagKey: "shop", tagValue: "car_repair"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "charging_station")
            ],
            iconOverrides: ["minor_crash"],
            querySpecificTagFilters: [
                "gas": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "fuel")
                ],
                "gas station": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "fuel")
                ],
                "charging": [
                    MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "charging_station")
                ]
            ]
        ),
        .services: MerchantCategoryDescriptor(
            group: .services,
            chipSymbolName: "wrench.adjustable.fill",
            priority: 10,
            searchAliases: ["services", "service", "printing", "cleaning", "home services", "repair", "construction"],
            matchingTagValues: [
                "office", "coworking", "transport", "plumber", "electrician",
                "carpenter", "photographer", "electronics_repair", "painter"
            ],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "office", tagValue: "coworking")
            ],
            iconOverrides: ["build", "cleaning_services", "engineering", "home", "local_printshop", "plumbing", "construction", "electrical_services", "roofing", "window", "hvac", "architecture", "design_services", "dns", "warehouse", "cell_tower", "lock", "mail", "edit"],
            querySpecificTagFilters: [:]
        ),
        .recreation: MerchantCategoryDescriptor(
            group: .recreation,
            chipSymbolName: "figure.run.circle.fill",
            priority: 11,
            searchAliases: ["park", "sports", "music", "art", "attractions", "museum", "games", "cinema", "recreation"],
            matchingTagValues: [
                "park", "sports", "fitness", "cycling", "golf", "tennis", "soccer",
                "art", "music", "gallery", "attraction", "cinema", "theatre"
            ],
            remoteTagFilters: [
                MerchantCategoryTagFilter(tagKey: "leisure", tagValue: "park"),
                MerchantCategoryTagFilter(tagKey: "tourism", tagValue: "attraction"),
                MerchantCategoryTagFilter(tagKey: "amenity", tagValue: "cinema")
            ],
            iconOverrides: ["attractions", "games", "mic", "museum", "local_movies", "golf_course", "sports_martial_arts", "sports_score", "piano", "beach_access", "pool", "sauna", "sailing", "directions_boat", "directions_walk", "volunteer_activism", "public", "science", "imagesearch_roller", "hive", "church", "celebration", "adult_content", "outdoor_grill"],
            querySpecificTagFilters: [:]
        )
    ]
}
