import Foundation

// Address caching to prevent geocoding rate limiting 
class LRUCache<Key: Hashable, Value> {
    private let maxSize: Int
    private var cache: [Key: CacheItem] = [:]
    private var lruKeys: [Key] = []
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    } 
    
    func getValue(forKey key: Key) -> Value? {
        guard let item = cache[key] else { return nil }
        
        // Move the accessed key to the end (most recently used)
        if let index = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: index)
            lruKeys.append(key)
        }
        
        return item.value
    }
    
    func setValue(_ value: Value, forKey key: Key) {
        // Evict the least recently used item if the cache is full
        if cache.count >= maxSize, let lruKey = lruKeys.first {
            cache.removeValue(forKey: lruKey)
            lruKeys.removeFirst()
        }
        
        cache[key] = CacheItem(value: value)
        lruKeys.append(key)
    }

    func allValues() -> [Key: Value] {
        return cache.mapValues { $0.value }
    }

    func setValues(_ values: [Key: Value]) {
        cache.removeAll()
        lruKeys.removeAll()
        for (key, value) in values {
            setValue(value, forKey: key)
        }
    }
    
    private struct CacheItem {
        let value: Value
    }
}
