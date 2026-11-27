import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.alerts))
struct MerchantAlertsModelsTests {
    @Test func cityKeyNormalizesCaseWhitespaceAndDiacritics() {
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

        #expect(lhs == rhs)
    }

    @Test func cityKeyDifferentiatesSameCityAcrossRegions() {
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

        #expect(illinois != missouri)
    }

    @Test func cityKeyCanonicalizesUnitedStatesRegionAbbreviations() {
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

        #expect(abbreviation == fullName)
        #expect(abbreviation == "oceanside|california|united states")
    }

    @Test func displayNameOmitsEmptyRegion() {
        let displayName = MerchantAlertsCityNormalizer.displayName(
            city: "Singapore",
            region: "",
            country: "Singapore"
        )

        #expect(displayName == "Singapore, Singapore")
    }

    @Test func citySubscriptionDecodesLegacyLocationIDFromCityKey() throws {
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
        #expect(decoded.locationID == "astoria|new york|united states")
    }

    @Test func catchUpPolicyAllowsDigestCreatedAfterSubscriptionEvenWhenWindowEndedEarlier() {
        let subscriptionCreatedAt = ISO8601DateFormatter().date(from: "2026-04-26T13:05:00Z")!
        let digestWindowEnd = ISO8601DateFormatter().date(from: "2026-04-26T13:00:00Z")!
        let recordCreationDate = ISO8601DateFormatter().date(from: "2026-04-26T13:17:00Z")!

        #expect(MerchantAlertsCatchUpPolicy.isEligible(
                recordCreationDate: recordCreationDate,
                digestWindowEnd: digestWindowEnd,
                subscriptionCreatedAt: subscriptionCreatedAt
            ))
    }

    @Test func catchUpPolicyRejectsDigestCreatedBeforeSubscription() {
        let subscriptionCreatedAt = ISO8601DateFormatter().date(from: "2026-04-26T14:00:00Z")!
        let digestWindowEnd = ISO8601DateFormatter().date(from: "2026-04-26T13:00:00Z")!
        let recordCreationDate = ISO8601DateFormatter().date(from: "2026-04-26T13:17:00Z")!

        #expect(MerchantAlertsCatchUpPolicy.isEligible(
                recordCreationDate: recordCreationDate,
                digestWindowEnd: digestWindowEnd,
                subscriptionCreatedAt: subscriptionCreatedAt
            ) == false)
    }
}
