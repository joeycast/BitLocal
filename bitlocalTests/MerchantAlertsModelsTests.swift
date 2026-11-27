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

    @Test(arguments: [
        (1, "1 new merchant"),
        (298, "298 new merchants"),
    ])
    func cityDigestSummaryLineEvaluatesGrammarInflectionWithoutRawSyntax(
        count: Int,
        expected: String
    ) {
        let digest = CityDigest(
            id: "digest-\(count)",
            locationID: "el zonte|la libertad|el salvador",
            cityKey: "el zonte|la libertad|el salvador",
            cityDisplayName: "El Zonte, El Salvador",
            digestWindowStart: nil,
            digestWindowEnd: nil,
            merchantCount: count,
            merchantIDs: [],
            topMerchantNames: [],
            timeZoneID: nil,
            deliveryLocalDate: nil
        )

        #expect(digest.summaryLine == expected)
        #expect(!digest.summaryLine.contains("^["))
        #expect(!digest.summaryLine.contains("inflect:"))
    }

    @Test func pendingDigestRequestRespectsTargetedAndActiveSceneRules() {
        let sceneA = UUID()
        let sceneB = UUID()
        let digest = CityDigest(
            id: "digest-scene-test",
            locationID: "austin|texas|united states",
            cityKey: "austin|texas|united states",
            cityDisplayName: "Austin, Texas, United States",
            digestWindowStart: nil,
            digestWindowEnd: nil,
            merchantCount: 2,
            merchantIDs: ["1", "2"],
            topMerchantNames: ["Cafe Satoshi", "Lightning Books"],
            timeZoneID: "America/Chicago",
            deliveryLocalDate: "2026-11-27"
        )

        // Targeted request (e.g. from Settings in sceneA) only matches sceneA.
        let targeted = PendingMerchantDigestRequest(digest: digest, targetSceneID: sceneA)
        #expect(targeted.canBeClaimed(bySceneID: sceneA, isSceneActive: true))
        #expect(targeted.canBeClaimed(bySceneID: sceneA, isSceneActive: false))
        #expect(!targeted.canBeClaimed(bySceneID: sceneB, isSceneActive: true))

        // Untargeted request (e.g. push notification) only matches an active foreground scene.
        let untargeted = PendingMerchantDigestRequest(digest: digest, targetSceneID: nil)
        #expect(!untargeted.canBeClaimed(bySceneID: sceneA, isSceneActive: false))
        #expect(untargeted.canBeClaimed(bySceneID: sceneB, isSceneActive: true))
    }
}
