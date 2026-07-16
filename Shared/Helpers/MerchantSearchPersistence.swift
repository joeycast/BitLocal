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
    private static let savedAtKey = "merchant_search_last_category_saved_at"
    /// Category chips are cheap local filters — keep for a week of return visits.
    static let categoryTTL: TimeInterval = 7 * 24 * 60 * 60

    static func saveCategoryGroup(_ group: MerchantCategoryGroup?, defaults: UserDefaults = .standard) {
        if let group {
            defaults.set(group.rawValue, forKey: categoryKey)
            defaults.set(Date().timeIntervalSince1970, forKey: savedAtKey)
        } else {
            clear(defaults: defaults)
        }
    }

    static func loadCategoryGroup(defaults: UserDefaults = .standard, now: Date = Date()) -> MerchantCategoryGroup? {
        guard let raw = defaults.string(forKey: categoryKey),
              let group = MerchantCategoryGroup(rawValue: raw) else {
            return nil
        }
        let savedAt = defaults.double(forKey: savedAtKey)
        guard savedAt > 0 else {
            clear(defaults: defaults)
            return nil
        }
        let age = now.timeIntervalSince1970 - savedAt
        guard age >= 0, age <= categoryTTL else {
            clear(defaults: defaults)
            return nil
        }
        return group
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: categoryKey)
        defaults.removeObject(forKey: savedAtKey)
    }
}
