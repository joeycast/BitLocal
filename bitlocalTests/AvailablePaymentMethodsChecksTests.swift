import XCTest
@testable import bitlocal

final class AvailablePaymentMethodsChecksTests: XCTestCase {
    func testInfersLightningForKnownBrandWhenPaymentTagsMissing() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: "Q7605233"
        )

        XCTAssertTrue(acceptsLightning(element: element))
        XCTAssertFalse(acceptsBitcoin(element: element))
        XCTAssertFalse(acceptsBitcoinOnChain(element: element))
        XCTAssertFalse(acceptsContactlessLightning(element: element))
    }

    func testDoesNotInferLightningWhenExplicitPaymentTagsExist() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: "yes",
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: "Q7605233"
        )

        XCTAssertFalse(acceptsLightning(element: element))
        XCTAssertTrue(acceptsBitcoinOnChain(element: element))
    }

    func testInfersLightningForKnownBrandNameWhenWikidataMissing() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: nil
        )

        XCTAssertTrue(acceptsLightning(element: element))
        XCTAssertFalse(acceptsBitcoin(element: element))
        XCTAssertFalse(acceptsBitcoinOnChain(element: element))
        XCTAssertFalse(acceptsContactlessLightning(element: element))
    }

    private func makeElement(
        paymentBitcoin: String?,
        currencyXBT: String?,
        paymentOnchain: String?,
        paymentLightning: String?,
        paymentLightningContactless: String?,
        brandWikidata: String?
    ) -> Element {
        let tags = OsmTags(
            addrCity: nil,
            addrCountry: nil,
            addrHousenumber: nil,
            addrPostcode: nil,
            addrState: nil,
            addrStreet: nil,
            paymentBitcoin: paymentBitcoin,
            currencyXBT: currencyXBT,
            paymentOnchain: paymentOnchain,
            paymentLightning: paymentLightning,
            paymentLightningContactless: paymentLightningContactless,
            name: "Test Place",
            operator: nil,
            brand: "Steak 'n Shake",
            brandWikidata: brandWikidata,
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
            id: "1",
            osmJSON: osmJSON,
            tags: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
    }
}
