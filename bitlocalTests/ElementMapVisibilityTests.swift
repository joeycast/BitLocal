import XCTest
@testable import bitlocal

final class ElementMapVisibilityTests: XCTestCase {
    func testBrandOnlyMerchantHasMapRenderableIdentity() {
        let element = makeElement(name: nil, brand: "Steak 'n Shake", operatorName: nil)
        XCTAssertEqual(element.displayName, "Steak 'n Shake")
        XCTAssertTrue(element.hasMapRenderableIdentity)
    }

    func testOperatorOnlyMerchantHasMapRenderableIdentity() {
        let element = makeElement(name: nil, brand: nil, operatorName: "Acme Ops LLC")
        XCTAssertEqual(element.displayName, "Acme Ops LLC")
        XCTAssertTrue(element.hasMapRenderableIdentity)
    }

    func testNamedMerchantHasMapRenderableIdentity() {
        let element = makeElement(name: "Cafe Bitcoin", brand: nil, operatorName: nil)
        XCTAssertTrue(element.hasMapRenderableIdentity)
    }

    func testPlaceholderNameStillHasMapRenderableIdentity() {
        let element = makeElement(name: "BTC Map Place #42", brand: nil, operatorName: nil)
        XCTAssertNil(element.displayName)
        XCTAssertTrue(element.hasMapRenderableIdentity)
    }

    func testEmptyIdentityIsNotMapRenderable() {
        let element = makeElement(name: nil, brand: nil, operatorName: nil)
        XCTAssertNil(element.displayName)
        XCTAssertFalse(element.hasMapRenderableIdentity)
    }

    func testUnnamedWithoutFallbackIsNotMapRenderable() {
        let element = makeElement(name: "unnamed", brand: nil, operatorName: nil)
        XCTAssertNil(element.displayName)
        XCTAssertFalse(element.hasMapRenderableIdentity)
    }

    func testAmenityATMIsDetected() {
        let element = makeElement(name: "BTC ATM", brand: nil, operatorName: nil, amenity: "atm")
        XCTAssertTrue(element.isATM)
    }

    func testLocalATMIconIsDetected() {
        let element = makeElement(name: "Cash Point", brand: nil, operatorName: nil, icon: "local_atm")
        XCTAssertTrue(element.isATM)
    }

    func testCafeIsNotATM() {
        let element = makeElement(name: "Cafe", brand: nil, operatorName: nil, amenity: "cafe", icon: "local_cafe")
        XCTAssertFalse(element.isATM)
    }

    func testBankIsNotATM() {
        let element = makeElement(name: "Bank", brand: nil, operatorName: nil, amenity: "bank")
        XCTAssertFalse(element.isATM)
    }

    private func makeElement(
        name: String?,
        brand: String?,
        operatorName: String?,
        amenity: String? = nil,
        icon: String? = nil
    ) -> Element {
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
            operator: operatorName,
            brand: brand,
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
            amenity: amenity,
            place: nil,
            leisure: nil,
            office: nil,
            building: nil,
            company: nil
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: 36.16,
            lon: -86.78,
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
        var element = Element(
            id: "test",
            osmJSON: osmJSON,
            tags: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
        if let icon {
            element.v4Metadata = ElementV4Metadata(
                icon: icon,
                commentsCount: nil,
                verifiedAt: nil,
                boostedUntil: nil,
                osmID: nil,
                osmURL: nil,
                email: nil,
                twitter: nil,
                facebook: nil,
                instagram: nil,
                telegram: nil,
                line: nil,
                requiredAppURL: nil,
                imageURL: nil,
                paymentProvider: nil,
                rawAddress: nil
            )
        }
        return element
    }
}
