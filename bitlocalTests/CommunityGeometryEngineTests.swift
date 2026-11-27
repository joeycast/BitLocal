import CoreLocation
import Foundation
import MapKit
import Testing
@testable import bitlocal

@Suite(.tags(.map))
struct CommunityGeometryEngineTests {

    @Test("Point-in-polygon handles outer rings and excludes inner holes")
    func pointInPolygonHandlesOuterAndHoleRings() {
        let outer: [[Double]] = [
            [0, 0],
            [10, 0],
            [10, 10],
            [0, 10],
            [0, 0],
        ]
        let hole: [[Double]] = [
            [3, 3],
            [7, 3],
            [7, 7],
            [3, 7],
            [3, 3],
        ]

        // Inside outer, outside hole
        #expect(CommunityGeometryEngine.coordinateInPolygon(latitude: 1.5, longitude: 1.5, rings: [outer, hole]))
        // Inside hole -> excluded
        #expect(!CommunityGeometryEngine.coordinateInPolygon(latitude: 5.0, longitude: 5.0, rings: [outer, hole]))
        // Outside outer -> excluded
        #expect(!CommunityGeometryEngine.coordinateInPolygon(latitude: 12.0, longitude: 5.0, rings: [outer, hole]))
    }

    @Test("Antimeridian seam splitting breaks trans-pacific rings cleanly at +/-180")
    func antimeridianSeamSplittingCreatesClosedFragments() {
        // Simple quad crossing from 175°E to -175°W across the antimeridian
        let ring = [
            CLLocationCoordinate2D(latitude: -17.0, longitude: 175.0),
            CLLocationCoordinate2D(latitude: -17.0, longitude: -175.0),
            CLLocationCoordinate2D(latitude: -19.0, longitude: -175.0),
            CLLocationCoordinate2D(latitude: -19.0, longitude: 175.0),
            CLLocationCoordinate2D(latitude: -17.0, longitude: 175.0),
        ]

        let fragments = CommunityGeometryEngine.splitRingAtAntimeridian(ring)
        #expect(fragments.count >= 2)
        for fragment in fragments {
            #expect(fragment.count >= 4)
            // Every segment inside each fragment must stay within <= 180 degrees longitude jump
            for i in 0..<(fragment.count - 1) {
                let jump = abs(fragment[i + 1].longitude - fragment[i].longitude)
                #expect(jump <= 180.0001)
            }
        }
    }

    @Test("Antimeridian bounding region computes shortest span and normalized midpoint")
    func antimeridianBoundingRegionAndMidpoint() {
        let area = V2AreaRecord(
            id: "fiji-bitcoin",
            tags: [
                "name": "Bitcoin Fiji",
                "type": "community",
                "box:north": "-16.0",
                "box:south": "-19.0",
                "box:west": "176.0",
                "box:east": "-178.0",
            ],
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil,
            geoJSON: nil
        )

        let region = CommunityGeometryEngine.mapRegion(forCommunityArea: area)
        #expect(region != nil)
        if let region {
            // West 176 -> East -178 is 6 degrees across the antimeridian (midpoint 179°E)
            #expect(abs(region.center.latitude - (-17.5)) < 0.001)
            #expect(abs(region.center.longitude - 179.0) < 0.001)
            #expect(abs(region.span.longitudeDelta - (6.0 * 1.2)) < 0.001)
        }
    }

    @Test("Tiny community bounding map rects expand to at least 800m for readable map zoom")
    func tinyBoundingRectExpandsToMinimumMeters() {
        let area = V2AreaRecord(
            id: "micro-community",
            tags: [
                "name": "Micro Hub",
                "type": "community",
                "box:north": "30.26725",
                "box:south": "30.26720",
                "box:west": "-97.74315",
                "box:east": "-97.74310",
            ],
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil,
            geoJSON: nil
        )

        let rect = CommunityGeometryEngine.boundingMapRect(for: area)
        #expect(rect != nil)
        if let rect {
            let minPoints = 800.0 * MKMapPointsPerMeterAtLatitude(30.267225)
            #expect(rect.width >= minPoints - 1.0)
            #expect(rect.height >= minPoints - 1.0)
        }
    }
}
