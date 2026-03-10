import XCTest
@testable import bitlocal

final class MerchantAlertsModelsTests: XCTestCase {
    func testCityKeyNormalizesCaseWhitespaceAndDiacritics() {
        let lhs = MerchantAlertsCityNormalizer.cityKey(
            city: "  São Paulo ",
            region: " SP ",
            country: " Brazil "
        )
        let rhs = MerchantAlertsCityNormalizer.cityKey(
            city: "sao paulo",
            region: "sp",
            country: "brazil"
        )

        XCTAssertEqual(lhs, rhs)
    }

    func testCityKeyDifferentiatesSameCityAcrossRegions() {
        let illinois = MerchantAlertsCityNormalizer.cityKey(
            city: "Springfield",
            region: "Illinois",
            country: "United States"
        )
        let missouri = MerchantAlertsCityNormalizer.cityKey(
            city: "Springfield",
            region: "Missouri",
            country: "United States"
        )

        XCTAssertNotEqual(illinois, missouri)
    }

    func testCityKeyCanonicalizesUnitedStatesRegionAbbreviations() {
        let abbreviation = MerchantAlertsCityNormalizer.cityKey(
            city: "Oceanside",
            region: "CA",
            country: "United States"
        )
        let fullName = MerchantAlertsCityNormalizer.cityKey(
            city: "Oceanside",
            region: "California",
            country: "United States"
        )

        XCTAssertEqual(abbreviation, fullName)
        XCTAssertEqual(abbreviation, "oceanside|california|united states")
    }

    func testDisplayNameOmitsEmptyRegion() {
        let displayName = MerchantAlertsCityNormalizer.displayName(
            city: "Singapore",
            region: "",
            country: "Singapore"
        )

        XCTAssertEqual(displayName, "Singapore, Singapore")
    }
}
