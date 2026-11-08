import Foundation

/// A merchant's category, keyed by the BTC Map v4 `icon` (a Material icon name
/// such as `local_cafe`). Symbol and label lookup live in the app's category
/// catalog; the domain only needs identity and a few predicates.
public struct MerchantCategory: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(icon: String?) {
        self.init(rawValue: icon ?? "")
    }

    public static let unknown = MerchantCategory(rawValue: "")

    public var isUnknown: Bool { rawValue.isEmpty || rawValue == "question_mark" }

    /// Bitcoin ATMs (not banks or exchanges). Drives the "Hide ATMs" setting.
    public var isATM: Bool { rawValue == "local_atm" || rawValue == "atm" }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
