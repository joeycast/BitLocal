import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.persistence, .search))
final class MerchantSearchPersistenceTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "MerchantSearchPersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func saveAndLoadCategoryWithinTTL() {
        MerchantSearchPersistence.saveCategoryGroup(.coffee, defaults: defaults)
        let loaded = MerchantSearchPersistence.loadCategoryGroup(defaults: defaults)
        #expect(loaded == .coffee)
    }

    @Test func expiredCategoryIsCleared() {
        MerchantSearchPersistence.saveCategoryGroup(.food, defaults: defaults)
        defaults.set(
            Date.now.timeIntervalSince1970 - MerchantSearchPersistence.categoryTTL - 10,
            forKey: "merchant_search_last_category_saved_at"
        )
        #expect(MerchantSearchPersistence.loadCategoryGroup(defaults: defaults) == nil)
    }

    @Test func clearRemovesCategory() {
        MerchantSearchPersistence.saveCategoryGroup(.bars, defaults: defaults)
        MerchantSearchPersistence.clear(defaults: defaults)
        #expect(MerchantSearchPersistence.loadCategoryGroup(defaults: defaults) == nil)
    }
}
