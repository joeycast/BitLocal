import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.sync))
struct V4PlaceRecordDecodingTests {
    @Test func decodesSnapshotRecordMinimalPayload() throws {
        let data = Data("""
        [{"id":123,"lat":1.23,"lon":4.56,"icon":"cafe","comments":2,"boosted_until":"2026-01-01T00:00:00Z"}]
        """.utf8)

        let records = try JSONDecoder().decode([V4PlaceSnapshotRecord].self, from: data)
        #expect(records.count == 1)
        #expect(records.first?.id == 123)
        #expect(records.first?.icon == "cafe")
        #expect(records.first?.comments == 2)
        #expect(records.first?.preferredName == nil)
    }

    @Test func decodesSnapshotRecordWithOptionalNameFields() throws {
        let data = Data("""
        [{"id":5,"lat":1.0,"lon":2.0,"icon":"hotel","name":"  Sea Lodge  ","display_name":"Sea Lodge Display"}]
        """.utf8)

        let record = try JSONDecoder().decode([V4PlaceSnapshotRecord].self, from: data).first
        #expect(record?.preferredName == "Sea Lodge")
        let element = V4PlaceToElementMapper.snapshotRecordToElement(
            try #require(record),
            fallbackTimestamp: "2026-01-01T00:00:00Z"
        )
        #expect(element.displayName == "Sea Lodge")
        #expect(Element.isPlaceholderName(element.osmJSON?.tags?.name ?? "") == false)
    }

    @Test func snapshotWithoutNameUsesCategoryDisplayNameWhileKeepingPlaceholderTag() {
        let record = V4PlaceSnapshotRecord(
            id: 9,
            lat: 1,
            lon: 2,
            icon: "local_cafe",
            comments: nil,
            boostedUntil: nil,
            name: nil,
            displayName: nil
        )
        let element = V4PlaceToElementMapper.snapshotRecordToElement(
            record,
            fallbackTimestamp: "2026-01-01T00:00:00Z"
        )
        #expect(Element.isPlaceholderName(element.osmJSON?.tags?.name ?? ""))
        // Category labels are UI-only — must not pollute displayName/search scoring.
        #expect(element.displayName == nil)
        #expect(element.displayNameForUI == MerchantCategoryGroup.coffee.localizedLabel)
    }

    @Test func decodesFullPlaceRecordWithOptionalFields() throws {
        let data = Data("""
        [{
          "id": 999,
          "lat": 40.0,
          "lon": -74.0,
          "icon": "restaurant",
          "name": "Test Merchant",
          "address": "123 Main St",
          "opening_hours": "Mo-Fr 09:00-17:00",
          "comments": 7,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-02T00:00:00Z",
          "verified_at": "2025-01-03T00:00:00Z",
          "osm_id": "node/1",
          "osm_url": "https://www.openstreetmap.org/node/1",
          "phone": "+1-555-0100",
          "website": "example.com",
          "twitter": "example",
          "facebook": "https://facebook.com/example",
          "instagram": "example_ig",
          "telegram": "exampletg",
          "line": "https://line.me/example",
          "email": "hello@example.com",
          "boosted_until": "2025-01-10T00:00:00Z",
          "required_app_url": "https://apps.apple.com/us/app/example",
          "description": "Great place",
          "image": "https://cdn.example.com/image.jpg",
          "payment_provider": "coinos",
          "osm:payment:bitcoin": "yes",
          "osm:payment:lightning": "yes",
          "osm:addr:housenumber": "123",
          "osm:addr:street": "Main St",
          "osm:addr:city": "New York",
          "osm:addr:state": "NY",
          "osm:addr:postcode": "10001",
          "osm:brand:wikidata": "Q7605233"
        }]
        """.utf8)

        let records = try JSONDecoder().decode([V4PlaceRecord].self, from: data)
        let record = try #require(records.first)
        #expect(record.id == 999)
        #expect(record.displayName == "Test Merchant")
        #expect(record.paymentProvider == "coinos")
        #expect(record.osmPaymentBitcoin == "yes")
        #expect(record.osmPaymentLightning == "yes")
        #expect(record.osmAddrCity == "New York")
        #expect(record.osmBrandWikidata == "Q7605233")
    }

    @Test func boostHelpersUseFuturePastAndInvalidDatesCorrectly() {
        let referenceDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

        let boostedRecord = Self.makePlaceRecord(id: 1, boostedUntil: "2025-02-01T00:00:00Z")
        let expiredRecord = Self.makePlaceRecord(id: 2, boostedUntil: "2024-12-01T00:00:00Z")
        let invalidRecord = Self.makePlaceRecord(id: 3, boostedUntil: "not-a-date")
        let noBoostRecord = Self.makePlaceRecord(id: 4, boostedUntil: nil)

        #expect(boostedRecord.isCurrentlyBoosted(referenceDate: referenceDate))
        #expect(expiredRecord.isCurrentlyBoosted(referenceDate: referenceDate) == false)
        #expect(invalidRecord.isCurrentlyBoosted(referenceDate: referenceDate) == false)
        #expect(noBoostRecord.isCurrentlyBoosted(referenceDate: referenceDate) == false)
    }

    @Test func elementAndPlaceRecordAgreeOnBoostState() {
        let referenceDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
        let record = Self.makePlaceRecord(id: 5, boostedUntil: "2025-03-01T12:00:00Z")
        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        #expect(record.isCurrentlyBoosted(referenceDate: referenceDate) == element.isCurrentlyBoosted(referenceDate: referenceDate))
        #expect(record.boostExpirationDate == element.boostExpirationDate)
    }
    private static func makePlaceRecord(id: Int, boostedUntil: String?) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: 1.23,
            lon: 4.56,
            icon: "cafe",
            name: "Merchant \(id)",
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-01T00:00:00Z",
            deletedAt: nil,
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
            boostedUntil: boostedUntil,
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
            osmBrand: nil,
            osmBrandWikidata: nil
        )
    }
}
