import XCTest
@testable import bitlocal

final class LRUCacheTests: XCTestCase {
    func testUpdatingExistingKeyDoesNotEvictOtherEntries() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        cache.setValue(3, forKey: "a")

        XCTAssertEqual(cache.getValue(forKey: "a"), 3)
        XCTAssertEqual(cache.getValue(forKey: "b"), 2)
    }

    func testLeastRecentlyUsedEntryEvictsAfterUpdateRefreshesRecency() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        _ = cache.getValue(forKey: "a")
        cache.setValue(3, forKey: "c")

        XCTAssertEqual(cache.getValue(forKey: "a"), 1)
        XCTAssertNil(cache.getValue(forKey: "b"))
        XCTAssertEqual(cache.getValue(forKey: "c"), 3)
    }
}
