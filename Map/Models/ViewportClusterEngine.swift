import CoreLocation
import Foundation
import MapKit

/// Lightweight value entry stored in the map's spatial lookup grid.
struct ViewportSpatialEntry: Sendable {
    let element: Element
    let latitude: Double
    let longitude: Double
    let mapPointX: Double
    let mapPointY: Double

    var mapPoint: MKMapPoint {
        MKMapPoint(x: mapPointX, y: mapPointY)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(element: Element, coordinate: CLLocationCoordinate2D) {
        self.element = element
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        let point = MKMapPoint(coordinate)
        self.mapPointX = point.x
        self.mapPointY = point.y
    }
}

/// Pure cluster value produced by `ViewportClusterEngine` for a screen-space grid cell.
struct ViewportClusterDescriptor: Equatable, Sendable {
    let key: String
    let latitude: Double
    let longitude: Double
    let count: Int
    let boundingMinX: Double
    let boundingMinY: Double
    let boundingWidth: Double
    let boundingHeight: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var boundingMapRect: MKMapRect {
        MKMapRect(x: boundingMinX, y: boundingMinY, width: boundingWidth, height: boundingHeight)
    }
}

/// Output of a single viewport clustering pass.
struct ViewportClusterOutput: Sendable {
    /// Individual merchant pins to display on the map.
    let singleElements: [Element]
    /// Grid clusters to display when zoomed out past `maxUnclusteredAnnotations`.
    let clusters: [ViewportClusterDescriptor]
    /// Whether regional grid clustering was engaged for this pass.
    let isClustered: Bool
}

/// `MKAnnotation` representing a regional grid cluster when the viewport contains
/// more merchants than MapKit should cluster individually.
final class MerchantClusterAnnotation: NSObject, MKAnnotation {
    let clusterKey: String
    let count: Int
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(descriptor: ViewportClusterDescriptor) {
        self.clusterKey = descriptor.key
        self.count = descriptor.count
        self.boundingMapRect = descriptor.boundingMapRect
        self.coordinate = descriptor.coordinate
        super.init()
    }
}

/// Fast viewport-driven spatial clusterer that removes the 25-mile map pin cap
/// while keeping MapKit annotation counts bounded at city, country, and world zoom.
enum ViewportClusterEngine {
    /// Above this visible merchant count, switch from individual pins (with MapKit's
    /// street-level clustering) to O(n) screen-space grid clusters so zooming out
    /// across countries or continents stays 60/120fps.
    static let defaultMaxUnclusteredAnnotations = 300

    /// Maximum visible elements published to the bottom sheet list on zoomed-out views.
    static let defaultMaxPublishedVisibleElements = 400

    /// Target screen-space cluster cell size in points.
    static let defaultTargetCellPoints: Double = 60

    static func cluster(
        entries: [ViewportSpatialEntry],
        visibleMapRect: MKMapRect,
        viewportSize: CGSize,
        pinnedElementID: String? = nil,
        maxUnclusteredAnnotations: Int = defaultMaxUnclusteredAnnotations,
        targetCellPoints: Double = defaultTargetCellPoints
    ) -> ViewportClusterOutput {
        guard !entries.isEmpty else {
            return ViewportClusterOutput(singleElements: [], clusters: [], isClustered: false)
        }

        // Deduplicate by ID (last-wins, matching IdentifiableIndex.byID) while preserving order.
        var deduped: [ViewportSpatialEntry] = []
        deduped.reserveCapacity(entries.count)
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(entries.count)
        for entry in entries {
            if let existingIndex = indexByID[entry.element.id] {
                deduped[existingIndex] = entry
            } else {
                indexByID[entry.element.id] = deduped.count
                deduped.append(entry)
            }
        }

        if deduped.count <= maxUnclusteredAnnotations {
            return ViewportClusterOutput(
                singleElements: deduped.map(\.element),
                clusters: [],
                isClustered: false
            )
        }

        let safeWidth = max(Double(viewportSize.width), 320)
        let safeHeight = max(Double(viewportSize.height), 320)
        let columns = min(max(Int((safeWidth / targetCellPoints).rounded()), 6), 14)
        let rows = min(max(Int((safeHeight / targetCellPoints).rounded()), 6), 16)

        let rectWidth = max(visibleMapRect.size.width, 1)
        let rectHeight = max(visibleMapRect.size.height, 1)
        let cellWidth = rectWidth / Double(columns)
        let cellHeight = rectHeight / Double(rows)
        let worldWidth = MKMapSize.world.width

        struct CellKey: Hashable {
            let col: Int
            let row: Int
        }

        struct Bucket {
            var count: Int = 0
            var firstEntry: ViewportSpatialEntry
            var sumLat: Double = 0
            var sumLon: Double = 0
            var minX: Double = .greatestFiniteMagnitude
            var maxX: Double = -.greatestFiniteMagnitude
            var minY: Double = .greatestFiniteMagnitude
            var maxY: Double = -.greatestFiniteMagnitude

            mutating func append(_ entry: ViewportSpatialEntry, adjustedX: Double) {
                count += 1
                sumLat += entry.latitude
                sumLon += entry.longitude
                minX = min(minX, adjustedX)
                maxX = max(maxX, adjustedX)
                minY = min(minY, entry.mapPointY)
                maxY = max(maxY, entry.mapPointY)
            }
        }

        var singles: [Element] = []
        var buckets: [CellKey: Bucket] = [:]
        buckets.reserveCapacity(min(columns * rows, 160))

        for entry in deduped {
            if let pinnedElementID, entry.element.id == pinnedElementID {
                singles.append(entry.element)
                continue
            }

            // Normalize X into visibleMapRect's unwrapped coordinate space when crossing antimeridian.
            var adjustedX = entry.mapPointX
            if adjustedX < visibleMapRect.minX, visibleMapRect.maxX > worldWidth {
                adjustedX += worldWidth
            }

            let col = Int(floor((adjustedX - visibleMapRect.minX) / cellWidth))
            let row = Int(floor((entry.mapPointY - visibleMapRect.minY) / cellHeight))
            let key = CellKey(col: col, row: row)

            if var bucket = buckets[key] {
                bucket.append(entry, adjustedX: adjustedX)
                buckets[key] = bucket
            } else {
                var bucket = Bucket(firstEntry: entry)
                bucket.append(entry, adjustedX: adjustedX)
                buckets[key] = bucket
            }
        }

        var clusters: [ViewportClusterDescriptor] = []
        clusters.reserveCapacity(buckets.count)

        for (cellKey, bucket) in buckets {
            if bucket.count == 1 {
                singles.append(bucket.firstEntry.element)
            } else {
                let avgLat = bucket.sumLat / Double(bucket.count)
                let avgLon = bucket.sumLon / Double(bucket.count)
                let width = max(bucket.maxX - bucket.minX, 0)
                let height = max(bucket.maxY - bucket.minY, 0)
                // Quantize world-anchored cell index so identical clusters keep a stable identity.
                let worldCol = Int(floor(bucket.minX / max(cellWidth, 1)))
                let worldRow = Int(floor(bucket.minY / max(cellHeight, 1)))
                let clusterKey = "\(worldCol):\(worldRow):\(cellKey.col):\(cellKey.row):\(bucket.count)"
                clusters.append(
                    ViewportClusterDescriptor(
                        key: clusterKey,
                        latitude: avgLat,
                        longitude: avgLon,
                        count: bucket.count,
                        boundingMinX: bucket.minX,
                        boundingMinY: bucket.minY,
                        boundingWidth: width,
                        boundingHeight: height
                    )
                )
            }
        }

        return ViewportClusterOutput(
            singleElements: singles,
            clusters: clusters,
            isClustered: true
        )
    }

    /// Selects a bounded, representative slice of visible elements for the bottom sheet
    /// when zoomed out over thousands of merchants (preserving all boosted places + nearest to center).
    static func selectVisibleListElements(
        from entries: [ViewportSpatialEntry],
        centerCoordinate: CLLocationCoordinate2D,
        maxCount: Int = defaultMaxPublishedVisibleElements,
        referenceDate: Date = .now
    ) -> [Element] {
        // Deduplicate by ID (last-wins) first.
        var deduped: [ViewportSpatialEntry] = []
        deduped.reserveCapacity(entries.count)
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(entries.count)
        for entry in entries {
            if let idx = indexByID[entry.element.id] {
                deduped[idx] = entry
            } else {
                indexByID[entry.element.id] = deduped.count
                deduped.append(entry)
            }
        }

        guard deduped.count > maxCount else {
            return deduped.map(\.element)
        }

        let centerLat = centerCoordinate.latitude
        let centerLon = centerCoordinate.longitude
        let cosLat = cos(centerLat * Double.pi / 180.0)

        func approxDistanceSq(_ entry: ViewportSpatialEntry) -> Double {
            let dLat = entry.latitude - centerLat
            var rawDLon = entry.longitude - centerLon
            if rawDLon > 180.0 { rawDLon -= 360.0 }
            else if rawDLon < -180.0 { rawDLon += 360.0 }
            let dLon = rawDLon * cosLat
            return dLat * dLat + dLon * dLon
        }

        var boosted: [ViewportSpatialEntry] = []
        var regular: [(entry: ViewportSpatialEntry, distSq: Double)] = []
        regular.reserveCapacity(deduped.count)

        for entry in deduped {
            if entry.element.isCurrentlyBoosted(referenceDate: referenceDate) {
                boosted.append(entry)
            } else {
                regular.append((entry, approxDistanceSq(entry)))
            }
        }

        boosted.sort { approxDistanceSq($0) < approxDistanceSq($1) }
        if boosted.count >= maxCount {
            return Array(boosted.prefix(maxCount)).map(\.element)
        }

        let remainingSlots = maxCount - boosted.count
        regular.sort { $0.distSq < $1.distSq }

        var selected: [Element] = []
        selected.reserveCapacity(maxCount)
        selected.append(contentsOf: boosted.map(\.element))
        selected.append(contentsOf: regular.prefix(remainingSlots).map(\.entry.element))
        return selected
    }

    /// Formats cluster counts cleanly so large country/continent clusters stay legible on pins.
    static func formattedCount(_ count: Int) -> String {
        if count < 1_000 {
            return "\(count)"
        }
        if count < 10_000 {
            let tenths = (count * 10 + 500) / 1_000
            if tenths % 10 == 0 {
                return "\(tenths / 10)K"
            }
            return "\(tenths / 10).\(tenths % 10)K"
        }
        let thousands = (count + 500) / 1_000
        return "\(thousands)K"
    }

    /// Computes a safe target `MKMapRect` when tapping a cluster (handling co-located points
    /// where `boundingMapRect` has zero width/height by zooming in smoothly around the centroid).
    static func zoomTargetMapRect(
        for boundingMapRect: MKMapRect,
        centroid: CLLocationCoordinate2D,
        currentVisibleRect: MKMapRect,
        paddingScale: Double = 1.3
    ) -> MKMapRect {
        if boundingMapRect.size.width > 1 || boundingMapRect.size.height > 1 {
            let padFactor = max(paddingScale - 1.0, 0)
            let minSpan = 2_000.0
            let targetWidth = max(boundingMapRect.size.width, minSpan)
            let targetHeight = max(boundingMapRect.size.height, minSpan)
            let centerX = boundingMapRect.midX
            let centerY = boundingMapRect.midY
            let expandedWidth = targetWidth * (1.0 + padFactor * 2.0)
            let expandedHeight = targetHeight * (1.0 + padFactor * 2.0)
            return MKMapRect(
                x: centerX - expandedWidth / 2.0,
                y: centerY - expandedHeight / 2.0,
                width: expandedWidth,
                height: expandedHeight
            )
        }

        // All members share the same coordinate — zoom in to 35% of current span (clamped to ~400m).
        let centerPoint = MKMapPoint(centroid)
        let targetWidth = max(currentVisibleRect.size.width * 0.35, 3_000.0)
        let targetHeight = max(currentVisibleRect.size.height * 0.35, 3_000.0)
        return MKMapRect(
            x: centerPoint.x - targetWidth / 2.0,
            y: centerPoint.y - targetHeight / 2.0,
            width: targetWidth,
            height: targetHeight
        )
    }

    /// Tests whether a map point falls inside `visibleRect`, accounting for antimeridian wrap.
    static func visibleRect(_ visibleRect: MKMapRect, contains point: MKMapPoint) -> Bool {
        if visibleRect.contains(point) {
            return true
        }
        let worldWidth = MKMapSize.world.width
        if visibleRect.maxX > worldWidth {
            let wrapped = MKMapPoint(x: point.x + worldWidth, y: point.y)
            return visibleRect.contains(wrapped)
        }
        return false
    }
}
