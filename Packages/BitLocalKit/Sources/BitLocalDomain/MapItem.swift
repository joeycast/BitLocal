import Foundation

/// Stable id for a cluster: zoom bucket + grid cell, so clusters don't flicker while panning.
public struct ClusterID: Hashable, Sendable {
    public let zoomBucket: Int
    public let cellX: Int
    public let cellY: Int

    public init(zoomBucket: Int, cellX: Int, cellY: Int) {
        self.zoomBucket = zoomBucket
        self.cellX = cellX
        self.cellY = cellY
    }
}

/// One thing drawn on the map: a single merchant or a cluster of them.
public enum MapItem: Identifiable, Hashable, Sendable {
    case merchant(MerchantSummary)
    case cluster(id: ClusterID, coordinate: Coordinate, count: Int, memberIDs: [MerchantID], sampleCategory: MerchantCategory)

    public enum ID: Hashable, Sendable {
        case merchant(MerchantID)
        case cluster(ClusterID)
    }

    public var id: ID {
        switch self {
        case .merchant(let summary): .merchant(summary.id)
        case .cluster(let id, _, _, _, _): .cluster(id)
        }
    }

    public var coordinate: Coordinate {
        switch self {
        case .merchant(let summary): summary.coordinate
        case .cluster(_, let coordinate, _, _, _): coordinate
        }
    }
}
