import Foundation

/// BTC Map v4 place id. Identity for every merchant in the app.
public struct MerchantID: RawRepresentable, Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }

    /// Parses the string ids the legacy `Element` model uses ("1234").
    public init?(string: String) {
        guard let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.rawValue = value
    }

    public var description: String { String(rawValue) }

    public static func < (lhs: MerchantID, rhs: MerchantID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// BTC Map area id for a community.
public struct CommunityID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }

    public var description: String { String(rawValue) }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
