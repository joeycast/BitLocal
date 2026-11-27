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

enum MerchantChipFilterEngine {
    /// Applies unified multi-select chip filters to a list of merchants:
    /// - Quick attribute filters (`Open Now`, `Lightning`, `NFC`, `Verified`, `Saved`) combine with **AND**.
    /// - Category filters (`Food`, `Coffee`, `Bars`, …) combine with **OR**.
    /// - Attribute filters and category filters combine with **AND**.
    static func filter(
        _ elements: [Element],
        quickFilters: Set<MerchantQuickFilter>,
        categoryFilters: Set<MerchantCategoryGroup>,
        savedIDs: Set<String> = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Element] {
        guard !quickFilters.isEmpty || !categoryFilters.isEmpty else { return elements }

        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)
            ?? now.addingTimeInterval(-365 * 24 * 60 * 60)

        let requiresSaved = quickFilters.contains(.saved)
        let requiresLightning = quickFilters.contains(.lightning)
        let requiresNFC = quickFilters.contains(.nfc)
        let requiresVerified = quickFilters.contains(.verified)
        let requiresOpenNow = quickFilters.contains(.openNow)
        let hasCategoryFilters = !categoryFilters.isEmpty

        return elements.filter { element in
            if requiresSaved && !savedIDs.contains(element.id) {
                return false
            }
            if requiresLightning && !acceptsLightning(element: element) {
                return false
            }
            if requiresNFC && !acceptsContactlessLightning(element: element) {
                return false
            }
            if requiresVerified {
                guard let verifiedDate = BTCMapDateParser.parse(element.v4Metadata?.verifiedAt),
                      verifiedDate >= oneYearAgo else {
                    return false
                }
            }
            if requiresOpenNow {
                guard OpeningHoursLiveStatus.isOpenNow(
                    rawOpeningHours: element.osmJSON?.tags?.openingHours,
                    now: now,
                    calendar: calendar
                ) else {
                    return false
                }
            }
            if hasCategoryFilters {
                let groups = ElementCategorySymbols.merchantCategoryGroups(for: element)
                if categoryFilters.isDisjoint(with: groups) {
                    return false
                }
            }
            return true
        }
    }

    /// Computes visible category chips for the current viewport while keeping any
    /// actively selected categories pinned first (even if 0 matches exist in the
    /// current viewport) so users can always see and clear active filters.
    static func visibleCategoryChips(
        for viewportElements: [Element],
        selectedCategories: Set<MerchantCategoryGroup>,
        limit: Int = 6
    ) -> [MerchantCategoryChip] {
        let baseChips = ElementCategorySymbols.merchantCategoryChips(for: viewportElements, limit: limit)
        guard !selectedCategories.isEmpty else { return baseChips }

        let baseByGroup = Dictionary(uniqueKeysWithValues: baseChips.map { ($0.group, $0) })

        let selectedOrdered = selectedCategories
            .sorted {
                ElementCategorySymbols.merchantCategoryDescriptor(for: $0).priority
                    < ElementCategorySymbols.merchantCategoryDescriptor(for: $1).priority
            }
            .map { group -> MerchantCategoryChip in
                if let existing = baseByGroup[group] {
                    return existing
                }
                return MerchantCategoryChip(
                    group: group,
                    count: 0,
                    symbolName: ElementCategorySymbols.merchantCategoryDescriptor(for: group).chipSymbolName
                )
            }

        let remaining = baseChips.filter { !selectedCategories.contains($0.group) }
        return selectedOrdered + remaining
    }
}
