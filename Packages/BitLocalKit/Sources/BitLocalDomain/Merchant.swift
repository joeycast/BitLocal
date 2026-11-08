import Foundation

/// The light merchant shape used by the map, clusters, list rows and cards.
/// Equality and hashing use `id` + `updatedAt`, so SwiftUI diffing is cheap
/// and still notices a merchant that changed in a sync.
public struct MerchantSummary: Identifiable, Sendable, Codable {
    public let id: MerchantID
    public let coordinate: Coordinate
    /// Never empty: falls back to the category name at ingest (see `MerchantMapper`).
    public let name: String
    /// True when `name` is a real merchant name and not a category fallback.
    public let hasRealName: Bool
    public let category: MerchantCategory
    public let paymentMethods: PaymentMethods
    public let boostedUntil: Date?
    /// Raw OSM `opening_hours` string; parsed by the hours formatter when shown.
    public let openingHours: String?
    public let updatedAt: Date

    public init(
        id: MerchantID,
        coordinate: Coordinate,
        name: String,
        hasRealName: Bool,
        category: MerchantCategory,
        paymentMethods: PaymentMethods,
        boostedUntil: Date?,
        openingHours: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.hasRealName = hasRealName
        self.category = category
        self.paymentMethods = paymentMethods
        self.boostedUntil = boostedUntil
        self.openingHours = openingHours
        self.updatedAt = updatedAt
    }

    /// Time-dependent, so it takes a date instead of being stored.
    public func isBoosted(at date: Date) -> Bool {
        guard let boostedUntil else { return false }
        return boostedUntil > date
    }
}

extension MerchantSummary: Hashable {
    public static func == (lhs: MerchantSummary, rhs: MerchantSummary) -> Bool {
        lhs.id == rhs.id && lhs.updatedAt == rhs.updatedAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(updatedAt)
    }
}

/// The full merchant shape for the detail screen. A primary-key read.
public struct Merchant: Identifiable, Sendable, Codable {
    public let summary: MerchantSummary
    public let address: PostalAddress?
    public let contact: Contact
    public let socials: [SocialLink]
    public let about: String?
    public let imageURL: URL?
    public let requiredAppURL: URL?
    public let verifiedAt: Date?
    public let commentsCount: Int
    public let osmURL: URL?
    /// False when only the thin CDN snapshot fields are known.
    public let isHydrated: Bool

    public var id: MerchantID { summary.id }

    public init(
        summary: MerchantSummary,
        address: PostalAddress? = nil,
        contact: Contact = Contact(),
        socials: [SocialLink] = [],
        about: String? = nil,
        imageURL: URL? = nil,
        requiredAppURL: URL? = nil,
        verifiedAt: Date? = nil,
        commentsCount: Int = 0,
        osmURL: URL? = nil,
        isHydrated: Bool
    ) {
        self.summary = summary
        self.address = address
        self.contact = contact
        self.socials = socials
        self.about = about
        self.imageURL = imageURL
        self.requiredAppURL = requiredAppURL
        self.verifiedAt = verifiedAt
        self.commentsCount = commentsCount
        self.osmURL = osmURL
        self.isHydrated = isHydrated
    }
}

extension Merchant: Hashable {
    public static func == (lhs: Merchant, rhs: Merchant) -> Bool {
        lhs.summary == rhs.summary && lhs.isHydrated == rhs.isHydrated
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(summary)
        hasher.combine(isHydrated)
    }
}
