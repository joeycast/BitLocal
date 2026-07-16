import XCTest
@testable import bitlocal

final class MerchantSearchPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MerchantSearchPersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndLoadCategoryWithinTTL() {
        MerchantSearchPersistence.saveCategoryGroup(.coffee, defaults: defaults)
        let loaded = MerchantSearchPersistence.loadCategoryGroup(defaults: defaults)
        XCTAssertEqual(loaded, .coffee)
    }

    func testExpiredCategoryIsCleared() {
        MerchantSearchPersistence.saveCategoryGroup(.food, defaults: defaults)
        defaults.set(
            Date().timeIntervalSince1970 - MerchantSearchPersistence.categoryTTL - 10,
            forKey: "merchant_search_last_category_saved_at"
        )
        XCTAssertNil(MerchantSearchPersistence.loadCategoryGroup(defaults: defaults))
    }

    func testClearRemovesCategory() {
        MerchantSearchPersistence.saveCategoryGroup(.bars, defaults: defaults)
        MerchantSearchPersistence.clear(defaults: defaults)
        XCTAssertNil(MerchantSearchPersistence.loadCategoryGroup(defaults: defaults))
    }
}
