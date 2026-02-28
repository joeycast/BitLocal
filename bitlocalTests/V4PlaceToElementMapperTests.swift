import XCTest
@testable import bitlocal

final class V4PlaceToElementMapperTests: XCTestCase {
    func testMapsV4PlaceRecordIntoElementAndMetadata() {
        let record = V4PlaceRecord(
            id: 42,
            lat: 10.0,
            lon: 20.0,
            icon: "cafe",
            name: "Cafe Bitcoin",
            address: "1 Lightning Ave",
            openingHours: "24/7",
            comments: 3,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z",
            deletedAt: nil,
            verifiedAt: "2025-01-03T00:00:00Z",
            osmID: "node/42",
            osmURL: "https://www.openstreetmap.org/node/42",
            phone: "+1 555 999 0000",
            website: "cafebitcoin.com",
            twitter: "cafebitcoin",
            facebook: nil,
            instagram: nil,
            line: nil,
            telegram: nil,
            email: "hello@cafebitcoin.com",
            boostedUntil: "2025-02-01T00:00:00Z",
            requiredAppURL: "https://apps.apple.com/us/app/example",
            description: "A bitcoin-first cafe",
            image: "https://cdn.example.com/cafe.jpg",
            paymentProvider: "coinos",
            osmPaymentBitcoin: "yes",
            osmCurrencyXBT: "yes",
            osmPaymentOnchain: "yes",
            osmPaymentLightning: "yes",
            osmPaymentLightningContactless: "yes",
            osmAddrHouseNumber: "1",
            osmAddrStreet: "Lightning Ave",
            osmAddrCity: "Nashville",
            osmAddrState: "TN",
            osmAddrPostcode: "37201",
            osmOperator: "Cafe Bitcoin LLC",
            osmBrand: nil
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        XCTAssertEqual(element.id, "42")
        XCTAssertEqual(element.osmJSON?.lat, 10.0)
        XCTAssertEqual(element.osmJSON?.lon, 20.0)
        XCTAssertEqual(element.osmJSON?.tags?.name, "Cafe Bitcoin")
        XCTAssertEqual(element.osmJSON?.tags?.openingHours, "24/7")
        XCTAssertEqual(element.osmJSON?.tags?.paymentLightning, "yes")
        XCTAssertEqual(element.osmJSON?.tags?.addrCity, "Nashville")
        XCTAssertEqual(element.v4Metadata?.commentsCount, 3)
        XCTAssertEqual(element.v4Metadata?.verifiedAt, "2025-01-03T00:00:00Z")
        XCTAssertEqual(element.v4Metadata?.paymentProvider, "coinos")
        XCTAssertEqual(element.v4Metadata?.imageURL, "https://cdn.example.com/cafe.jpg")
    }
}
