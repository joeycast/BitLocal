import XCTest
@testable import bitlocal

final class MerchantSpatialIndexTests: XCTestCase {
    func testCandidatesRespectBoundingBox() {
        let elements = [
            makeElement(id: "in", lat: 36.16, lon: -86.78),
            makeElement(id: "out", lat: 40.0, lon: -74.0)
        ]
        var index = MerchantSpatialIndex(cellSizeDegrees: 0.05)
        index.rebuild(from: elements, sourceSignature: 1)

        let hits = index.candidates(
            minLatitude: 36.0,
            maxLatitude: 36.3,
            minLongitude: -87.0,
            maxLongitude: -86.5
        )
        XCTAssertEqual(hits.map(\.id), ["in"])
    }

    func testRebuildReplacesPreviousEntries() {
        var index = MerchantSpatialIndex(cellSizeDegrees: 0.1)
        index.rebuild(from: [makeElement(id: "a", lat: 1, lon: 1)], sourceSignature: 1)
        XCTAssertEqual(index.entryCount, 1)

        index.rebuild(from: [
            makeElement(id: "b", lat: 2, lon: 2),
            makeElement(id: "c", lat: 3, lon: 3)
        ], sourceSignature: 2)
        XCTAssertEqual(index.entryCount, 2)
        XCTAssertEqual(index.sourceSignature, 2)

        let hits = index.candidates(minLatitude: 1.5, maxLatitude: 2.5, minLongitude: 1.5, maxLongitude: 2.5)
        XCTAssertEqual(hits.map(\.id), ["b"])
    }

    func testPolygonBoundingBoxFromOuterRing() {
        let polygon: [[[[Double]]]] = [[
            [
                [-87.0, 36.0],
                [-86.0, 36.0],
                [-86.0, 37.0],
                [-87.0, 37.0],
                [-87.0, 36.0]
            ]
        ]]
        let box = MerchantPolygonGeometry.boundingBox(for: polygon)
        XCTAssertEqual(box?.minLat, 36.0)
        XCTAssertEqual(box?.maxLat, 37.0)
        XCTAssertEqual(box?.minLon, -87.0)
        XCTAssertEqual(box?.maxLon, -86.0)
    }

    func testCandidatesAcrossAntimeridianUseShortArc() {
        // Points near ±180; naive min/max lon span is huge and would cover the wrong ocean.
        let elements = [
            makeElement(id: "pacific-west", lat: 0, lon: 179.9),
            makeElement(id: "pacific-east", lat: 0, lon: -179.9),
            makeElement(id: "atlantic", lat: 0, lon: 0)
        ]
        var index = MerchantSpatialIndex(cellSizeDegrees: 0.5)
        index.rebuild(from: elements, sourceSignature: 1)

        let hits = index.candidates(
            minLatitude: -1,
            maxLatitude: 1,
            minLongitude: -179.8,
            maxLongitude: 179.8
        )
        let ids = Set(hits.map(\.id))
        XCTAssertTrue(ids.contains("pacific-west"))
        XCTAssertTrue(ids.contains("pacific-east"))
        XCTAssertFalse(ids.contains("atlantic"))
    }

    private func makeElement(id: String, lat: Double, lon: Double) -> Element {
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
        return Element(
            id: id,
            osmJSON: osmJSON,
            tags: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }
}
