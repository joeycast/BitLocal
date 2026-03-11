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
            osmAddrCountry: "US",
            osmAddrState: "TN",
            osmAddrPostcode: "37201",
            osmOperator: "Cafe Bitcoin LLC",
            osmBrand: nil,
            osmBrandWikidata: "Q7605233"
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        XCTAssertEqual(element.id, "42")
        XCTAssertEqual(element.osmJSON?.lat, 10.0)
        XCTAssertEqual(element.osmJSON?.lon, 20.0)
        XCTAssertEqual(element.osmJSON?.tags?.name, "Cafe Bitcoin")
        XCTAssertEqual(element.osmJSON?.tags?.openingHours, "24/7")
        XCTAssertEqual(element.osmJSON?.tags?.amenity, "cafe")
        XCTAssertEqual(element.osmJSON?.tags?.paymentLightning, "yes")
        XCTAssertEqual(element.osmJSON?.tags?.brandWikidata, "Q7605233")
        XCTAssertEqual(element.osmJSON?.tags?.addrCity, "Nashville")
        XCTAssertEqual(element.v4Metadata?.commentsCount, 3)
        XCTAssertEqual(element.v4Metadata?.verifiedAt, "2025-01-03T00:00:00Z")
        XCTAssertEqual(element.v4Metadata?.paymentProvider, "coinos")
        XCTAssertEqual(element.v4Metadata?.imageURL, "https://cdn.example.com/cafe.jpg")
        XCTAssertEqual(element.address?.countryCode, "US")
        XCTAssertEqual(element.address?.streetLine, "1 Lightning Ave")
    }

    func testMapsIconToShopCategoryWhenNeeded() {
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
            osmAddrCountry: nil,
            osmAddrState: nil,
            osmAddrPostcode: nil,
            osmOperator: nil,
            osmBrand: nil,
            osmBrandWikidata: nil
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        XCTAssertEqual(element.osmJSON?.tags?.shop, "computer")
        XCTAssertNil(element.osmJSON?.tags?.amenity)
    }

    func testKeepsRawAddressAsFallbackInsteadOfTreatingItAsStreet() {
        let record = V4PlaceRecord(
            id: 44,
            lat: 10.0,
            lon: 20.0,
            icon: "cafe",
            name: "Raw Address Merchant",
            address: "188 ซอย 6",
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
            osmAddrCountry: nil,
            osmAddrState: nil,
            osmAddrPostcode: nil,
            osmOperator: nil,
            osmBrand: nil,
            osmBrandWikidata: nil
        )

        let element = V4PlaceToElementMapper.placeRecordToElement(record)

        XCTAssertNil(element.address)
        XCTAssertEqual(element.v4Metadata?.rawAddress, "188 ซอย 6")
        XCTAssertNil(element.osmJSON?.tags?.addrStreet)
    }

    func testUsesStructuredAddressWhenAvailableAndHidesMatchingCountryInCompactStyle() {
        let address = Address(
            streetNumber: "1132",
            streetName: "4th Avenue South",
            cityOrTownName: "Nashville",
            postalCode: "37210",
            regionOrStateName: "TN",
            countryName: nil,
            countryCode: "US"
        )

        let compact = AddressDisplayFormatter.format(
            address: address,
            rawAddress: nil,
            style: .compact(referenceRegionCode: "US")
        )
        let detail = AddressDisplayFormatter.format(
            address: address,
            rawAddress: nil,
            style: .detail(includeCountry: true)
        )

        XCTAssertEqual(compact?.primaryLine, "1132 4th Avenue South")
        XCTAssertEqual(compact?.secondaryLine, "Nashville, TN 37210")
        XCTAssertEqual(detail?.multiline, "1132 4th Avenue South\nNashville, TN 37210\nUnited States")
        XCTAssertFalse(compact?.singleLine?.contains("United States") ?? true)
        XCTAssertTrue(detail?.singleLine?.contains("United States") ?? false)
    }

    func testNormalizesZipPlus4ForObviousUnitedStatesAddressWithoutCountryCode() {
        let address = Address(
            streetNumber: "3213",
            streetName: "Grand Avenue",
            cityOrTownName: "Miami",
            postalCode: Address.normalizedPostalCode(
                "33133-5010",
                countryName: nil,
                countryCode: nil,
                regionOrStateName: "FL"
            ),
            regionOrStateName: "FL",
            countryName: nil,
            countryCode: nil
        )

        let compact = AddressDisplayFormatter.format(
            address: address,
            rawAddress: nil,
            style: .compact(referenceRegionCode: "US")
        )

        XCTAssertEqual(address.postalCode, "33133")
        XCTAssertEqual(compact?.secondaryLine, "Miami, FL 33133")
    }

    func testUsesLocaleAwareOrderingForGermanyCompactRows() {
        let address = Address(
            streetNumber: "25",
            streetName: "Holzmarktstraße",
            cityOrTownName: "Berlin",
            postalCode: "10243",
            regionOrStateName: nil,
            countryName: nil,
            countryCode: "DE"
        )

        let compact = AddressDisplayFormatter.format(
            address: address,
            rawAddress: nil,
            style: .compact(referenceRegionCode: "US")
        )
        let detail = AddressDisplayFormatter.format(
            address: address,
            rawAddress: nil,
            style: .detail(includeCountry: true)
        )

        XCTAssertEqual(compact?.primaryLine, "25 Holzmarktstraße")
        XCTAssertEqual(compact?.secondaryLine, "10243 Berlin")
        XCTAssertFalse(compact?.singleLine?.contains("Germany") ?? true)
        XCTAssertTrue(detail?.singleLine?.contains("Germany") ?? false)
    }

    func testVisibleListRowKeepsFrozenCompactAddressUntilItReappears() {
        let initialAddress = Address(
            streetNumber: "72",
            streetName: "HH Kreuzbergstraße",
            cityOrTownName: "Berlin",
            postalCode: "10965",
            regionOrStateName: nil,
            countryName: nil,
            countryCode: nil
        )
        let enrichedAddress = Address(
            streetNumber: "72",
            streetName: "HH Kreuzbergstraße",
            cityOrTownName: "Berlin",
            postalCode: "10965",
            regionOrStateName: nil,
            countryName: "Germany",
            countryCode: "DE"
        )
        let element = Element(
            id: "frozen-row",
            osmJSON: nil,
            tags: nil,
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: "2025-01-01T00:00:00Z",
            deletedAt: nil,
            address: initialAddress,
            v4Metadata: ElementV4Metadata(
                icon: nil,
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
        let viewModel = ElementCellViewModel(
            element: element,
            userLocation: nil,
            viewModel: ContentViewModel(),
            allowsLiveAddressEnrichment: false
        )

        viewModel.onCellAppear()
        let frozenBefore = viewModel.compactDisplayAddress

        viewModel.adoptResolvedAddress(enrichedAddress)
        let frozenAfter = viewModel.compactDisplayAddress

        XCTAssertEqual(frozenBefore?.secondaryLine, "Berlin 10965")
        XCTAssertEqual(frozenAfter?.secondaryLine, "Berlin 10965")

        viewModel.onCellDisappear()
        viewModel.onCellAppear()

        XCTAssertEqual(viewModel.compactDisplayAddress?.secondaryLine, "10965 Berlin")
    }

    func testSymbolResolutionUsesMaterialV4IconAliasWhenTagsMissing() {
        let element = Element(
            id: "1",
            osmJSON: nil,
            tags: Tags(
                category: nil,
                iconAndroid: "lunch_dining",
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

        XCTAssertEqual(ElementCategorySymbols.symbolName(for: element), "fork.knife.circle.fill")
    }
}

final class OSMOpeningHoursParserTests: XCTestCase {
    func testParsesWeekdayAndWeekendRanges() {
        let raw = "Mo-Fr 06:30-15:00; Sa 07:00-14:00; Su 08:00-13:00"

        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .monday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 390, endMinutes: 900)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .saturday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 420, endMinutes: 840)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .sunday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 780)
        ])
    }

    func testParsesMixedDayLists() {
        let raw = "Tu 10:00-18:00; We, Fr, Sa 09:00-17:00; Th 11:00-19:00; Su 11:00-17:00"

        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .monday })?.ranges, [])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .tuesday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 600, endMinutes: 1080)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .wednesday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 540, endMinutes: 1020)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .friday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 540, endMinutes: 1020)
        ])
    }

    func testParsesTwentyFourSeven() {
        let schedule = OSMOpeningHoursParser.parseWeekSchedule("24/7")

        XCTAssertEqual(schedule?.days.count, 7)
        XCTAssertEqual(schedule?.isTwentyFourSeven, true)
    }

    func testParsesSingleRangeAcrossMostOfWeek() {
        let raw = "Mo-Sa 08:00-14:00"
        let schedule = OSMOpeningHoursParser.parseWeekSchedule(raw)

        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .monday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 840)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .saturday })?.ranges, [
            OSMOpeningHoursTimeRange(startMinutes: 480, endMinutes: 840)
        ])
        XCTAssertEqual(schedule?.days.first(where: { $0.weekday == .sunday })?.ranges, [])
    }

    func testReturnsNilForUnsupportedOrMalformedInput() {
        XCTAssertNil(OSMOpeningHoursParser.parseWeekSchedule("Mo-Fr 9am-5pm"))
        XCTAssertNil(OSMOpeningHoursParser.parseWeekSchedule("PH off"))
        XCTAssertNil(OSMOpeningHoursParser.parseWeekSchedule("Mo-Fr 09:00-17:00 || \"by appointment\""))
    }
}
