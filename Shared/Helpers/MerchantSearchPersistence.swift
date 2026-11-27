import Foundation

/// Lightweight persistence for merchant search UX.
///
/// Product policy:
/// - Persist **category chip** selection only (not free-text queries).
/// - Restoring free-text could auto-fire expensive worldwide search on launch.
/// - Clear when the user explicitly clears search or dismisses search.
/// - Category restore is allowed for 7 days after last selection.
enum MerchantSearchPersistence {
    private static let categoryKey = "merchant_search_last_category_group"
    private static let categoriesKey = "merchant_search_last_category_groups"
    private static let savedAtKey = "merchant_search_last_category_saved_at"
    /// Category chips are cheap local filters — keep for a week of return visits.
    static let categoryTTL: TimeInterval = 7 * 24 * 60 * 60

    static func saveCategoryGroups(
        _ groups: Set<MerchantCategoryGroup>,
        defaults: UserDefaults = .standard
    ) {
        guard !groups.isEmpty else {
            clear(defaults: defaults)
            return
        }
        let sortedRaw = groups.map(\.rawValue).sorted()
        defaults.set(sortedRaw, forKey: categoriesKey)
        defaults.set(sortedRaw.first, forKey: categoryKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: savedAtKey)
    }

    static func loadCategoryGroups(
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) -> Set<MerchantCategoryGroup> {
        let savedAt = defaults.double(forKey: savedAtKey)
        guard savedAt > 0 else {
            clear(defaults: defaults)
            return []
        }
        let age = now.timeIntervalSince1970 - savedAt
        guard age >= 0, age <= categoryTTL else {
            clear(defaults: defaults)
            return []
        }

        if let rawList = defaults.stringArray(forKey: categoriesKey) {
            let parsed = Set(rawList.compactMap(MerchantCategoryGroup.init(rawValue:)))
            if !parsed.isEmpty {
                return parsed
            }
        }

        if let legacyRaw = defaults.string(forKey: categoryKey),
           let legacyGroup = MerchantCategoryGroup(rawValue: legacyRaw) {
            return [legacyGroup]
        }

        clear(defaults: defaults)
        return []
    }

    static func saveCategoryGroup(_ group: MerchantCategoryGroup?, defaults: UserDefaults = .standard) {
        if let group {
            saveCategoryGroups([group], defaults: defaults)
        } else {
            clear(defaults: defaults)
        }
    }

    static func loadCategoryGroup(defaults: UserDefaults = .standard, now: Date = .now) -> MerchantCategoryGroup? {
        loadCategoryGroups(defaults: defaults, now: now).sorted { $0.rawValue < $1.rawValue }.first
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: categoryKey)
        defaults.removeObject(forKey: categoriesKey)
        defaults.removeObject(forKey: savedAtKey)
    }
}
