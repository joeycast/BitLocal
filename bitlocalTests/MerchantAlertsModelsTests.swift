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

    func testCitySubscriptionDecodesLegacyLocationIDFromCityKey() throws {
        let payload = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "cityKey": "astoria|new york|united states",
          "city": "Astoria",
          "region": "New York",
          "country": "United States",
          "displayName": "Astoria, New York, United States",
          "isEnabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CitySubscription.self, from: payload)
        XCTAssertEqual(decoded.locationID, "astoria|new york|united states")
    }

    func testCatchUpPolicyAllowsDigestCreatedAfterSubscriptionEvenWhenWindowEndedEarlier() {
        let subscriptionCreatedAt = ISO8601DateFormatter().date(from: "2026-04-26T13:05:00Z")!
        let digestWindowEnd = ISO8601DateFormatter().date(from: "2026-04-26T13:00:00Z")!
        let recordCreationDate = ISO8601DateFormatter().date(from: "2026-04-26T13:17:00Z")!

        XCTAssertTrue(
            MerchantAlertsCatchUpPolicy.isEligible(
                recordCreationDate: recordCreationDate,
                digestWindowEnd: digestWindowEnd,
                subscriptionCreatedAt: subscriptionCreatedAt
            )
        )
    }

    func testCatchUpPolicyRejectsDigestCreatedBeforeSubscription() {
        let subscriptionCreatedAt = ISO8601DateFormatter().date(from: "2026-04-26T14:00:00Z")!
        let digestWindowEnd = ISO8601DateFormatter().date(from: "2026-04-26T13:00:00Z")!
        let recordCreationDate = ISO8601DateFormatter().date(from: "2026-04-26T13:17:00Z")!

        XCTAssertFalse(
            MerchantAlertsCatchUpPolicy.isEligible(
                recordCreationDate: recordCreationDate,
                digestWindowEnd: digestWindowEnd,
                subscriptionCreatedAt: subscriptionCreatedAt
            )
        )
    }
}
