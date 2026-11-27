import CoreGraphics
import SwiftUI
import Testing
@testable import bitlocal

@Suite(.tags(.layout))
struct OnboardingFlowTests {

    @Test("Adaptive screen category maps iPhone, iPhone Duo, and iPad poses accurately")
    func screenCategoryCoversAllDevicePoses() {
        // Compact phone / iPhone Duo outer display
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular,
                width: 375,
                height: 667
            ) == .iPhoneSmall
        )

        // Standard phone
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular,
                width: 390,
                height: 780
            ) == .iPhoneMedium
        )

        // Tall iPhone (e.g. iPhone 17)
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular,
                width: 393,
                height: 852
            ) == .iPhoneLarge
        )

        // iPhone Duo unfolded landscape: regular×regular but height < 760
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                width: 951,
                height: 669
            ) == .iPhoneMedium
        )

        // iPhone Duo unfolded portrait: regular×regular, height >= 760, minDimension < 740
        let duoPortrait = OnboardingLayoutResolver.screenCategory(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            width: 669,
            height: 951
        )
        #expect(duoPortrait == .iPadSmall)
        #expect(duoPortrait.usesGenerousMargins)

        // 11" iPad
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                width: 834,
                height: 1194
            ) == .iPadMedium
        )

        // 13" iPad
        #expect(
            OnboardingLayoutResolver.screenCategory(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                width: 1032,
                height: 1376
            ) == .iPadLarge
        )
    }

    @Test("Compact height tightens top anchor especially on the alerts setup step")
    func topAnchorFactorAdaptsToCompactHeightAndPageKind() {
        #expect(
            OnboardingLayoutResolver.topAnchorFactor(
                for: .iPhoneSmall,
                pageKind: .alertsSetup,
                containerHeight: 667
            ) == 0.08
        )
        #expect(
            OnboardingLayoutResolver.topAnchorFactor(
                for: .iPhoneSmall,
                pageKind: .info,
                containerHeight: 667
            ) == 0.16
        )
        #expect(
            OnboardingLayoutResolver.topAnchorFactor(
                for: .iPhoneLarge,
                pageKind: .info,
                containerHeight: 852
            ) == 0.25
        )
        #expect(
            OnboardingLayoutResolver.topAnchorFactor(
                for: .iPadMedium,
                pageKind: .info,
                containerHeight: 1194
            ) == 0.30
        )
    }

    @Test("Onboarding default pages and step progression complete cleanly on the final page")
    func stepProgressionAndDefaultPages() {
        let pages = OnboardingStepProgression.defaultPages
        #expect(pages.count == 5)
        #expect(pages[2].kind == .locationPermission)
        #expect(pages[3].kind == .alertsSetup)
        #expect(pages[4].kind == .info)

        var current = 0
        var completed = false
        for expectedNext in 1..<pages.count {
            let result = OnboardingStepProgression.nextState(currentPage: current, pageCount: pages.count)
            #expect(result.nextPage == expectedNext)
            #expect(!result.didComplete)
            current = result.nextPage
            completed = result.didComplete
        }
        #expect(!completed)

        let finalResult = OnboardingStepProgression.nextState(currentPage: current, pageCount: pages.count)
        #expect(finalResult.nextPage == pages.count - 1)
        #expect(finalResult.didComplete)
    }

    @Test("Alert city preselection respects manual choice and priority fallbacks")
    func preferredAlertCityPriorityOrder() {
        let manual = MerchantAlertCityChoice(locationID: "manual", city: "Austin", region: "Texas", country: "United States")
        let gps = MerchantAlertCityChoice(locationID: "gps", city: "Nashville", region: "Tennessee", country: "United States")
        let active = MerchantAlertCityChoice(locationID: "active", city: "Miami", region: "Florida", country: "United States")
        let recommended = MerchantAlertCityChoice(locationID: "rec", city: "Lugano", region: "Ticino", country: "Switzerland")

        // Manual choice is never overwritten by GPS/active updates.
        #expect(
            OnboardingStepProgression.preferredAlertCity(
                hasManuallySelected: true,
                currentSelected: manual,
                currentLocationCity: gps,
                activeAlertCity: active,
                firstRecommendedCity: recommended
            ) == manual
        )

        // Automatic fallback order: GPS > active subscription > first recommended.
        #expect(
            OnboardingStepProgression.preferredAlertCity(
                hasManuallySelected: false,
                currentSelected: nil,
                currentLocationCity: gps,
                activeAlertCity: active,
                firstRecommendedCity: recommended
            ) == gps
        )
        #expect(
            OnboardingStepProgression.preferredAlertCity(
                hasManuallySelected: false,
                currentSelected: nil,
                currentLocationCity: nil,
                activeAlertCity: active,
                firstRecommendedCity: recommended
            ) == active
        )
        #expect(
            OnboardingStepProgression.preferredAlertCity(
                hasManuallySelected: false,
                currentSelected: nil,
                currentLocationCity: nil,
                activeAlertCity: nil,
                firstRecommendedCity: recommended
            ) == recommended
        )
    }
}
