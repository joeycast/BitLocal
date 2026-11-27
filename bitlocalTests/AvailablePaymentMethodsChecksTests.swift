import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.formatting))
struct AvailablePaymentMethodsChecksTests {
    @Test func infersLightningForKnownBrandWhenPaymentTagsMissing() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: "Q7605233"
        )

        #expect(acceptsLightning(element: element))
        #expect(acceptsBitcoin(element: element) == false)
        #expect(acceptsBitcoinOnChain(element: element) == false)
        #expect(acceptsContactlessLightning(element: element) == false)
    }

    @Test func doesNotInferLightningWhenExplicitPaymentTagsExist() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: "yes",
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: "Q7605233"
        )

        #expect(acceptsLightning(element: element) == false)
        #expect(acceptsBitcoinOnChain(element: element))
    }

    @Test func infersLightningForKnownBrandNameWhenWikidataMissing() {
        let element = makeElement(
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            brandWikidata: nil
        )

        #expect(acceptsLightning(element: element))
        #expect(acceptsBitcoin(element: element) == false)
        #expect(acceptsBitcoinOnChain(element: element) == false)
        #expect(acceptsContactlessLightning(element: element) == false)
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
