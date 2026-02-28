import XCTest
@testable import bitlocal

final class BTCMapMergeTests: XCTestCase {
    func testMergeUpsertsNewerRecord() {
        let existing = [V4PlaceToElementMapper.placeRecordToElement(record(id: 1, updatedAt: "2025-01-01T00:00:00Z", name: "Old"))]
        let incoming = [V4PlaceToElementMapper.placeRecordToElement(record(id: 1, updatedAt: "2025-01-02T00:00:00Z", name: "New"))]

        let merged = BTCMapRepository.mergeElements(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.osmJSON?.tags?.name, "New")
    }

    func testMergeRemovesDeletedRecord() {
        let existing = [V4PlaceToElementMapper.placeRecordToElement(record(id: 1, updatedAt: "2025-01-01T00:00:00Z", name: "Keep"))]
        let deleted = V4PlaceToElementMapper.placeRecordToElement(record(id: 1, updatedAt: "2025-01-02T00:00:00Z", name: "Keep", deletedAt: "2025-01-02T00:00:00Z"))

        let merged = BTCMapRepository.mergeElements(existing: existing, incoming: [deleted])
        XCTAssertTrue(merged.isEmpty)
    }

    private func record(id: Int, updatedAt: String, name: String, deletedAt: String? = nil) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: 1,
            lon: 2,
            icon: nil,
            name: name,
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            verifiedAt: nil,
            osmID: nil,
            osmURL: nil,
            phone: nil,
            website: nil,
            twitter: nil,
            facebook: nil,
            instagram: nil,
            line: nil,
            telegram: nil,
            email: nil,
            boostedUntil: nil,
            requiredAppURL: nil,
            description: nil,
            image: nil,
            paymentProvider: nil,
            osmPaymentBitcoin: nil,
            osmCurrencyXBT: nil,
            osmPaymentOnchain: nil,
            osmPaymentLightning: nil,
            osmPaymentLightningContactless: nil,
            osmAddrHouseNumber: nil,
            osmAddrStreet: nil,
            osmAddrCity: nil,
            osmAddrState: nil,
            osmAddrPostcode: nil,
            osmOperator: nil,
            osmBrand: nil
        )
    }
}
