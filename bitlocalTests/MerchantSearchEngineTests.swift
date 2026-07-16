import XCTest
@testable import bitlocal

final class MerchantSearchEngineTests: XCTestCase {
    func testMatchScoresExactNameHigherThanCategory() {
        let cafe = makeElement(id: "1", name: "Da Vinci Coffee", icon: "local_cafe")
        let other = makeElement(id: "2", name: "Random Shop", icon: "local_cafe")
        let query = SearchTextNormalizer.normalize("Da Vinci Coffee")
        let cafeMatch = MerchantSearchEngine.match(
            document: MerchantSearchEngine.document(for: cafe),
            normalizedQuery: query,
            resolvedGroup: nil
        )
        let otherMatch = MerchantSearchEngine.match(
            document: MerchantSearchEngine.document(for: other),
            normalizedQuery: SearchTextNormalizer.normalize("coffee"),
            resolvedGroup: .coffee
        )
        XCTAssertNotNil(cafeMatch)
        XCTAssertNotNil(otherMatch)
        XCTAssertGreaterThan(cafeMatch!.score, otherMatch!.score)
    }

    func testFilterElementsReturnsScores() {
        let elements = [
            makeElement(id: "1", name: "Cafe Bitcoin", icon: "local_cafe"),
            makeElement(id: "2", name: "Hardware Store", icon: "hardware")
        ]
        let result = MerchantSearchEngine.filterElements(
            elements,
            normalizedQuery: SearchTextNormalizer.normalize("cafe"),
            documentProvider: MerchantSearchEngine.document(for:)
        )
        XCTAssertEqual(result.elements.map(\.id), ["1"])
        XCTAssertNotNil(result.scoresByID["1"])
    }

    private func makeElement(id: String, name: String, icon: String) -> Element {
        let tags = OsmTags(
            addrCity: nil, addrHousenumber: nil, addrPostcode: nil, addrState: nil, addrStreet: nil,
            paymentBitcoin: nil, currencyXBT: nil, paymentOnchain: nil, paymentLightning: nil,
            paymentLightningContactless: nil, name: name, operator: nil, brand: nil, brandWikidata: nil,
            description: nil, descriptionEn: nil, website: nil, contactWebsite: nil, phone: nil,
            contactPhone: nil, openingHours: nil, cuisine: nil, shop: nil, sport: nil, tourism: nil,
            healthcare: nil, craft: nil, amenity: nil, place: nil, leisure: nil, office: nil,
            building: nil, company: nil
        )
        let osmJSON = OsmJSON(
            changeset: nil, id: nil, lat: 36.1, lon: -86.7, tags: tags, timestamp: nil,
            type: .node, uid: nil, user: nil, version: nil, bounds: nil, geometry: nil,
            nodes: nil, members: nil
        )
        return Element(
            id: id,
            osmJSON: osmJSON,
            tags: Tags(
                category: nil, iconPlatform: icon, paymentCoinos: nil, paymentPouch: nil,
                boostExpires: nil, categoryPlural: nil, paymentProvider: nil, paymentURI: nil
            ),
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil,
            v4Metadata: ElementV4Metadata(
                icon: icon, commentsCount: nil, verifiedAt: nil, boostedUntil: nil,
                osmID: nil, osmURL: nil, email: nil, twitter: nil, facebook: nil, instagram: nil,
                telegram: nil, line: nil, requiredAppURL: nil, imageURL: nil, paymentProvider: nil,
                rawAddress: nil
            )
        )
    }
}
