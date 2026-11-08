import CoreGraphics
import Foundation
import BitLocalDomain

/// Camera as values: the center and the zoom as meters per screen point.
public struct CameraState: Equatable, Sendable {
    public var center: Coordinate
    public var metersPerPoint: Double

    public init(center: Coordinate, metersPerPoint: Double) {
        self.center = center
        self.metersPerPoint = metersPerPoint
    }
}

public enum MapFraming {
    static let metersPerDegreeLatitude = 111_320.0

    /// Keeps `focus` at the center of the unobscured rect after a layout change,
    /// at the same meters-per-point zoom (duo.md 3.2). No animation: the layout change is the motion.
    public static func camera(
        keeping focus: Coordinate,
        metersPerPoint: Double,
        mapSize: CGSize,
        unobscured: CGRect
    ) -> CameraState {
        // Offset (in points) from the map's center to the unobscured rect's center.
        let dx = Double(unobscured.midX - mapSize.width / 2)
        let dy = Double(unobscured.midY - mapSize.height / 2)
        // The map center sits opposite that offset from the focus.
        let metersEast = -dx * metersPerPoint
        let metersNorth = dy * metersPerPoint // screen y grows downward
        let latitude = focus.latitude + metersNorth / metersPerDegreeLatitude
        let metersPerDegreeLongitude = max(metersPerDegreeLatitude * cos(focus.latitude * .pi / 180), 1)
        var longitude = focus.longitude + metersEast / metersPerDegreeLongitude
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return CameraState(
            center: Coordinate(latitude: min(max(latitude, -85), 85), longitude: longitude),
            metersPerPoint: metersPerPoint
        )
    }

    /// The zoom at which a pin stands alone: its nearest neighbor `neighborDistance`
    /// meters away lands at least one cluster cell + pin diameter apart (duo.md 5).
    /// Never zooms out: returns `current` when it is already closer.
    public static func standAloneMetersPerPoint(
        neighborDistance: Double,
        current: Double,
        cellSize: Double = 60,
        pinDiameter: Double = 36,
        streetLevel: Double = 1.5,
        maximumZoom: Double = 0.1
    ) -> Double {
        let needed = neighborDistance / (cellSize + pinDiameter)
        let target = max(min(needed, streetLevel), maximumZoom)
        return min(current, target)
    }
}
