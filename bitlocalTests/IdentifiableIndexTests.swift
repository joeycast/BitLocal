import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.sync))
struct IdentifiableIndexTests {
    @Test func byIDKeepsLastDuplicateWithoutTrapping() {
        let first = makeElement(id: "1", name: "First")
        let second = makeElement(id: "1", name: "Second")
        let third = makeElement(id: "2", name: "Other")

        let indexed = IdentifiableIndex.byID([first, second, third])
        #expect(indexed.count == 2)
        #expect(indexed["1"]?.osmJSON?.tags?.name == "Second")
        #expect(indexed["2"]?.osmJSON?.tags?.name == "Other")
    }

    @Test func byIDFirstWinsWhenCombinePrefersExisting() {
        let first = makeElement(id: "1", name: "First")
        let second = makeElement(id: "1", name: "Second")

        let indexed = IdentifiableIndex.byID([first, second], uniquingKeysWith: { existing, _ in existing })
        #expect(indexed["1"]?.osmJSON?.tags?.name == "First")
    }

    @Test func dictionaryHelperUniquesArbitraryKeys() {
        let pairs = [("a", 1), ("a", 2), ("b", 3)]
        let dict = IdentifiableIndex.dictionary(pairs)
        #expect(dict == ["a": 2, "b": 3])
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
