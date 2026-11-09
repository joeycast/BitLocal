import Foundation
import Testing
import BitLocalData
import BitLocalDomain
@testable import BitLocalMap

private func summary(_ id: Int, _ lat: Double, _ lon: Double, category: String = "local_cafe") -> MerchantSummary {
    MerchantSummary(
        id: MerchantID(id), coordinate: Coordinate(latitude: lat, longitude: lon), name: "M\(id)",
        hasRealName: true, category: MerchantCategory(rawValue: category), paymentMethods: [.lightning],
        boostedUntil: nil, openingHours: nil, updatedAt: Date(timeIntervalSince1970: 0)
    )
}

/// A viewport `span` degrees wide around `center`, drawn `width` points wide.
private func viewport(center: Coordinate, span: Double, width: Double = 400) -> MapViewport {
    let rect = GeoRect(center: center, latitudeDelta: span, longitudeDelta: span)
    return MapViewport(rect: rect, center: center, worldSize: width * 360 / span)
}

private func merchantCount(_ items: [MapItem]) -> Int {
    items.reduce(0) { total, item in
        switch item {
        case .merchant: total + 1
        case .cluster(_, _, let count, _, _): total + count
        }
    }
}

@Suite("Mercator projection")
struct ProjectionTests {
    @Test func roundTrips() {
        for coordinate in [Coordinate(latitude: 36.16, longitude: -86.78), Coordinate(latitude: -33.9, longitude: 151.2), Coordinate(latitude: 0, longitude: 0)] {
            let p = MercatorProjection.point(coordinate)
            let back = MercatorProjection.coordinate(x: p.x, y: p.y)
            #expect(abs(back.latitude - coordinate.latitude) < 1e-9)
            #expect(abs(back.longitude - coordinate.longitude) < 1e-9)
        }
    }

    @Test func equatorIsTheMiddle() {
        #expect(abs(MercatorProjection.y(latitude: 0) - 0.5) < 1e-12)
        #expect(MercatorProjection.y(latitude: 60) < 0.5)
        #expect(MercatorProjection.x(longitude: -180) == 0)
    }

    @Test func zoomBucket() {
        #expect(MapViewport(rect: GeoRect(center: Coordinate(latitude: 0, longitude: 0), latitudeDelta: 1, longitudeDelta: 1), center: Coordinate(latitude: 0, longitude: 0), worldSize: 256).zoomBucket == 0)
        #expect(MapViewport(rect: GeoRect(center: Coordinate(latitude: 0, longitude: 0), latitudeDelta: 1, longitudeDelta: 1), center: Coordinate(latitude: 0, longitude: 0), worldSize: 1023).zoomBucket == 1)
    }
}

@Suite("MerchantClusterer")
struct ClustererTests {
    let nashville = Coordinate(latitude: 36.16, longitude: -86.78)

    @Test func nearbyMerchantsClusterAtCountryZoom() {
        let merchants = (0..<50).map { summary($0, 36.16 + Double($0) * 0.0005, -86.78) }
        let items = MerchantClusterer.cluster(merchants, viewport: viewport(center: nashville, span: 20))
        #expect(items.count < 5)
        #expect(merchantCount(items) == 50)
    }

    @Test func spreadOutMerchantsStayPinsAtStreetZoom() {
        // 0.02° apart on a 0.05°-wide, 400 pt map: ~200 pt between pins, more than a cell.
        let merchants = (0..<10).map { summary($0, 36.16 + Double($0) * 0.02, -86.78) }
        let items = MerchantClusterer.cluster(merchants, viewport: viewport(center: nashville, span: 0.05))
        #expect(items.count == 10)
        #expect(items.allSatisfy { if case .merchant = $0 { true } else { false } })
    }

    @Test func clusterIDsAreStableWhilePanning() {
        let merchants = (0..<200).map { summary($0, 36 + Double($0 % 20) * 0.01, -87 + Double($0 / 20) * 0.01) }
        let a = MerchantClusterer.cluster(merchants, viewport: viewport(center: nashville, span: 2))
        let panned = MapViewport(
            rect: GeoRect(center: Coordinate(latitude: 36.3, longitude: -86.6), latitudeDelta: 2, longitudeDelta: 2),
            center: Coordinate(latitude: 36.3, longitude: -86.6),
            worldSize: viewport(center: nashville, span: 2).worldSize
        )
        let b = MerchantClusterer.cluster(merchants, viewport: panned)
        #expect(a.map(\.id) == b.map(\.id))
    }

    @Test func selectedMerchantIsNeverClustered() {
        let merchants = (0..<20).map { summary($0, 36.16, -86.78 + Double($0) * 0.0001) }
        let items = MerchantClusterer.cluster(merchants, viewport: viewport(center: nashville, span: 10), selected: MerchantID(7))
        #expect(items.contains { $0.id == .merchant(MerchantID(7)) })
        #expect(merchantCount(items) == 20)
        for item in items {
            if case .cluster(_, _, _, let members, _) = item {
                #expect(!members.contains(MerchantID(7)))
            }
        }
    }

    @Test func colocatedMerchantsClusterAtMaxZoom() {
        let merchants = [summary(1, 36.16, -86.78), summary(2, 36.16, -86.78), summary(3, 36.1601, -86.78)]
        let deep = MapViewport(
            rect: GeoRect(center: nashville, latitudeDelta: 0.001, longitudeDelta: 0.001),
            center: nashville,
            worldSize: 256 * pow(2, 19)
        )
        let items = MerchantClusterer.cluster(merchants, viewport: deep)
        #expect(items.count == 2)
        #expect(items.contains { if case .cluster(_, _, 2, _, _) = $0 { true } else { false } })
    }

    @Test func sampleCategoryIsTheMostCommon() {
        let merchants = [
            summary(1, 36.16, -86.78, category: "restaurant"),
            summary(2, 36.1601, -86.78, category: "local_cafe"),
            summary(3, 36.1602, -86.78, category: "local_cafe"),
        ]
        let items = MerchantClusterer.cluster(merchants, viewport: viewport(center: nashville, span: 20))
        guard case .cluster(_, _, _, _, let category) = items.first else {
            Issue.record("expected one cluster"); return
        }
        #expect(category == MerchantCategory(rawValue: "local_cafe"))
    }
}

private actor FakeSource: MerchantViewportSource {
    var merchants: [MerchantSummary]
    private(set) var queries: [GeoRect] = []

    init(_ merchants: [MerchantSummary]) { self.merchants = merchants }

    func summaries(in rect: GeoRect, filter: MerchantFilter, limit: Int) async throws -> [MerchantSummary] {
        queries.append(rect)
        return Array(merchants.filter { rect.contains($0.coordinate) && filter.matches($0) }.prefix(limit))
    }

    func set(_ merchants: [MerchantSummary]) { self.merchants = merchants }
}

@Suite("MapModel")
@MainActor
struct MapModelTests {
    let nashville = Coordinate(latitude: 36.16, longitude: -86.78)

    @Test func publishesItemsAndNearestFirstList() async {
        let source = FakeSource([summary(1, 36.20, -86.78), summary(2, 36.161, -86.78), summary(3, 50, 10)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        await model.settle()
        #expect(model.visibleSummaries.map(\.id) == [MerchantID(2), MerchantID(1)])
        #expect(model.visibleCount == 2)
        #expect(merchantCount(model.items) == 2)
        #expect(model.revision == 1)
    }

    @Test func noTwentyFiveMileCap() async {
        // Two merchants ~110 km apart, both on screen at a regional zoom.
        let source = FakeSource([summary(1, 36.16, -86.78), summary(2, 37.16, -86.78)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: Coordinate(latitude: 36.66, longitude: -86.78), span: 3))
        await model.settle()
        #expect(model.visibleCount == 2)
    }

    @Test func latestCameraWins() async {
        let source = FakeSource([summary(1, 36.16, -86.78), summary(2, 51.5, -0.12)])
        let model = MapModel(source: source, configuration: .init(debounce: .milliseconds(50)))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        model.cameraDidChange(viewport(center: Coordinate(latitude: 51.5, longitude: -0.12), span: 0.5))
        await model.settle()
        #expect(model.visibleSummaries.map(\.id) == [MerchantID(2)])
        #expect(model.revision == 1)
        #expect(await source.queries.count == 1)
    }

    @Test func queryIncludesMargin() async {
        let source = FakeSource([summary(1, 36.16 + 0.3, -86.78)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        await model.settle()
        // Outside the visible rect (half-span 0.25) but inside the 25% margin: drawn, not listed.
        #expect(merchantCount(model.items) == 1)
        #expect(model.visibleSummaries.isEmpty)
    }

    @Test func filterRequeries() async {
        let source = FakeSource([summary(1, 36.16, -86.78, category: "local_atm"), summary(2, 36.161, -86.78)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        await model.settle()
        #expect(model.visibleCount == 2)
        model.filter = MerchantFilter(hideATMs: true)
        await model.settle()
        #expect(model.visibleSummaries.map(\.id) == [MerchantID(2)])
    }

    @Test func restrictionLimitsPinsAndListUntilCleared() async {
        let source = FakeSource([summary(1, 36.16, -86.78), summary(2, 36.161, -86.78), summary(3, 36.162, -86.78)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        await model.settle()
        #expect(model.visibleCount == 3)
        model.restriction = [MerchantID(1), MerchantID(3)]
        await model.settle()
        #expect(Set(model.visibleSummaries.map(\.id)) == [MerchantID(1), MerchantID(3)])
        #expect(merchantCount(model.items) == 2)
        model.restriction = []
        await model.settle()
        #expect(model.visibleCount == 0)
        #expect(model.items.isEmpty)
        model.restriction = nil
        await model.settle()
        #expect(model.visibleCount == 3)
    }

    @Test func refreshPicksUpNewRows() async {
        let source = FakeSource([summary(1, 36.16, -86.78)])
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 0.5))
        await model.settle()
        await source.set([summary(1, 36.16, -86.78), summary(2, 36.161, -86.78)])
        model.refresh()
        await model.settle()
        #expect(model.visibleCount == 2)
    }

    @Test func selectionReclustersWithoutQuerying() async {
        let merchants = (0..<20).map { summary($0, 36.16, -86.78 + Double($0) * 0.0001) }
        let source = FakeSource(merchants)
        let model = MapModel(source: source, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: nashville, span: 10))
        await model.settle()
        #expect(!model.items.contains { $0.id == .merchant(MerchantID(5)) })
        model.selectedID = MerchantID(5)
        await model.settle()
        #expect(model.items.contains { $0.id == .merchant(MerchantID(5)) })
        #expect(await source.queries.count == 1)
    }

    @Test func storeBackedEndToEnd() async throws {
        let store = try MerchantStore(url: nil)
        let rows = (0..<100).map { i in
            Merchant(
                summary: summary(i, 36.0 + Double(i) * 0.01, -86.78),
                isHydrated: true
            )
        }
        try await store.apply(SyncBatch(upserts: rows))
        let model = MapModel(source: store, configuration: .init(debounce: .zero))
        model.cameraDidChange(viewport(center: Coordinate(latitude: 36.5, longitude: -86.78), span: 2))
        await model.settle()
        #expect(model.visibleCount == 100)
        #expect(merchantCount(model.items) == 100)
    }
}
