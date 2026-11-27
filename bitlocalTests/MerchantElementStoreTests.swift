import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.sync))
struct MerchantElementStoreTests {
    @Test func replaceAllIndexesByID() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "1", name: "A"),
            makeElement(id: "2", name: "B")
        ])
        #expect(store.count == 2)
        #expect(store.element(id: "1")?.osmJSON?.tags?.name == "A")
        #expect(store.revision == 1)
    }

    @Test func upsertDoesNotRebuildFromScratchForOtherIDs() {
        let store = MerchantElementStore()
        store.replaceAll([makeElement(id: "1", name: "A"), makeElement(id: "2", name: "B")])
        let revisionAfterLoad = store.revision
        store.upsert(makeElement(id: "1", name: "A2"))
        #expect(store.element(id: "1")?.osmJSON?.tags?.name == "A2")
        #expect(store.element(id: "2")?.osmJSON?.tags?.name == "B")
        #expect(store.revision == revisionAfterLoad + 1)
    }

    @Test func upsertManyAndElementsByIDs() {
        let store = MerchantElementStore()
        store.replaceAll([makeElement(id: "1", name: "A")])
        store.upsertMany([
            makeElement(id: "2", name: "B"),
            makeElement(id: "3", name: "C")
        ])
        #expect(store.count == 3)
        #expect(store.elements(ids: ["3", "1", "missing"]).map(\.id) == ["3", "1"])
    }

    @Test func snapshotPreservesFirstSeenOrderWithoutSorting() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "b", name: "B"),
            makeElement(id: "a", name: "A"),
            makeElement(id: "c", name: "C")
        ])
        // Stable first-seen order — sorting ~25k ids on every upsert is too expensive.
        #expect(store.snapshot().map(\.id) == ["b", "a", "c"])
    }

    @Test func upsertKeepsExistingPositionAndAppendsNewIDs() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "b", name: "B"),
            makeElement(id: "a", name: "A")
        ])
        store.upsert(makeElement(id: "b", name: "B2"))
        store.upsert(makeElement(id: "z", name: "Z"))
        #expect(store.snapshot().map(\.id) == ["b", "a", "z"])
        #expect(store.element(id: "b")?.osmJSON?.tags?.name == "B2")
    }

    @Test func duplicateIDsInReplaceKeepLastAtFirstPosition() {
        let store = MerchantElementStore()
        store.replaceAll([
            makeElement(id: "1", name: "first"),
            makeElement(id: "2", name: "two"),
            makeElement(id: "1", name: "second")
        ])
        #expect(store.count == 2)
        #expect(store.element(id: "1")?.osmJSON?.tags?.name == "second")
        #expect(store.snapshot().map(\.id) == ["1", "2"])
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
