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

    /// Loads all community-capable v2 areas, calling `onPage` on the main actor after each page merge.
    func loadAll(
        initialAnchor: String = "2022-01-01T00:00:00.000Z",
        onPage: @escaping (_ areas: [V2AreaRecord], _ isComplete: Bool, _ error: Error?) -> Void
    ) {
        let repository = self.repository
        let pageLimit = self.pageLimit
        let maxPages = self.maxPages

        Task {
            var anchor = initialAnchor
            var page = 1
            var accumulated: [String: V2AreaRecord] = [:]

            while true {
                do {
                    let areas = try await repository.fetchV2Areas(updatedSince: anchor, limit: pageLimit)
                    for area in areas {
                        if area.isDeleted {
                            accumulated.removeValue(forKey: area.id)
                        } else {
                            accumulated[area.id] = area
                        }
                    }

                    let nextAnchor = areas.last?.updatedAt
                    let shouldContinue = areas.count == pageLimit &&
                        page < maxPages &&
                        nextAnchor != nil &&
                        nextAnchor != anchor

                    let snapshot = Array(accumulated.values)
                    if shouldContinue, let nextAnchor {
                        await MainActor.run {
                            onPage(snapshot, false, nil)
                        }
                        anchor = nextAnchor
                        page += 1
                        continue
                    }

                    await MainActor.run {
                        onPage(snapshot, true, nil)
                    }
                    return
                } catch {
                    let snapshot = Array(accumulated.values)
                    await MainActor.run {
                        onPage(snapshot, true, error)
                    }
                    return
                }
            }
        }
    }
}
