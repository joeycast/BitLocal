import Foundation

struct BusinessSubmission: Codable {
    // Submitter Information
    var submitterName: String = ""
    var submitterEmail: String = ""
    var relationship: SubmitterRelationship = .owner

    // Business Information
    var businessName: String = ""
    var businessDescription: String = ""

    // Address Information
    var streetNumber: String = ""
    var streetName: String = ""
    var city: String = ""
    var stateProvince: String = ""
    var country: String = ""
    var postalCode: String = ""

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

    private func isValidEmail(_ email: String) -> Bool {
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
