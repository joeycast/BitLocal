import Foundation
import BitLocalDomain

/// Web Mercator in normalized world units: x and y both run 0...1, with (0, 0) at
/// the north-west corner. Matches `MKMapPoint` up to a constant scale, so a map's
/// width in points divided by its visible width in world units gives `worldSize`.
public enum MercatorProjection {
    public static let maxLatitude = 85.05112878

    public static func x(longitude: Double) -> Double {
        (longitude + 180) / 360
    }

    public static func y(latitude: Double) -> Double {
        let lat = min(max(latitude, -maxLatitude), maxLatitude) * .pi / 180
        return (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2
    }

    public static func point(_ coordinate: Coordinate) -> (x: Double, y: Double) {
        (x(longitude: coordinate.longitude), y(latitude: coordinate.latitude))
    }

    public static func coordinate(x: Double, y: Double) -> Coordinate {
        let longitude = x * 360 - 180
        let n = Double.pi * (1 - 2 * y)
        let latitude = atan(sinh(n)) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// What the map shows right now, in the terms the query and clusterer need.
public struct MapViewport: Hashable, Sendable {
    /// The visible area (antimeridian-aware).
    public var rect: GeoRect
    /// The point the list sorts by distance from: the center of the unobscured map.
    public var center: Coordinate
    /// Width of the whole world in screen points at the current zoom.
    public var worldSize: Double

    public init(rect: GeoRect, center: Coordinate, worldSize: Double) {
        self.rect = rect
        self.center = center
        self.worldSize = worldSize
    }

    /// The zoom bucket used for cluster identity: 0 when the world is 256 pt wide,
    /// +1 for every doubling.
    public var zoomBucket: Int {
        Int(floor(log2(max(worldSize, 1) / 256)))
    }
}
