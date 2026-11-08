import Foundation

/// A latitude/longitude pair. Plain `Double`s so it is `Sendable` and usable
/// without CoreLocation (tests run on macOS without a simulator).
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
            !(latitude == 0 && longitude == 0)
    }

    /// Great-circle distance in meters (haversine, mean Earth radius).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// An axis-aligned latitude/longitude box. `minLongitude > maxLongitude`
/// means the box crosses the antimeridian.
public struct GeoRect: Hashable, Sendable, Codable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// A box centered on `center` spanning the given degree deltas.
    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        let halfLat = abs(latitudeDelta) / 2
        let halfLon = min(abs(longitudeDelta) / 2, 180)
        minLatitude = max(center.latitude - halfLat, -90)
        maxLatitude = min(center.latitude + halfLat, 90)
        if halfLon >= 180 {
            minLongitude = -180
            maxLongitude = 180
        } else {
            minLongitude = GeoRect.wrap(center.longitude - halfLon)
            maxLongitude = GeoRect.wrap(center.longitude + halfLon)
        }
    }

    public var crossesAntimeridian: Bool { minLongitude > maxLongitude }

    /// One or two non-wrapping boxes covering the same area, for R-tree queries.
    public var normalizedParts: [GeoRect] {
        guard crossesAntimeridian else { return [self] }
        return [
            GeoRect(minLatitude: minLatitude, maxLatitude: maxLatitude, minLongitude: minLongitude, maxLongitude: 180),
            GeoRect(minLatitude: minLatitude, maxLatitude: maxLatitude, minLongitude: -180, maxLongitude: maxLongitude),
        ]
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        guard (minLatitude...maxLatitude).contains(coordinate.latitude) else { return false }
        if crossesAntimeridian {
            return coordinate.longitude >= minLongitude || coordinate.longitude <= maxLongitude
        }
        return (minLongitude...maxLongitude).contains(coordinate.longitude)
    }

    /// The same box grown by `fraction` of its span on every side (0.25 = 25%).
    public func expanded(by fraction: Double) -> GeoRect {
        let latPad = (maxLatitude - minLatitude) * fraction
        let lonSpan = crossesAntimeridian
            ? (180 - minLongitude) + (maxLongitude + 180)
            : maxLongitude - minLongitude
        let lonPad = lonSpan * fraction
        if lonSpan + 2 * lonPad >= 360 {
            return GeoRect(
                minLatitude: max(minLatitude - latPad, -90),
                maxLatitude: min(maxLatitude + latPad, 90),
                minLongitude: -180,
                maxLongitude: 180
            )
        }
        return GeoRect(
            minLatitude: max(minLatitude - latPad, -90),
            maxLatitude: min(maxLatitude + latPad, 90),
            minLongitude: GeoRect.wrap(minLongitude - lonPad),
            maxLongitude: GeoRect.wrap(maxLongitude + lonPad)
        )
    }

    static func wrap(_ longitude: Double) -> Double {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}
