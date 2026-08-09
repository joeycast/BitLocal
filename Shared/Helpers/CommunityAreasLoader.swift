import Foundation

/// Paginated loader for BTC Map v2 community areas.
/// Publishes progressive merges so the map can show communities before the full crawl finishes.
final class CommunityAreasLoader {
    private let repository: BTCMapRepositoryProtocol
    private let pageLimit: Int
    private let maxPages: Int

    init(
        repository: BTCMapRepositoryProtocol,
        pageLimit: Int = 500,
        maxPages: Int = 20
    ) {
        self.repository = repository
        self.pageLimit = pageLimit
        self.maxPages = maxPages
    }

    /// Loads all community-capable v2 areas, calling `onPage` on the main queue after each page merge.
    func loadAll(
        initialAnchor: String = "2022-01-01T00:00:00.000Z",
        onPage: @escaping (_ areas: [V2AreaRecord], _ isComplete: Bool, _ error: Error?) -> Void
    ) {
        step(anchor: initialAnchor, page: 1, accumulated: [:], onPage: onPage)
    }

    private func step(
        anchor: String,
        page: Int,
        accumulated: [String: V2AreaRecord],
        onPage: @escaping (_ areas: [V2AreaRecord], _ isComplete: Bool, _ error: Error?) -> Void
    ) {
        // Deliberately capture self strongly: callers create this loader as a
        // local, so the in-flight completion is the only thing keeping it (and
        // the pagination) alive. A weak capture would deallocate the loader as
        // soon as the calling scope returns and onPage would never fire. The
        // retain resolves when the network completion runs.
        repository.fetchV2Areas(updatedSince: anchor, limit: pageLimit) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    onPage(Array(accumulated.values), true, error)

                case .success(let areas):
                    var merged = accumulated
                    for area in areas {
                        if area.isDeleted {
                            merged.removeValue(forKey: area.id)
                        } else {
                            merged[area.id] = area
                        }
                    }

                    let nextAnchor = areas.last?.updatedAt
                    let shouldContinue = areas.count == self.pageLimit &&
                        page < self.maxPages &&
                        nextAnchor != nil &&
                        nextAnchor != anchor

                    if shouldContinue, let nextAnchor {
                        onPage(Array(merged.values), false, nil)
                        self.step(anchor: nextAnchor, page: page + 1, accumulated: merged, onPage: onPage)
                        return
                    }

                    onPage(Array(merged.values), true, nil)
                }
            }
        }
    }
}
