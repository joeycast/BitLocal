import Foundation
import CoreLocation

/// Coarse lat/lon grid for bounding-box candidate lookup before point-in-polygon.
/// Used to avoid scanning the global merchant catalog for community membership.
struct MerchantSpatialIndex {
    struct Entry: Hashable {
        let id: String
        let latitude: Double
        let longitude: Double
    }

    /// ~0.05° ≈ 5.5 km at the equator; fine enough for community polygons,
    /// coarse enough to keep cell counts modest.
    private let cellSizeDegrees: Double
    private var cells: [CellKey: [Entry]] = [:]
    private(set) var entryCount: Int = 0
    private(set) var sourceSignature: Int = 0

    init(cellSizeDegrees: Double = 0.05) {
        self.cellSizeDegrees = max(cellSizeDegrees, 0.01)
    }

    var isEmpty: Bool { entryCount == 0 }

    mutating func rebuild(from elements: [Element], sourceSignature: Int) {
        cells.removeAll(keepingCapacity: true)
        entryCount = 0
        self.sourceSignature = sourceSignature

        for element in elements {
            guard let coordinate = element.mapCoordinate else { continue }
            let entry = Entry(
                id: element.id,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let key = cellKey(latitude: entry.latitude, longitude: entry.longitude)
            cells[key, default: []].append(entry)
            entryCount += 1
        }
    }

    /// Returns indexed merchants whose coordinates fall inside the inclusive bounding box.
    /// Handles antimeridian-spanning boxes (lon span > 180°) by querying the short arc
    /// as the union of `[maxLon, 180]` and `[-180, minLon]`.
    func candidates(
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double
    ) -> [Entry] {
        guard entryCount > 0 else { return [] }

        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)

        // Naive min/max across the date line yields a huge span that covers the wrong ocean.
        if maxLon - minLon > 180 {
            return candidatesInBox(minLat: minLat, maxLat: maxLat, minLon: maxLon, maxLon: 180)
                + candidatesInBox(minLat: minLat, maxLat: maxLat, minLon: -180, maxLon: minLon)
        }

        return candidatesInBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    private func candidatesInBox(
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double
    ) -> [Entry] {
        let minX = cellIndex(minLon)
        let maxX = cellIndex(maxLon)
        let minY = cellIndex(minLat)
        let maxY = cellIndex(maxLat)

        guard minX <= maxX, minY <= maxY else { return [] }

        var results: [Entry] = []
        results.reserveCapacity(64)

        for x in minX...maxX {
            for y in minY...maxY {
                guard let bucket = cells[CellKey(x: x, y: y)] else { continue }
                for entry in bucket {
                    if entry.latitude >= minLat,
                       entry.latitude <= maxLat,
                       entry.longitude >= minLon,
                       entry.longitude <= maxLon {
                        results.append(entry)
                    }
                }
            }
        }
        return results
    }

    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }

    private func cellKey(latitude: Double, longitude: Double) -> CellKey {
        CellKey(x: cellIndex(longitude), y: cellIndex(latitude))
    }

    private func cellIndex(_ value: Double) -> Int {
        Int(floor(value / cellSizeDegrees))
    }
}

enum MerchantPolygonGeometry {
    /// Axis-aligned bounding box for a GeoJSON-style polygon rings collection.
    /// Outer ring coordinates are [lon, lat] pairs.
    ///
    /// When the lon span exceeds 180°, the polygon is assumed to cross the
    /// antimeridian; callers of `MerchantSpatialIndex.candidates` treat that
    /// span as the short arc across ±180 rather than the long way through 0°.
    static func boundingBox(for polygons: [[[[Double]]]]) -> (
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double
    )? {
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        var found = false

        for polygon in polygons {
            guard let outer = polygon.first else { continue }
            for point in outer where point.count >= 2 {
                let lon = point[0]
                let lat = point[1]
                minLat = min(minLat, lat)
                maxLat = max(maxLat, lat)
                minLon = min(minLon, lon)
                maxLon = max(maxLon, lon)
                found = true
            }
        }

        guard found else { return nil }
        return (minLat, maxLat, minLon, maxLon)
    }
}
