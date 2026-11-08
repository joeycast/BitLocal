import Foundation

/// A street address, parsed at ingest from v4 `address` and OSM `addr:*` fields.
public struct PostalAddress: Hashable, Sendable, Codable {
    public var houseNumber: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    /// The unparsed single-line address from BTC Map, when OSM parts are missing.
    public var freeform: String?

    public init(
        houseNumber: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        postalCode: String? = nil,
        freeform: String? = nil
    ) {
        self.houseNumber = houseNumber.nonEmpty
        self.street = street.nonEmpty
        self.city = city.nonEmpty
        self.state = state.nonEmpty
        self.postalCode = PostalAddress.normalizedPostalCode(postalCode)
        self.freeform = freeform.nonEmpty
    }

    public var isEmpty: Bool {
        houseNumber == nil && street == nil && city == nil && state == nil && postalCode == nil && freeform == nil
    }

    /// "123 Main St" (or the freeform address when no street is known).
    public var streetLine: String? {
        if let street {
            if let houseNumber { return "\(houseNumber) \(street)" }
            return street
        }
        return freeform
    }

    /// "Nashville, TN 37203".
    public var localityLine: String? {
        let cityState = [city, state].compactMap { $0 }.joined(separator: ", ")
        let parts = [cityState.isEmpty ? nil : cityState, postalCode].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// One line suitable for copy and share.
    public var singleLine: String? {
        let parts = [streetLine, localityLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// US ZIP+4 is shortened to 5 digits; everything else is kept as typed.
    static func normalizedPostalCode(_ value: String?) -> String? {
        guard let trimmed = value.nonEmpty else { return nil }
        if trimmed.range(of: #"^\d{5}-\d{4}$"#, options: .regularExpression) != nil {
            return String(trimmed.prefix(5))
        }
        return trimmed
    }
}

/// Ways to reach a merchant directly.
public struct Contact: Hashable, Sendable, Codable {
    public var phone: String?
    public var website: URL?
    public var email: String?

    public init(phone: String? = nil, website: URL? = nil, email: String? = nil) {
        self.phone = phone.nonEmpty
        self.website = website
        self.email = email.nonEmpty
    }

    public var isEmpty: Bool { phone == nil && website == nil && email == nil }
}

/// A social profile link.
public struct SocialLink: Hashable, Sendable, Codable {
    public enum Network: String, Hashable, Sendable, Codable, CaseIterable {
        case twitter, facebook, instagram, telegram, line
    }

    public var network: Network
    public var url: URL

    public init(network: Network, url: URL) {
        self.network = network
        self.url = url
    }
}

extension Optional where Wrapped == String {
    /// Trimmed value, or nil when missing or blank.
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
