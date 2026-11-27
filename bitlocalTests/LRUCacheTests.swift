import Testing
@testable import bitlocal

@Suite(.tags(.persistence))
struct LRUCacheTests {
    @Test func updatingExistingKeyDoesNotEvictOtherEntries() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        cache.setValue(3, forKey: "a")

        #expect(cache.getValue(forKey: "a") == 3)
        #expect(cache.getValue(forKey: "b") == 2)
    }

    @Test func leastRecentlyUsedEntryEvictsAfterUpdateRefreshesRecency() {
        let cache = LRUCache<String, Int>(maxSize: 2)

        cache.setValue(1, forKey: "a")
        cache.setValue(2, forKey: "b")
        _ = cache.getValue(forKey: "a")
        cache.setValue(3, forKey: "c")

        #expect(cache.getValue(forKey: "a") == 1)
        #expect(cache.getValue(forKey: "b") == nil)
        #expect(cache.getValue(forKey: "c") == 3)
    }

    @Test func concurrentAccessDoesNotCrash() async {
        let cache = LRUCache<String, Int>(maxSize: 50)
        let iterations = 200

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for i in 0..<iterations {
                        let key = "k\(i % 40)"
                        if worker % 2 == 0 {
                            cache.setValue(i, forKey: key)
                        } else {
                            _ = cache.getValue(forKey: key)
                        }
                    }
                }
            }
        }

        // Snapshot is well-formed after concurrent traffic
        #expect(cache.allValues().count <= 50)
    }
}
