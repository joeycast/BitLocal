import Foundation
import BitLocalDomain

/// Grid clustering in projected map points (architecture-redesign.md section 6).
///
/// The grid is anchored to the world, not the screen, and its cell size is fixed
/// within a zoom bucket, so a cluster keeps its id while the map pans. On screen a
/// cell is between `cellSize` and `2 × cellSize` points wide depending on where
/// the zoom sits inside its bucket.
public enum MerchantClusterer {
    /// From this zoom bucket on, only merchants at the same coordinate are grouped
    /// (the "N places here" case); everything else is drawn as its own pin.
    public static let colocatedOnlyBucket = 18

    public static func cluster(
        _ summaries: [MerchantSummary],
        viewport: MapViewport,
        cellSize: Double = 60,
        selected: MerchantID? = nil
    ) -> [MapItem] {
        let bucket = viewport.zoomBucket
        let bucketWorldSize = 256 * pow(2, Double(bucket))
        let cellWorld = cellSize / bucketWorldSize
        let colocatedOnly = bucket >= colocatedOnlyBucket

        struct Cell: Hashable { let x: Int; let y: Int }
        struct Group {
            var members: [MerchantSummary] = []
            var sumX = 0.0
            var sumY = 0.0
        }

        var groups: [Cell: Group] = [:]
        var items: [MapItem] = []
        items.reserveCapacity(min(summaries.count, 512))

        for summary in summaries {
            if summary.id == selected {
                // The selected pin is never swallowed by a cluster.
                items.append(.merchant(summary))
                continue
            }
            let p = MercatorProjection.point(summary.coordinate)
            let cell: Cell
            if colocatedOnly {
                // ~1 cm grid: identical coordinates only.
                cell = Cell(x: Int((p.x * 4e9).rounded()), y: Int((p.y * 4e9).rounded()))
            } else {
                cell = Cell(x: Int(floor(p.x / cellWorld)), y: Int(floor(p.y / cellWorld)))
            }
            groups[cell, default: Group()].members.append(summary)
            groups[cell]!.sumX += p.x
            groups[cell]!.sumY += p.y
        }

        for (cell, group) in groups {
            if group.members.count == 1 {
                items.append(.merchant(group.members[0]))
                continue
            }
            let count = Double(group.members.count)
            let center = MercatorProjection.coordinate(x: group.sumX / count, y: group.sumY / count)
            items.append(.cluster(
                id: ClusterID(zoomBucket: colocatedOnly ? colocatedOnlyBucket : bucket, cellX: cell.x, cellY: cell.y),
                coordinate: center,
                count: group.members.count,
                memberIDs: group.members.map(\.id).sorted { $0.rawValue < $1.rawValue },
                sampleCategory: mostCommonCategory(group.members)
            ))
        }

        return items.sorted(by: stableOrder)
    }

    private static func mostCommonCategory(_ members: [MerchantSummary]) -> MerchantCategory {
        var counts: [MerchantCategory: Int] = [:]
        for member in members { counts[member.category, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue > rhs.key.rawValue
        }?.key ?? .unknown
    }

    /// Deterministic order so diffs and tests are stable: merchants by id, then clusters by cell.
    private static func stableOrder(_ lhs: MapItem, _ rhs: MapItem) -> Bool {
        switch (lhs, rhs) {
        case let (.merchant(a), .merchant(b)):
            return a.id.rawValue < b.id.rawValue
        case (.merchant, .cluster):
            return true
        case (.cluster, .merchant):
            return false
        case let (.cluster(a, _, _, _, _), .cluster(b, _, _, _, _)):
            return (a.zoomBucket, a.cellX, a.cellY) < (b.zoomBucket, b.cellX, b.cellY)
        }
    }
}
