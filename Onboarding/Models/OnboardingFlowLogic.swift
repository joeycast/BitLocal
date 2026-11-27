import CoreGraphics
import SwiftUI

enum OnboardingPageKind: Equatable, Sendable {
    case info
    case locationPermission
    case alertsSetup
}

struct OnboardingPage {
    let titleKey: String
    let subtitleKey: String
    let symbolName: String
    let bgColor: Color
    let kind: OnboardingPageKind
}

enum OnboardingScreenCategory: Equatable, Sendable {
    case iPhoneSmall
    case iPhoneMedium
    case iPhoneLarge
    case iPadSmall
    case iPadMedium
    case iPadLarge

    var usesGenerousMargins: Bool {
        switch self {
        case .iPadSmall, .iPadMedium, .iPadLarge:
            return true
        case .iPhoneSmall, .iPhoneMedium, .iPhoneLarge:
            return false
        }
    }
}

/// Pure, unit-testable adaptive layout math for `OnboardingView` across iPhone,
/// iPhone Duo outer/unfolded poses, Split View, and iPad canvases.
enum OnboardingLayoutResolver {
    static func screenCategory(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        width: CGFloat,
        height: CGFloat
    ) -> OnboardingScreenCategory {
        let isRegularCanvas = horizontalSizeClass == .regular && verticalSizeClass == .regular
        let minDimension = min(width, height)

        if isRegularCanvas && height >= 760 {
            if minDimension >= 1000 { // Large tablet canvas (e.g. 13" iPad)
                return .iPadLarge
            } else if minDimension >= 740 { // Medium tablet canvas (e.g. 11" / mini iPad)
                return .iPadMedium
            } else { // Compact-regular canvas (e.g. iPhone Duo unfolded portrait)
                return .iPadSmall
            }
        } else if isRegularCanvas {
            // Wide but shorter regular canvas (e.g. iPhone Duo unfolded landscape ~951×669)
            return .iPhoneMedium
        } else {
            if width <= 375 || height <= 680 { // Compact phone or iPhone Duo outer display
                return .iPhoneSmall
            } else if height >= 850 { // Tall phone
                return .iPhoneLarge
            } else {
                return .iPhoneMedium
            }
        }
    }

    static func circleSize(for category: OnboardingScreenCategory) -> CGFloat {
        switch category {
        case .iPhoneSmall:
            return 110
        case .iPhoneMedium:
            return 120
        case .iPhoneLarge:
            return 130
        case .iPadSmall:
            return 160
        case .iPadMedium, .iPadLarge:
            return 180
        }
    }

    static func maxContentWidth(for category: OnboardingScreenCategory, containerWidth: CGFloat) -> CGFloat {
        switch category {
        case .iPhoneSmall, .iPhoneMedium:
            return 460
        case .iPhoneLarge:
            return 500
        case .iPadSmall:
            return min(600, containerWidth * 0.8)
        case .iPadMedium:
            return min(700, containerWidth * 0.75)
        case .iPadLarge:
            return min(800, containerWidth * 0.7)
        }
    }

    static func alertsSupplementHeight(for category: OnboardingScreenCategory) -> CGFloat {
        switch category {
        case .iPhoneSmall:
            return 176
        case .iPhoneMedium:
            return 194
        case .iPhoneLarge:
            return 212
        case .iPadSmall:
            return 248
        case .iPadMedium, .iPadLarge:
            return 272
        }
    }

    static func topAnchorFactor(
        for category: OnboardingScreenCategory,
        pageKind: OnboardingPageKind,
        containerHeight: CGFloat
    ) -> CGFloat {
        if containerHeight < 720 {
            return pageKind == .alertsSetup ? 0.08 : 0.16
        }
        return category.usesGenerousMargins ? 0.30 : 0.25
    }
}

/// Pure step-progression and alert-city preselection logic for `OnboardingView`.
enum OnboardingStepProgression {
    static let defaultPages: [OnboardingPage] = [
        OnboardingPage(
            titleKey: "onboarding_discover_title",
            subtitleKey: "onboarding_discover_subtitle",
            symbolName: "bitcoinsign.circle.fill",
            bgColor: .accentColor,
            kind: .info
        ),
        OnboardingPage(
            titleKey: "onboarding_map_title",
            subtitleKey: "onboarding_map_subtitle",
            symbolName: "map.fill",
            bgColor: .green,
            kind: .info
        ),
        OnboardingPage(
            titleKey: "onboarding_location_title",
            subtitleKey: "onboarding_location_subtitle",
            symbolName: "location.fill",
            bgColor: .blue,
            kind: .locationPermission
        ),
        OnboardingPage(
            titleKey: "Stay in the loop",
            subtitleKey: "Get alerts when new local businesses start accepting bitcoin.",
            symbolName: "bell.badge.fill",
            bgColor: .orange,
            kind: .alertsSetup
        ),
        OnboardingPage(
            titleKey: "onboarding_ready_title",
            subtitleKey: "onboarding_ready_subtitle",
            symbolName: "binoculars.fill",
            bgColor: .purple,
            kind: .info
        )
    ]

    static func nextState(currentPage: Int, pageCount: Int) -> (nextPage: Int, didComplete: Bool) {
        guard pageCount > 0 else { return (0, true) }
        let clamped = max(0, min(currentPage, pageCount - 1))
        if clamped < pageCount - 1 {
            return (clamped + 1, false)
        }
        return (clamped, true)
    }

    static func preferredAlertCity(
        hasManuallySelected: Bool,
        currentSelected: MerchantAlertCityChoice?,
        currentLocationCity: MerchantAlertCityChoice?,
        activeAlertCity: MerchantAlertCityChoice?,
        firstRecommendedCity: MerchantAlertCityChoice?
    ) -> MerchantAlertCityChoice? {
        if hasManuallySelected {
            return currentSelected
        }
        return currentLocationCity ?? activeAlertCity ?? firstRecommendedCity
    }
}
