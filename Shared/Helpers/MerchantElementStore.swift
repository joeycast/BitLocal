import Foundation

/// Authoritative merchant catalog store keyed by place id.
///
/// Replaces repeated `Dictionary(uniqueKeysWithValues: allElements…)` rebuilds for
/// single-element upserts. Maintains insertion-stable order so `snapshot()` is O(n)
/// (copy) rather than O(n log n) sort — full-catalog sorts on every hydrate/upsert
/// were too expensive at ~25k merchants.
final class MerchantElementStore {
    private var byID: [String: Element] = [:]
    /// First-seen id order. Updated elements keep their position; new ids append.
    private var orderedIDs: [String] = []
    private(set) var revision: UInt64 = 0

    var count: Int { byID.count }
    var isEmpty: Bool { byID.isEmpty }

    /// O(1) lookup.
    func element(id: String) -> Element? {
        byID[id]
    }

    /// Current catalog snapshot for UI / map in stable first-seen order.
    /// O(n) copy, no sort.
    func snapshot() -> [Element] {
        orderedIDs.compactMap { byID[$0] }
    }

    /// O(1) index access for bulk operations that already hold the store.
    func dictionary() -> [String: Element] {
        byID
    }

    @discardableResult
    func replaceAll(_ elements: [Element]) -> UInt64 {
        var nextByID: [String: Element] = [:]
        var nextOrder: [String] = []
        nextByID.reserveCapacity(elements.count)
        nextOrder.reserveCapacity(elements.count)

        for element in elements {
            if nextByID[element.id] == nil {
                nextOrder.append(element.id)
            }
            // Last write wins for duplicate ids; keep first-seen position.
            nextByID[element.id] = element
        }

        byID = nextByID
        orderedIDs = nextOrder
        revision &+= 1
        return revision
    }

    @discardableResult
    func upsert(_ element: Element) -> UInt64 {
        if byID[element.id] == nil {
            orderedIDs.append(element.id)
        }
        byID[element.id] = element
        revision &+= 1
        return revision
    }

    @discardableResult
    func upsertMany(_ elements: [Element]) -> UInt64 {
        guard !elements.isEmpty else { return revision }
        for element in elements {
            if byID[element.id] == nil {
                orderedIDs.append(element.id)
            }
            byID[element.id] = element
        }
        revision &+= 1
        return revision
    }

    @discardableResult
    func remove(id: String) -> UInt64 {
        guard byID.removeValue(forKey: id) != nil else { return revision }
        if let index = orderedIDs.firstIndex(of: id) {
            orderedIDs.remove(at: index)
        }
        revision &+= 1
        return revision
    }

    func elements(ids: [String]) -> [Element] {
        ids.compactMap { byID[$0] }
    }
}
