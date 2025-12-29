import Foundation

enum OSMFeatureType: String, CaseIterable, Codable, Identifiable {
    case unset
    case amenityRestaurant
    case amenityCafe
    case amenityBar
    case amenityPub
    case amenityFastFood
    case amenityBank
    case amenityAtm
    case amenityPharmacy
    case amenityClinic
    case amenityDoctors
    case amenityDentist
    case amenityHospital
    case amenityFuel
    case amenityChargingStation
    case amenityParking
    case amenityLibrary
    case amenitySchool
    case amenityTheatre
    case amenityCinema
    case amenityNightclub
    case amenityMarketplace
    case shopSupermarket
    case shopConvenience
    case shopBakery
    case shopClothes
    case shopShoes
    case shopElectronics
    case shopComputer
    case shopMobilePhone
    case shopHardware
    case shopFurniture
    case shopFlorist
    case shopGift
    case shopBooks
    case shopAlcohol
    case shopPet
    case shopSports
    case shopBicycle
    case shopCar
    case shopCarParts
    case shopBeauty
    case shopHairdresser
    case shopJewelry
    case shopFarm
    case shopTattoo
    case shopLaundry
    case tourismHotel
    case tourismCampSite
    case tourismHostel
    case tourismGuestHouse
    case tourismMuseum
    case tourismGallery
    case tourismAttraction
    case leisurePark
    case leisureStadium
    case leisureFitnessCentre
    case leisureSwimmingPool
    case leisureGolfCourse
    case leisureSportsCentre
    case craftBrewery
    case craftWinery
    case craftDistillery
    case craftCarpenter
    case craftTailor
    case craftShoemaker
    case craftJeweller
    case craftInstrument
    case officeCoworking
    case officeTravelAgent
    case healthcarePhysiotherapist
    case healthcareOptometrist
    case custom

    var id: String { rawValue }

    static let groupedOptions: [(String, [OSMFeatureType])] = [
        ("osm_feature_group_amenity", [
            .amenityRestaurant,
            .amenityCafe,
            .amenityBar,
            .amenityPub,
            .amenityFastFood,
            .amenityBank,
            .amenityAtm,
            .amenityPharmacy,
            .amenityClinic,
            .amenityDoctors,
            .amenityDentist,
            .amenityHospital,
            .amenityFuel,
            .amenityChargingStation,
            .amenityParking,
            .amenityLibrary,
            .amenitySchool,
            .amenityTheatre,
            .amenityCinema,
            .amenityNightclub,
            .amenityMarketplace
        ]),
        ("osm_feature_group_shop", [
            .shopSupermarket,
            .shopConvenience,
            .shopBakery,
            .shopClothes,
            .shopShoes,
            .shopElectronics,
            .shopComputer,
            .shopMobilePhone,
            .shopHardware,
            .shopFurniture,
            .shopFlorist,
            .shopGift,
            .shopBooks,
            .shopAlcohol,
            .shopPet,
            .shopSports,
            .shopBicycle,
            .shopCar,
            .shopCarParts,
            .shopBeauty,
            .shopHairdresser,
            .shopJewelry,
            .shopFarm,
            .shopTattoo,
            .shopLaundry
        ]),
        ("osm_feature_group_tourism", [
            .tourismHotel,
            .tourismCampSite,
            .tourismHostel,
            .tourismGuestHouse,
            .tourismMuseum,
            .tourismGallery,
            .tourismAttraction
        ]),
        ("osm_feature_group_leisure", [
            .leisurePark,
            .leisureStadium,
            .leisureFitnessCentre,
            .leisureSwimmingPool,
            .leisureGolfCourse,
            .leisureSportsCentre
        ]),
        ("osm_feature_group_craft", [
            .craftBrewery,
            .craftWinery,
            .craftDistillery,
            .craftCarpenter,
            .craftTailor,
            .craftShoemaker,
            .craftJeweller,
            .craftInstrument
        ]),
        ("osm_feature_group_office", [
            .officeCoworking,
            .officeTravelAgent
        ]),
        ("osm_feature_group_healthcare", [
            .healthcarePhysiotherapist,
            .healthcareOptometrist
        ]),
        ("osm_feature_group_other", [.custom]),
        ("osm_feature_group_general", [.unset])
    ]

    var localizedKey: String {
        switch self {
        case .unset: return "osm_feature_type_unset"
        case .amenityRestaurant: return "osm_feature_type_amenity_restaurant"
        case .amenityCafe: return "osm_feature_type_amenity_cafe"
        case .amenityBar: return "osm_feature_type_amenity_bar"
        case .amenityPub: return "osm_feature_type_amenity_pub"
        case .amenityFastFood: return "osm_feature_type_amenity_fast_food"
        case .amenityBank: return "osm_feature_type_amenity_bank"
        case .amenityAtm: return "osm_feature_type_amenity_atm"
        case .amenityPharmacy: return "osm_feature_type_amenity_pharmacy"
        case .amenityClinic: return "osm_feature_type_amenity_clinic"
        case .amenityDoctors: return "osm_feature_type_amenity_doctors"
        case .amenityDentist: return "osm_feature_type_amenity_dentist"
        case .amenityHospital: return "osm_feature_type_amenity_hospital"
        case .amenityFuel: return "osm_feature_type_amenity_fuel"
        case .amenityChargingStation: return "osm_feature_type_amenity_charging_station"
        case .amenityParking: return "osm_feature_type_amenity_parking"
        case .amenityLibrary: return "osm_feature_type_amenity_library"
        case .amenitySchool: return "osm_feature_type_amenity_school"
        case .amenityTheatre: return "osm_feature_type_amenity_theatre"
        case .amenityCinema: return "osm_feature_type_amenity_cinema"
        case .amenityNightclub: return "osm_feature_type_amenity_nightclub"
        case .amenityMarketplace: return "osm_feature_type_amenity_marketplace"
        case .shopSupermarket: return "osm_feature_type_shop_supermarket"
        case .shopConvenience: return "osm_feature_type_shop_convenience"
        case .shopBakery: return "osm_feature_type_shop_bakery"
        case .shopClothes: return "osm_feature_type_shop_clothes"
        case .shopShoes: return "osm_feature_type_shop_shoes"
        case .shopElectronics: return "osm_feature_type_shop_electronics"
        case .shopComputer: return "osm_feature_type_shop_computer"
        case .shopMobilePhone: return "osm_feature_type_shop_mobile_phone"
        case .shopHardware: return "osm_feature_type_shop_hardware"
        case .shopFurniture: return "osm_feature_type_shop_furniture"
        case .shopFlorist: return "osm_feature_type_shop_florist"
        case .shopGift: return "osm_feature_type_shop_gift"
        case .shopBooks: return "osm_feature_type_shop_books"
        case .shopAlcohol: return "osm_feature_type_shop_alcohol"
        case .shopPet: return "osm_feature_type_shop_pet"
        case .shopSports: return "osm_feature_type_shop_sports"
        case .shopBicycle: return "osm_feature_type_shop_bicycle"
        case .shopCar: return "osm_feature_type_shop_car"
        case .shopCarParts: return "osm_feature_type_shop_car_parts"
        case .shopBeauty: return "osm_feature_type_shop_beauty"
        case .shopHairdresser: return "osm_feature_type_shop_hairdresser"
        case .shopJewelry: return "osm_feature_type_shop_jewelry"
        case .shopFarm: return "osm_feature_type_shop_farm"
        case .shopTattoo: return "osm_feature_type_shop_tattoo"
        case .shopLaundry: return "osm_feature_type_shop_laundry"
        case .tourismHotel: return "osm_feature_type_tourism_hotel"
        case .tourismCampSite: return "osm_feature_type_tourism_camp_site"
        case .tourismHostel: return "osm_feature_type_tourism_hostel"
        case .tourismGuestHouse: return "osm_feature_type_tourism_guest_house"
        case .tourismMuseum: return "osm_feature_type_tourism_museum"
        case .tourismGallery: return "osm_feature_type_tourism_gallery"
        case .tourismAttraction: return "osm_feature_type_tourism_attraction"
        case .leisurePark: return "osm_feature_type_leisure_park"
        case .leisureStadium: return "osm_feature_type_leisure_stadium"
        case .leisureFitnessCentre: return "osm_feature_type_leisure_fitness_centre"
        case .leisureSwimmingPool: return "osm_feature_type_leisure_swimming_pool"
        case .leisureGolfCourse: return "osm_feature_type_leisure_golf_course"
        case .leisureSportsCentre: return "osm_feature_type_leisure_sports_centre"
        case .craftBrewery: return "osm_feature_type_craft_brewery"
        case .craftWinery: return "osm_feature_type_craft_winery"
        case .craftDistillery: return "osm_feature_type_craft_distillery"
        case .craftCarpenter: return "osm_feature_type_craft_carpenter"
        case .craftTailor: return "osm_feature_type_craft_tailor"
        case .craftShoemaker: return "osm_feature_type_craft_shoemaker"
        case .craftJeweller: return "osm_feature_type_craft_jeweller"
        case .craftInstrument: return "osm_feature_type_craft_instrument"
        case .officeCoworking: return "osm_feature_type_office_coworking"
        case .officeTravelAgent: return "osm_feature_type_office_travel_agent"
        case .healthcarePhysiotherapist: return "osm_feature_type_healthcare_physiotherapist"
        case .healthcareOptometrist: return "osm_feature_type_healthcare_optometrist"
        case .custom: return "osm_feature_type_custom"
        }
    }

    var osmTagKey: String? {
        switch self {
        case .unset, .custom: return nil
        case .amenityRestaurant,
             .amenityCafe,
             .amenityBar,
             .amenityPub,
             .amenityFastFood,
             .amenityBank,
             .amenityAtm,
             .amenityPharmacy,
             .amenityClinic,
             .amenityDoctors,
             .amenityDentist,
             .amenityHospital,
             .amenityFuel,
             .amenityChargingStation,
             .amenityParking,
             .amenityLibrary,
             .amenitySchool,
             .amenityTheatre,
             .amenityCinema,
             .amenityNightclub,
             .amenityMarketplace:
            return "amenity"
        case .shopSupermarket,
             .shopConvenience,
             .shopBakery,
             .shopClothes,
             .shopShoes,
             .shopElectronics,
             .shopComputer,
             .shopMobilePhone,
             .shopHardware,
             .shopFurniture,
             .shopFlorist,
             .shopGift,
             .shopBooks,
             .shopAlcohol,
             .shopPet,
             .shopSports,
             .shopBicycle,
             .shopCar,
             .shopCarParts,
             .shopBeauty,
             .shopHairdresser,
             .shopJewelry,
             .shopFarm,
             .shopTattoo,
             .shopLaundry:
            return "shop"
        case .tourismHotel,
             .tourismCampSite,
             .tourismHostel,
             .tourismGuestHouse,
             .tourismMuseum,
             .tourismGallery,
             .tourismAttraction:
            return "tourism"
        case .leisurePark,
             .leisureStadium,
             .leisureFitnessCentre,
             .leisureSwimmingPool,
             .leisureGolfCourse,
             .leisureSportsCentre:
            return "leisure"
        case .craftBrewery,
             .craftWinery,
             .craftDistillery,
             .craftCarpenter,
             .craftTailor,
             .craftShoemaker,
             .craftJeweller,
             .craftInstrument:
            return "craft"
        case .officeCoworking,
             .officeTravelAgent:
            return "office"
        case .healthcarePhysiotherapist,
             .healthcareOptometrist:
            return "healthcare"
        }
    }

    var osmTagValue: String? {
        switch self {
        case .unset, .custom: return nil
        case .amenityRestaurant: return "restaurant"
        case .amenityCafe: return "cafe"
        case .amenityBar: return "bar"
        case .amenityPub: return "pub"
        case .amenityFastFood: return "fast_food"
        case .amenityBank: return "bank"
        case .amenityAtm: return "atm"
        case .amenityPharmacy: return "pharmacy"
        case .amenityClinic: return "clinic"
        case .amenityDoctors: return "doctors"
        case .amenityDentist: return "dentist"
        case .amenityHospital: return "hospital"
        case .amenityFuel: return "fuel"
        case .amenityChargingStation: return "charging_station"
        case .amenityParking: return "parking"
        case .amenityLibrary: return "library"
        case .amenitySchool: return "school"
        case .amenityTheatre: return "theatre"
        case .amenityCinema: return "cinema"
        case .amenityNightclub: return "nightclub"
        case .amenityMarketplace: return "marketplace"
        case .shopSupermarket: return "supermarket"
        case .shopConvenience: return "convenience"
        case .shopBakery: return "bakery"
        case .shopClothes: return "clothes"
        case .shopShoes: return "shoes"
        case .shopElectronics: return "electronics"
        case .shopComputer: return "computer"
        case .shopMobilePhone: return "mobile_phone"
        case .shopHardware: return "hardware"
        case .shopFurniture: return "furniture"
        case .shopFlorist: return "florist"
        case .shopGift: return "gift"
        case .shopBooks: return "books"
        case .shopAlcohol: return "alcohol"
        case .shopPet: return "pet"
        case .shopSports: return "sports"
        case .shopBicycle: return "bicycle"
        case .shopCar: return "car"
        case .shopCarParts: return "car_parts"
        case .shopBeauty: return "beauty"
        case .shopHairdresser: return "hairdresser"
        case .shopJewelry: return "jewelry"
        case .shopFarm: return "farm"
        case .shopTattoo: return "tattoo"
        case .shopLaundry: return "laundry"
        case .tourismHotel: return "hotel"
        case .tourismCampSite: return "camp_site"
        case .tourismHostel: return "hostel"
        case .tourismGuestHouse: return "guest_house"
        case .tourismMuseum: return "museum"
        case .tourismGallery: return "gallery"
        case .tourismAttraction: return "attraction"
        case .leisurePark: return "park"
        case .leisureStadium: return "stadium"
        case .leisureFitnessCentre: return "fitness_centre"
        case .leisureSwimmingPool: return "swimming_pool"
        case .leisureGolfCourse: return "golf_course"
        case .leisureSportsCentre: return "sports_centre"
        case .craftBrewery: return "brewery"
        case .craftWinery: return "winery"
        case .craftDistillery: return "distillery"
        case .craftCarpenter: return "carpenter"
        case .craftTailor: return "tailor"
        case .craftShoemaker: return "shoemaker"
        case .craftJeweller: return "jeweller"
        case .craftInstrument: return "instrument"
        case .officeCoworking: return "coworking"
        case .officeTravelAgent: return "travel_agent"
        case .healthcarePhysiotherapist: return "physiotherapist"
        case .healthcareOptometrist: return "optometrist"
        }
    }
}

struct BusinessSubmission: Codable {
    // Submitter Information
    var submitterName: String = ""
    var submitterEmail: String = ""
    var relationship: SubmitterRelationship = .owner

    // Business Information
    var businessName: String = ""
    var businessDescription: String = ""
    var osmFeatureType: OSMFeatureType = .unset
    var osmCustomTag: String = ""

    // Address Information
    var streetNumber: String = ""
    var streetName: String = ""
    var city: String = ""
    var stateProvince: String = ""
    var country: String = ""
    var postalCode: String = ""
    var latitude: Double?
    var longitude: Double?

    // Contact Information
    var phoneNumber: String = ""
    var phoneCountryCode: String = "+1"
    var website: String = ""

    // Business Hours (optional)
    var weeklyHours = WeeklyHours()

    // Accepted Bitcoin Payment Methods (all required, at least one must be true)
    var acceptsOnChain: Bool = false
    var acceptsLightning: Bool = false
    var acceptsContactlessLightning: Bool = false

    enum SubmitterRelationship: String, CaseIterable, Codable {
        case owner = "Owner"
        case customer = "Customer"

        var localizedKey: String {
            switch self {
            case .owner: return "submitter_relationship_owner"
            case .customer: return "submitter_relationship_customer"
            }
        }
    }
}

// MARK: - Validation
extension BusinessSubmission {
    var isValid: Bool {
        !submitterName.isEmpty &&
        isValidEmail(submitterEmail) &&
        !businessName.isEmpty &&
        !streetNumber.isEmpty &&
        !streetName.isEmpty &&
        !city.isEmpty &&
        !stateProvince.isEmpty &&
        !country.isEmpty &&
        hasAtLeastOneBitcoinPayment &&
        isWebsiteValidIfProvided
    }

    var hasAtLeastOneBitcoinPayment: Bool {
        acceptsOnChain || acceptsLightning || acceptsContactlessLightning
    }

    var isWebsiteValidIfProvided: Bool {
        website.isEmpty || website.cleanedWebsiteURL() != nil
    }

    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    func validationErrors() -> [ValidationError] {
        var errors: [ValidationError] = []

        if submitterName.isEmpty {
            errors.append(.missingField("submitter_name_label"))
        }
        if !isValidEmail(submitterEmail) {
            errors.append(.invalidEmail)
        }
        if businessName.isEmpty {
            errors.append(.missingField("business_name_label"))
        }
        if streetNumber.isEmpty {
            errors.append(.missingField("street_number_label"))
        }
        if streetName.isEmpty {
            errors.append(.missingField("street_name_label"))
        }
        if city.isEmpty {
            errors.append(.missingField("city_label"))
        }
        if stateProvince.isEmpty {
            errors.append(.missingField("state_province_label"))
        }
        if country.isEmpty {
            errors.append(.missingField("country_label"))
        }
        if !hasAtLeastOneBitcoinPayment {
            errors.append(.noBitcoinPaymentMethod)
        }
        if !isWebsiteValidIfProvided {
            errors.append(.invalidWebsite)
        }

        return errors
    }

    func emailBody() -> String {
        var lines: [String] = []

        // Submitter info (not OSM tags, just context)
        lines.append("=== SUBMITTER INFORMATION ===")
        lines.append("Name: \(submitterName)")
        lines.append("Email: \(submitterEmail)")
        lines.append("Relationship: \(relationship.rawValue)")
        lines.append("")

        // Coordinates
        if let lat = latitude, let lon = longitude {
            lines.append("=== COORDINATES ===")
            lines.append("Latitude: \(lat)")
            lines.append("Longitude: \(lon)")
            lines.append("OSM URL: https://www.openstreetmap.org/?mlat=\(lat)&mlon=\(lon)#map=18/\(lat)/\(lon)")
            lines.append("")
        }

        // OpenStreetMap tags
        lines.append("=== OPENSTREETMAP TAGS ===")

        // Address
        if !city.isEmpty {
            lines.append("addr:city=\(city)")
        }
        if !streetNumber.isEmpty {
            lines.append("addr:housenumber=\(streetNumber)")
        }
        if !postalCode.isEmpty {
            lines.append("addr:postcode=\(postalCode)")
        }
        if !stateProvince.isEmpty {
            lines.append("addr:state=\(stateProvince)")
        }
        if !streetName.isEmpty {
            lines.append("addr:street=\(streetName)")
        }

        // Add check_date (today's date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        lines.append("check_date=\(today)")
        lines.append("check_date:currency:XBT=\(today)")

        // Contact info
        if !phoneNumber.isEmpty {
            let fullPhone = "\(phoneCountryCode)\(phoneNumber)"
            lines.append("contact:phone=\(fullPhone)")
        }
        if let websiteURL = website.cleanedWebsiteURL() {
            lines.append("contact:website=\(websiteURL.absoluteString)")
        }

        // Currency and payment
        lines.append("currency:XBT=yes")

        // Description
        if !businessDescription.isEmpty {
            lines.append("description=\(businessDescription)")
        }

        // Business name
        lines.append("name=\(businessName)")

        // Feature type
        if osmFeatureType == .custom {
            let customTag = osmCustomTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !customTag.isEmpty {
                if customTag.contains("=") {
                    lines.append(customTag)
                } else {
                    lines.append("custom_category=\(customTag)")
                }
            }
        } else if let key = osmFeatureType.osmTagKey,
                  let value = osmFeatureType.osmTagValue {
            lines.append("\(key)=\(value)")
        }

        // Opening hours
        let hoursString = weeklyHours.toOSMFormat()
        if !hoursString.isEmpty {
            lines.append("opening_hours=\(hoursString)")
        }

        // Payment methods
        lines.append("payment:lightning=\(acceptsLightning ? "yes" : "no")")
        if acceptsContactlessLightning {
            lines.append("payment:lightning_contactless=yes")
        }
        lines.append("payment:onchain=\(acceptsOnChain ? "yes" : "no")")

        return lines.joined(separator: "\n")
    }

    enum ValidationError: Identifiable {
        case missingField(String)
        case invalidEmail
        case invalidWebsite
        case noBitcoinPaymentMethod

        var id: String {
            switch self {
            case .missingField(let field): return "missing_\(field)"
            case .invalidEmail: return "invalid_email"
            case .invalidWebsite: return "invalid_website"
            case .noBitcoinPaymentMethod: return "no_bitcoin_payment"
            }
        }

        var localizedKey: String {
            switch self {
            case .missingField: return "validation_error_missing_field"
            case .invalidEmail: return "validation_error_invalid_email"
            case .invalidWebsite: return "validation_error_invalid_website"
            case .noBitcoinPaymentMethod: return "validation_error_no_bitcoin_payment"
            }
        }
    }
}
