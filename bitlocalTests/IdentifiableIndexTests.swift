import XCTest
@testable import bitlocal

final class IdentifiableIndexTests: XCTestCase {
    func testByIDKeepsLastDuplicateWithoutTrapping() {
        let first = makeElement(id: "1", name: "First")
        let second = makeElement(id: "1", name: "Second")
        let third = makeElement(id: "2", name: "Other")

        let indexed = IdentifiableIndex.byID([first, second, third])
        XCTAssertEqual(indexed.count, 2)
        XCTAssertEqual(indexed["1"]?.osmJSON?.tags?.name, "Second")
        XCTAssertEqual(indexed["2"]?.osmJSON?.tags?.name, "Other")
    }

    func testByIDFirstWinsWhenCombinePrefersExisting() {
        let first = makeElement(id: "1", name: "First")
        let second = makeElement(id: "1", name: "Second")

        let indexed = IdentifiableIndex.byID([first, second], uniquingKeysWith: { existing, _ in existing })
        XCTAssertEqual(indexed["1"]?.osmJSON?.tags?.name, "First")
    }

    func testDictionaryHelperUniquesArbitraryKeys() {
        let pairs = [("a", 1), ("a", 2), ("b", 3)]
        let dict = IdentifiableIndex.dictionary(pairs)
        XCTAssertEqual(dict, ["a": 2, "b": 3])
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
