import Foundation

/// Authoritative merchant catalog store keyed by place id.
///
/// Replaces repeated `Dictionary(uniqueKeysWithValues: allElements…)` rebuilds for
/// single-element upserts. Callers publish `snapshot()` to SwiftUI when needed.
final class MerchantElementStore {
    private var byID: [String: Element] = [:]
    private(set) var revision: UInt64 = 0

    var count: Int { byID.count }
    var isEmpty: Bool { byID.isEmpty }

    /// O(1) lookup.
    func element(id: String) -> Element? {
        byID[id]
    }

    /// Current catalog snapshot for UI / map. Builds an array of values.
    func snapshot() -> [Element] {
        Array(byID.values)
    }

    /// O(1) index access for bulk operations that already hold the store.
    func dictionary() -> [String: Element] {
        byID
    }

    @discardableResult
    func replaceAll(_ elements: [Element]) -> UInt64 {
        byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        revision &+= 1
        return revision
    }

    @discardableResult
    func upsert(_ element: Element) -> UInt64 {
        byID[element.id] = element
        revision &+= 1
        return revision
    }

    @discardableResult
    func upsertMany(_ elements: [Element]) -> UInt64 {
        guard !elements.isEmpty else { return revision }
        for element in elements {
            byID[element.id] = element
        }
        revision &+= 1
        return revision
    }

    @discardableResult
    func remove(id: String) -> UInt64 {
        if byID.removeValue(forKey: id) != nil {
            revision &+= 1
        }
        return revision
    }

    func elements(ids: [String]) -> [Element] {
        ids.compactMap { byID[$0] }
    }
}
