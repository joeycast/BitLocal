import SwiftUI

struct MerchantCategoryTagFilter: Hashable {
    let tagKey: String
    let tagValue: String
}

enum MerchantCategoryGroup: String, CaseIterable, Identifiable {
    case coffee
    case food
    case bars
    case groceries
    case shopping
    case finance
    case hotels
    case beauty
    case health
    case auto
    case services
    case recreation

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .coffee: String(localized: "Coffee")
        case .food: String(localized: "Food")
        case .bars: String(localized: "Bars")
        case .groceries: String(localized: "Groceries")
        case .shopping: String(localized: "Shopping")
        case .finance: String(localized: "Finance")
        case .hotels: String(localized: "Hotels")
        case .beauty: String(localized: "Beauty")
        case .health: String(localized: "Health")
        case .auto: String(localized: "Auto")
        case .services: String(localized: "Services")
        case .recreation: String(localized: "Recreation")
        }
    }
}

struct MerchantCategoryDescriptor {
    let group: MerchantCategoryGroup
    let chipSymbolName: String
    let priority: Int
    let searchAliases: [String]
    let matchingTagValues: [String]
    let remoteTagFilters: [MerchantCategoryTagFilter]
    let iconOverrides: [String]
    let querySpecificTagFilters: [String: [MerchantCategoryTagFilter]]
}

struct MerchantCategoryChip: Identifiable, Hashable {
    let group: MerchantCategoryGroup
    let count: Int
    let symbolName: String

    var id: String { group.id }
    var localizedLabel: String { group.localizedLabel }
}
