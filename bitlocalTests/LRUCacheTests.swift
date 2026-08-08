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

    func testConcurrentAccessDoesNotCrash() {
        let cache = LRUCache<String, Int>(maxSize: 50)
        let group = DispatchGroup()
        let iterations = 200

        for worker in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<iterations {
                    let key = "k\(i % 40)"
                    if worker % 2 == 0 {
                        cache.setValue(i, forKey: key)
                    } else {
                        _ = cache.getValue(forKey: key)
                    }
                }
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success)
        // Snapshot is well-formed after concurrent traffic
        XCTAssertLessThanOrEqual(cache.allValues().count, 50)
    }
}
