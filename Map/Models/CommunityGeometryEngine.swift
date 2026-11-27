import CoreLocation
import Foundation
import MapKit

/// Pure GeoJSON geometry, antimeridian seam-splitting, point-in-polygon membership,
/// and bounding-region calculations for Bitcoin community areas.
enum CommunityGeometryEngine {

    // MARK: - Map Overlays

    static func overlays(for areas: [V2AreaRecord]) -> [MKPolygon] {
        var polygons: [MKPolygon] = []
        for area in areas {
            guard let geoJSON = area.geoJSON else { continue }
            for feature in geoJSON.features {
                switch feature.geometry.coordinates {
                case .polygon(let rings):
                    polygons.append(contentsOf: mkPolygons(from: rings, title: area.displayName, identifier: area.id))
                case .multiPolygon(let multiRings):
                    for rings in multiRings {
                        polygons.append(contentsOf: mkPolygons(from: rings, title: area.displayName, identifier: area.id))
                    }
                }
            }
        }
        return polygons
    }

    static func mkPolygons(from rings: [[[Double]]], title: String, identifier: String?) -> [MKPolygon] {
        guard let outerRing = rings.first, !outerRing.isEmpty else { return [] }
        let coords = outerRing.compactMap { point -> CLLocationCoordinate2D? in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
        guard coords.count >= 3 else { return [] }

        let splitRings = splitRingAtAntimeridian(coords)
        return splitRings.compactMap { ring in
            guard ring.count >= 3 else { return nil }
            var mutableRing = ring
            let polygon = MKPolygon(coordinates: &mutableRing, count: mutableRing.count)
            polygon.title = title
            polygon.subtitle = identifier
            return polygon
        }
    }

    static func splitRingAtAntimeridian(_ ring: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        var points = ring
        if let first = points.first, let last = points.last, coordinatesNearlyEqual(first, last) {
            points.removeLast()
        }
        guard points.count >= 3 else { return [] }

        var fragments: [[CLLocationCoordinate2D]] = [[points[0]]]

        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let delta = b.longitude - a.longitude

            if abs(delta) <= 180 {
                appendCoordinateIfNeeded(b, to: &fragments[fragments.count - 1])
                continue
            }

            // Crossing the antimeridian; split at +/-180 and continue on the opposite seam.
            let crossesEastward = delta < -180 // e.g. 170 -> -170 (across +180)
            let seamCurrent: CLLocationDegrees = crossesEastward ? 180 : -180
            let seamNext: CLLocationDegrees = crossesEastward ? -180 : 180
            let adjustedBLon = crossesEastward ? (b.longitude + 360) : (b.longitude - 360)
            let denominator = adjustedBLon - a.longitude

            if denominator == 0 {
                appendCoordinateIfNeeded(b, to: &fragments[fragments.count - 1])
                continue
            }

            let t = max(0, min(1, (seamCurrent - a.longitude) / denominator))
            let seamLat = a.latitude + ((b.latitude - a.latitude) * t)
            let pointOnCurrentSeam = CLLocationCoordinate2D(latitude: seamLat, longitude: seamCurrent)
            let pointOnNextSeam = CLLocationCoordinate2D(latitude: seamLat, longitude: seamNext)

            appendCoordinateIfNeeded(pointOnCurrentSeam, to: &fragments[fragments.count - 1])

            var nextFragment: [CLLocationCoordinate2D] = [pointOnNextSeam]
            appendCoordinateIfNeeded(b, to: &nextFragment)
            fragments.append(nextFragment)
        }

        return fragments.compactMap { fragment in
            var cleaned = collapseConsecutiveDuplicates(fragment)
            guard cleaned.count >= 3 else { return nil }
            if let first = cleaned.first, let last = cleaned.last, !coordinatesNearlyEqual(first, last) {
                cleaned.append(first)
            }
            // MKPolygon accepts open rings too, but closing produces more stable seam splits.
            guard cleaned.count >= 4 else { return nil }
            return cleaned
        }
    }

    // MARK: - Bounding Rects & Regions

    static func boundingMapRect(for area: V2AreaRecord) -> MKMapRect? {
        if let geoJSON = area.geoJSON, let geoRect = mapRect(from: geoJSON), !geoRect.isNull, !geoRect.isEmpty {
            return expandedCommunityRectIfNeeded(geoRect)
        }

        func parse(_ key: String) -> Double? {
            guard let raw = area.tags?[key] else { return nil }
            return Double(raw)
        }

        if let north = parse("box:north"),
           let south = parse("box:south"),
           let east = parse("box:east"),
           let west = parse("box:west") {
            let topLeft = CLLocationCoordinate2D(latitude: north, longitude: west)
            let bottomRight = CLLocationCoordinate2D(latitude: south, longitude: east)
            let topLeftPoint = MKMapPoint(topLeft)
            let bottomRightPoint = MKMapPoint(bottomRight)
            let rect = MKMapRect(
                x: min(topLeftPoint.x, bottomRightPoint.x),
                y: min(topLeftPoint.y, bottomRightPoint.y),
                width: abs(topLeftPoint.x - bottomRightPoint.x),
                height: abs(topLeftPoint.y - bottomRightPoint.y)
            )
            if !rect.isNull, !rect.isEmpty {
                return expandedCommunityRectIfNeeded(rect)
            }
        }

        return nil
    }

    static func mapRect(from geoJSON: GeoJSONFeatureCollection) -> MKMapRect? {
        var rect = MKMapRect.null

        func includeCoordinate(_ coordinate: [Double]) {
            guard coordinate.count >= 2 else { return }
            let lon = coordinate[0]
            let lat = coordinate[1]
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return }
            let point = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }

        for feature in geoJSON.features {
            switch feature.geometry.coordinates {
            case .polygon(let rings):
                for ring in rings {
                    for coordinate in ring {
                        includeCoordinate(coordinate)
                    }
                }
            case .multiPolygon(let polygons):
                for rings in polygons {
                    for ring in rings {
                        for coordinate in ring {
                            includeCoordinate(coordinate)
                        }
                    }
                }
            }
        }

        return rect.isNull ? nil : rect
    }

    static func expandedCommunityRectIfNeeded(_ rect: MKMapRect, minimumMeters: CLLocationDistance = 800) -> MKMapRect {
        let midpoint = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let minimumMapPoints = minimumMeters * MKMapPointsPerMeterAtLatitude(midpoint.latitude)

        let additionalWidth = max(0, minimumMapPoints - rect.width)
        let additionalHeight = max(0, minimumMapPoints - rect.height)

        if additionalWidth == 0, additionalHeight == 0 {
            return rect
        }

        return rect.insetBy(dx: -(additionalWidth / 2), dy: -(additionalHeight / 2))
    }

    static func mapRegion(forCommunityArea area: V2AreaRecord) -> MKCoordinateRegion? {
        func parse(_ key: String) -> Double? {
            guard let raw = area.tags?[key] else { return nil }
            return Double(raw)
        }

        if let north = parse("box:north"),
           let south = parse("box:south"),
           let east = parse("box:east"),
           let west = parse("box:west") {
            let center = CLLocationCoordinate2D(
                latitude: (north + south) / 2,
                longitude: normalizedMidLongitude(west: west, east: east)
            )
            let latDelta = max(abs(north - south) * 1.2, 0.03)
            let lonSpan = longitudeDeltaAcrossAntimeridian(west: west, east: east)
            let lonDelta = max(lonSpan * 1.2, 0.03)
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        }
        return nil
    }

    static func mapRegion(for area: V3AreaRecord) -> MKCoordinateRegion? {
        guard let bounds = area.bounds,
              let minLat = bounds.minLat,
              let maxLat = bounds.maxLat,
              let minLon = bounds.minLon,
              let maxLon = bounds.maxLon else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.2, 0.05)
        let lonDelta = max((maxLon - minLon) * 1.2, 0.05)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    static func longitudeDeltaAcrossAntimeridian(west: Double, east: Double) -> Double {
        let direct = abs(east - west)
        return direct <= 180 ? direct : 360 - direct
    }

    static func normalizedMidLongitude(west: Double, east: Double) -> Double {
        if abs(east - west) <= 180 {
            return (west + east) / 2
        }
        let shiftedEast = east < west ? east + 360 : east
        var mid = (west + shiftedEast) / 2
        if mid > 180 { mid -= 360 }
        return mid
    }

    // MARK: - Polygon Containment

    static func geoJSONPolygons(from collection: GeoJSONFeatureCollection) -> [[[[Double]]]] {
        var polygons: [[[[Double]]]] = []
        for feature in collection.features {
            switch feature.geometry.coordinates {
            case .multiPolygon(let multipolygon):
                polygons.append(contentsOf: multipolygon)
            case .polygon(let polygon):
                polygons.append(polygon)
            }
        }
        return polygons
    }

    static func coordinateInPolygon(latitude: Double, longitude: Double, rings: [[[Double]]]) -> Bool {
        guard let outer = rings.first, pointInRing(latitude: latitude, longitude: longitude, ring: outer) else {
            return false
        }

        // Exclude points that are inside holes.
        for hole in rings.dropFirst() {
            if pointInRing(latitude: latitude, longitude: longitude, ring: hole) {
                return false
            }
        }
        return true
    }

    static func pointInRing(latitude: Double, longitude: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1

        for i in ring.indices {
            guard ring[i].count >= 2, ring[j].count >= 2 else {
                j = i
                continue
            }

            let xi = ring[i][0]
            let yi = ring[i][1]
            let xj = ring[j][0]
            let yj = ring[j][1]
            let intersects = ((yi > latitude) != (yj > latitude))
                && (longitude < (xj - xi) * (latitude - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)

            if intersects {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Private Ring Utilities

    private static func appendCoordinateIfNeeded(_ coordinate: CLLocationCoordinate2D, to ring: inout [CLLocationCoordinate2D]) {
        if let last = ring.last, coordinatesNearlyEqual(last, coordinate) { return }
        ring.append(coordinate)
    }

    private static func collapseConsecutiveDuplicates(_ ring: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for coordinate in ring {
            appendCoordinateIfNeeded(coordinate, to: &result)
        }
        return result
    }

    private static func coordinatesNearlyEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000001 &&
        abs(lhs.longitude - rhs.longitude) < 0.000001
    }
}
