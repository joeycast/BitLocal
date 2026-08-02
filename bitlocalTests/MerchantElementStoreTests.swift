import XCTest
@testable import bitlocal

final class MerchantElementStoreTests: XCTestCase {
    func testReplaceAllIndexesByID() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "1", name: "A"),
            makeElement(id: "2", name: "B")
        ])
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.element(id: "1")?.osmJSON?.tags?.name, "A")
        XCTAssertEqual(store.revision, 1)
    }

    func testUpsertDoesNotRebuildFromScratchForOtherIDs() {
        let store = MerchantElementStore()
        store.replaceAll([makeElement(id: "1", name: "A"), makeElement(id: "2", name: "B")])
        let revisionAfterLoad = store.revision
        store.upsert(makeElement(id: "1", name: "A2"))
        XCTAssertEqual(store.element(id: "1")?.osmJSON?.tags?.name, "A2")
        XCTAssertEqual(store.element(id: "2")?.osmJSON?.tags?.name, "B")
        XCTAssertEqual(store.revision, revisionAfterLoad + 1)
    }

    func testUpsertManyAndElementsByIDs() {
        let store = MerchantElementStore()
        store.replaceAll([makeElement(id: "1", name: "A")])
        store.upsertMany([
            makeElement(id: "2", name: "B"),
            makeElement(id: "3", name: "C")
        ])
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.elements(ids: ["3", "1", "missing"]).map(\.id), ["3", "1"])
    }

    func testSnapshotIsDeterministicallyOrderedByID() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "b", name: "B"),
            makeElement(id: "a", name: "A"),
            makeElement(id: "c", name: "C")
        ])
        XCTAssertEqual(store.snapshot().map(\.id), ["a", "b", "c"])
    }

    func testDuplicateIDsInReplaceKeepLast() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "1", name: "first"),
            makeElement(id: "1", name: "second")
        ])
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.element(id: "1")?.osmJSON?.tags?.name, "second")
    }

    private func makeElement(id: String, name: String) -> Element {
        let tags = OsmTags(
            addrCity: nil,
            addrHousenumber: nil,
            addrPostcode: nil,
            addrState: nil,
            addrStreet: nil,
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            name: name,
            operator: nil,
            brand: nil,
            brandWikidata: nil,
            description: nil,
            descriptionEn: nil,
            website: nil,
            contactWebsite: nil,
            phone: nil,
            contactPhone: nil,
            openingHours: nil,
            cuisine: nil,
            shop: nil,
            sport: nil,
            tourism: nil,
            healthcare: nil,
            craft: nil,
            amenity: nil,
            place: nil,
            leisure: nil,
            office: nil,
            building: nil,
            company: nil
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: 0,
            lon: 0,
            tags: tags,
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
