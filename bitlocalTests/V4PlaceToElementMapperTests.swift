import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.sync))
struct V4PlaceToElementMapperTests {
    @Test func mapsV4PlaceRecordIntoElementAndMetadata() {
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
            osmBrand: nil,
            osmBrandWikidata: "Q7605233"
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        #expect(element.id == "42")
        #expect(element.osmJSON?.lat == 10.0)
        #expect(element.osmJSON?.lon == 20.0)
        #expect(element.osmJSON?.tags?.name == "Cafe Bitcoin")
        #expect(element.osmJSON?.tags?.openingHours == "24/7")
        #expect(element.osmJSON?.tags?.amenity == "cafe")
        #expect(element.osmJSON?.tags?.paymentLightning == "yes")
        #expect(element.osmJSON?.tags?.brandWikidata == "Q7605233")
        #expect(element.osmJSON?.tags?.addrCity == "Nashville")
        #expect(element.v4Metadata?.commentsCount == 3)
        #expect(element.v4Metadata?.verifiedAt == "2025-01-03T00:00:00Z")
        #expect(element.v4Metadata?.paymentProvider == "coinos")
        #expect(element.v4Metadata?.imageURL == "https://cdn.example.com/cafe.jpg")
    }

    @Test func mapsIconToShopCategoryWhenNeeded() {
        let record = V4PlaceRecord(
            id: 43,
            lat: 10.0,
            lon: 20.0,
            icon: "computer",
            name: "Bitcoin Computers",
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-02T00:00:00Z",
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
            osmBrand: nil,
            osmBrandWikidata: nil
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        #expect(element.osmJSON?.tags?.shop == "computer")
        #expect(element.osmJSON?.tags?.amenity == nil)
    }

    @Test func symbolResolutionUsesMaterialV4IconAliasWhenTagsMissing() {
        let element = Element(
            id: "1",
            osmJSON: nil,
            tags: Tags(
                category: nil,
                iconPlatform: "lunch_dining",
                paymentCoinos: nil,
                paymentPouch: nil,
                boostExpires: nil,
                categoryPlural: nil,
                paymentProvider: nil,
                paymentURI: nil
            ),
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-01T00:00:00Z",
            deletedAt: nil,
            address: nil,
            v4Metadata: ElementV4Metadata(
                icon: "lunch_dining",
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
        )

        #expect(ElementCategorySymbols.symbolName(for: element) == "fork.knife.circle.fill")
    }

    @Test func tagsCodingPreservesLegacyIconPayloadKey() throws {
        let iconPayloadKey = "icon:" + String(decoding: [97, 110, 100, 114, 111, 105, 100], as: UTF8.self)
        let jsonData = try JSONSerialization.data(
            withJSONObject: [iconPayloadKey: "local_cafe", "payment:provider": "coinos"]
        )

        let decoded = try JSONDecoder().decode(Tags.self, from: jsonData)

        #expect(decoded.iconPlatform == "local_cafe")
        #expect(decoded.paymentProvider == "coinos")

        let encodedData = try JSONEncoder().encode(decoded)
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encodedData) as? [String: String])

        #expect(encodedObject[iconPayloadKey] == "local_cafe")
        #expect(encodedObject["payment:provider"] == "coinos")
    }
}

@Suite(.tags(.sync))
struct OSMOpeningHoursParserTests {
    @Test func parsesWeekdayAndWeekendRanges() {
        let raw = "Mo-Fr 06:30-15:00; Sa 07:00-14:00; Su 08:00-13:00"

        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        #expect(schedule?.days.first(where: { $0.weekday == .monday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 390, endMinutes: 900)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .saturday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 420, endMinutes: 840)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .sunday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 780)
        ])
    }

    @Test func parsesMixedDayLists() {
        let raw = "Tu 10:00-18:00; We, Fr, Sa 09:00-17:00; Th 11:00-19:00; Su 11:00-17:00"

        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        #expect(schedule?.days.first(where: { $0.weekday == .monday })?.ranges == [])
        #expect(schedule?.days.first(where: { $0.weekday == .tuesday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 600, endMinutes: 1080)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .wednesday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 540, endMinutes: 1020)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .friday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 540, endMinutes: 1020)
        ])
    }

    @Test func parsesTwentyFourSeven() {
        let schedule = OSMOpeningHoursParser.parseWeekSchedule("24/7")

        #expect(schedule?.days.count == 7)
        #expect(schedule?.isTwentyFourSeven == true)
    }

    @Test func parsesSingleRangeAcrossMostOfWeek() {
        let raw = "Mo-Sa 08:00-14:00"
        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        #expect(schedule?.days.first(where: { $0.weekday == .monday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 840)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .saturday })?.ranges == [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 840)
        ])
        #expect(schedule?.days.first(where: { $0.weekday == .sunday })?.ranges == [])
    }

    @Test func returnsNilForUnsupportedOrMalformedInput() {
        #expect(OSMOpeningHoursParser.parseWeekSchedule("Mo-Fr 9am-5pm") == nil)
        #expect(OSMOpeningHoursParser.parseWeekSchedule("PH off") == nil)
        #expect(OSMOpeningHoursParser.parseWeekSchedule("Mo-Fr 09:00-17:00 || \"by appointment\"") == nil)
    }
}
