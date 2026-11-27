import CoreLocation
import Foundation
import MapKit
import Testing
@testable import bitlocal

@Suite(.tags(.map))
struct ViewportClusterEngineTests {

    private func makeElement(
        id: String,
        lat: Double,
        lon: Double,
        boostedUntil: String? = nil
    ) -> Element {
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: lat,
            lon: lon,
            tags: nil,
            timestamp: nil,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )
        let tags = boostedUntil.map {
            Tags(
                category: nil,
                iconPlatform: nil,
                paymentCoinos: nil,
                paymentPouch: nil,
                boostExpires: $0,
                categoryPlural: nil,
                paymentProvider: nil,
                paymentURI: nil
            )
        }
        return Element(
            id: id,
            osmJSON: osmJSON,
            tags: tags,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }

    private func mapRect(centerLat: Double, centerLon: Double, latDelta: Double, lonDelta: Double) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: centerLat + latDelta / 2, longitude: centerLon - lonDelta / 2))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: centerLat - latDelta / 2, longitude: centerLon + lonDelta / 2))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    @Test func staysUnclusteredBelowThresholdEvenAcrossWideRegion() {
        // Merchants spread 200+ miles apart (far beyond old 25-mile cap) stay individual pins when <= threshold.
        let entries = [
            ViewportSpatialEntry(element: makeElement(id: "1", lat: 37.77, lon: -122.42), coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)),
            ViewportSpatialEntry(element: makeElement(id: "2", lat: 34.05, lon: -118.24), coordinate: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)),
            ViewportSpatialEntry(element: makeElement(id: "3", lat: 36.17, lon: -115.14), coordinate: CLLocationCoordinate2D(latitude: 36.17, longitude: -115.14))
        ]
        let rect = mapRect(centerLat: 36.0, centerLon: -119.0, latDelta: 8.0, lonDelta: 12.0)

        let output = ViewportClusterEngine.cluster(
            entries: entries,
            visibleMapRect: rect,
            viewportSize: CGSize(width: 400, height: 700),
            maxUnclusteredAnnotations: 300
        )

        #expect(output.isClustered == false)
        #expect(output.clusters.isEmpty)
        #expect(output.singleElements.map(\.id) == ["1", "2", "3"])
    }

    @Test func clustersDenseViewportIntoBoundedAnnotationsAndKeepsPinnedElementSingle() {
        var entries: [ViewportSpatialEntry] = []
        // Generate 500 merchants spread across two dense cities + 1 isolated merchant.
        for i in 0..<250 {
            let lat = 37.70 + Double(i % 25) * 0.004
            let lon = -122.45 + Double(i / 25) * 0.004
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            entries.append(ViewportSpatialEntry(element: makeElement(id: "sf-\(i)", lat: lat, lon: lon), coordinate: coord))
        }
        for i in 0..<249 {
            let lat = 34.00 + Double(i % 25) * 0.004
            let lon = -118.25 + Double(i / 25) * 0.004
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            entries.append(ViewportSpatialEntry(element: makeElement(id: "la-\(i)", lat: lat, lon: lon), coordinate: coord))
        }
        let isolatedCoord = CLLocationCoordinate2D(latitude: 39.50, longitude: -119.80)
        entries.append(ViewportSpatialEntry(element: makeElement(id: "reno", lat: 39.50, lon: -119.80), coordinate: isolatedCoord))

        let rect = mapRect(centerLat: 36.8, centerLon: -120.0, latDelta: 8.0, lonDelta: 10.0)
        let output = ViewportClusterEngine.cluster(
            entries: entries,
            visibleMapRect: rect,
            viewportSize: CGSize(width: 400, height: 700),
            pinnedElementID: "sf-0",
            maxUnclusteredAnnotations: 300
        )

        #expect(output.isClustered == true)
        #expect(!output.clusters.isEmpty)
        // Total annotations stay dramatically smaller than 500.
        #expect(output.singleElements.count + output.clusters.count < 50)
        // Pinned merchant and isolated merchant remain unclustered singles.
        let singleIDs = Set(output.singleElements.map(\.id))
        #expect(singleIDs.contains("sf-0"))
        #expect(singleIDs.contains("reno"))
        // Every merchant is accounted for exactly once across singles + clusters.
        let totalAccounted = output.singleElements.count + output.clusters.reduce(0) { $0 + $1.count }
        #expect(totalAccounted == 500)
    }

    @Test func visibleListSelectionCapsCountWhilePreservingBoostedAndNearestMerchants() {
        let futureBoost = "2099-01-01T00:00:00Z"
        let center = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42)
        var entries: [ViewportSpatialEntry] = []

        // 1 far boosted merchant + 10 regular merchants at increasing distances.
        entries.append(
            ViewportSpatialEntry(
                element: makeElement(id: "boosted-far", lat: 40.0, lon: -120.0, boostedUntil: futureBoost),
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -120.0)
            )
        )
        for i in 1...10 {
            let lat = 37.77 + Double(i) * 0.1
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: -122.42)
            entries.append(ViewportSpatialEntry(element: makeElement(id: "reg-\(i)", lat: lat, lon: -122.42), coordinate: coord))
        }

        let selected = ViewportClusterEngine.selectVisibleListElements(
            from: entries,
            centerCoordinate: center,
            maxCount: 4,
            referenceDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(selected.count == 4)
        #expect(selected.first?.id == "boosted-far")
        #expect(selected.dropFirst().map(\.id) == ["reg-1", "reg-2", "reg-3"])
    }

    @Test func formattedCountFormatsSmallAndLargeClusterTotalsCleanly() {
        #expect(ViewportClusterEngine.formattedCount(2) == "2")
        #expect(ViewportClusterEngine.formattedCount(999) == "999")
        #expect(ViewportClusterEngine.formattedCount(1_000) == "1K")
        #expect(ViewportClusterEngine.formattedCount(1_250) == "1.3K")
        #expect(ViewportClusterEngine.formattedCount(9_950) == "10K")
        #expect(ViewportClusterEngine.formattedCount(24_800) == "25K")
    }

    @Test func zoomTargetMapRectHandlesColocatedPointsWithoutCollapsingToZeroSpan() {
        let centroid = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let point = MKMapPoint(centroid)
        let zeroRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
        let currentVisible = MKMapRect(x: point.x - 50_000, y: point.y - 50_000, width: 100_000, height: 100_000)

        let target = ViewportClusterEngine.zoomTargetMapRect(
            for: zeroRect,
            centroid: centroid,
            currentVisibleRect: currentVisible
        )

        #expect(target.size.width > 1_000)
        #expect(target.size.height > 1_000)
        #expect(target.size.width < currentVisible.size.width)
        #expect(target.contains(point))
    }
}
