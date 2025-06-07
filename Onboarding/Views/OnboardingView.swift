//
//  OnboardingView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import CoreLocation
import Foundation // for DebugUtils
import UIKit     // ← added, for checking userInterfaceIdiom

struct OnboardingPage {
    let titleKey: String
    let subtitleKey: String
    let image: String
    let bgColor: Color
    let isLocationPage: Bool
}

struct OnboardingView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var currentPage = 0
    @State private var locationManager = CLLocationManager()
    @State private var locationDelegate = LocationPermissionDelegate()
    @State private var iconScale: CGFloat = 1.0

    // ──────────────── Device Detection Helpers ────────────────
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // Screen size categories based on actual dimensions
    private func screenSizeCategory(width: CGFloat, height: CGFloat) -> ScreenCategory {
        let minDimension = min(width, height)
        let maxDimension = max(width, height)
        
        if isPad {
            if minDimension >= 1000 { // iPad 13" and larger
                return .iPadLarge
            } else if minDimension >= 800 { // iPad 11"
                return .iPadMedium
            } else { // iPad mini
                return .iPadSmall
            }
        } else {
            if minDimension <= 375 { // iPhone SE and smaller
                return .iPhoneSmall
            } else if maxDimension >= 850 { // iPhone Pro Max
                return .iPhoneLarge
            } else { // Regular iPhones
                return .iPhoneMedium
            }
        }
    }
    
    enum ScreenCategory {
        case iPhoneSmall
        case iPhoneMedium
        case iPhoneLarge
        case iPadSmall
        case iPadMedium
        case iPadLarge
    }
    // ──────────────── End Device Detection ──────────────────

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            titleKey: "onboarding_discover_title",
            subtitleKey: "onboarding_discover_subtitle",
            image: "currency-btc-bold",
            bgColor: .accentColor,
            isLocationPage: false
        ),
        OnboardingPage(
            titleKey: "onboarding_map_title",
            subtitleKey: "onboarding_map_subtitle",
            image: "map-trifold-fill",
            bgColor: .green,
            isLocationPage: false
        ),
        OnboardingPage(
            titleKey: "onboarding_location_title",
            subtitleKey: "onboarding_location_subtitle",
            image: "navigation-arrow-fill",
            bgColor: .blue,
            isLocationPage: true
        ),
        OnboardingPage(
            titleKey: "onboarding_ready_title",
            subtitleKey: "onboarding_ready_subtitle",
            image: "binoculars-fill",
            bgColor: .purple,
            isLocationPage: false
        )
    ]

    var body: some View {
        GeometryReader { fullGeo in
            let screenCategory = screenSizeCategory(width: fullGeo.size.width, height: fullGeo.size.height)
            let isLandscape = fullGeo.size.width > fullGeo.size.height
            
            // Dynamic sizing based on screen dimensions
            let circleSize = getCircleSize(for: screenCategory, isLandscape: isLandscape)
            let iconSize = getIconSize(for: screenCategory, isLandscape: isLandscape)
            let titleFont = getTitleFont(for: screenCategory, isLandscape: isLandscape, width: fullGeo.size.width)
            let subtitleFont = getSubtitleFont(for: screenCategory, isLandscape: isLandscape)
            let spacing = getSpacing(for: screenCategory, isLandscape: isLandscape)
            let buttonFont = getButtonFont(for: screenCategory, isLandscape: isLandscape)
            let maxContentWidth = getMaxContentWidth(for: screenCategory, width: fullGeo.size.width)

            ZStack {
                // Background layers
                pages[currentPage].bgColor.ignoresSafeArea()
                Color(UIColor.systemBackground)
                    .opacity(0.95)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Position icon at 1/4 from top for iPhones, 1/3 for iPads
                    Spacer()
                        .frame(height: fullGeo.size.height * (isPad ? 0.33 : 0.25) - circleSize / 2)
                    
                    // Icon
                    ZStack {
                        Circle()
                            .fill(pages[currentPage].bgColor)
                            .frame(width: circleSize, height: circleSize)
                            .shadow(
                                color: pages[currentPage].bgColor.opacity(0.3),
                                radius: circleSize * 0.133,
                                x: 0,
                                y: circleSize * 0.067
                            )

                        Image(pages[currentPage].image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                            .foregroundColor(.white)
                            .scaleEffect(iconScale)
                            .offset(
                                y: pages[currentPage].image == "navigation-arrow-fill" ? 2 : 0
                            )
                            .offset(
                                x: pages[currentPage].image == "navigation-arrow-fill" ? -4 : 0
                            )
                            .offset(
                                x: pages[currentPage].image == "currency-btc-bold" ? 1 : 0
                            )
                    }
                    .id(currentPage)
                    .animation(.easeInOut(duration: 0.5), value: currentPage)

                    // Title & subtitle
                    VStack(spacing: spacing.text) {
                        Text(LocalizedStringKey(pages[currentPage].titleKey))
                            .font(titleFont)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .id("title\(currentPage)")
                            .animation(.spring(), value: currentPage)

                        Text(LocalizedStringKey(pages[currentPage].subtitleKey))
                            .font(subtitleFont)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, spacing.textHorizontal)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .id("subtitle\(currentPage)")
                            .animation(.spring(response: 0.6), value: currentPage)
                    }
                    .padding(.top, spacing.afterIcon)

                    Spacer()

                    // Indicator
                    HStack(spacing: spacing.indicator) {
                        ForEach(pages.indices, id: \.self) { i in
                            Capsule()
                                .fill(
                                    i == currentPage
                                        ? pages[currentPage].bgColor
                                        : Color.gray.opacity(0.3)
                                )
                                .frame(
                                    width: i == currentPage ? spacing.indicatorWidthActive : spacing.indicatorWidth,
                                    height: spacing.indicatorHeight
                                )
                                .animation(.easeInOut(duration: 0.25), value: currentPage)
                        }
                    }
                    .padding(.bottom, spacing.indicatorBottom)

                    // Page-specific controls
                    if pages[currentPage].isLocationPage {
                        // Location permission UI
                        VStack(spacing: spacing.button) {
                            Button {
                                requestLocationPermission()
                            } label: {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("onboarding_button_enable_location")
                                }
                                .font(buttonFont)
                                .frame(maxWidth: min(maxContentWidth * 0.9, 500))
                                .padding(.vertical, spacing.buttonPadding)
                                .background(pages[currentPage].bgColor)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .shadow(
                                    color: pages[currentPage].bgColor.opacity(0.3),
                                    radius: 6,
                                    x: 0,
                                    y: 3
                                )
                            }

                            Button {
                                proceedToNextPage()
                            } label: {
                                Text("onboarding_button_location_skip")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, spacing.buttonHorizontal)
                        .padding(.bottom, spacing.bottomPadding)

                    } else {
                        // Next / Get Started button
                        Button {
                            proceedToNextPage()
                        } label: {
                            Text(
                                currentPage == pages.count - 1
                                    ? "onboarding_button_get_started"
                                    : "onboarding_button_next"
                            )
                            .font(buttonFont)
                            .frame(maxWidth: min(maxContentWidth * 0.9, 500))
                            .padding(.vertical, spacing.buttonPadding)
                            .background(pages[currentPage].bgColor)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(
                                color: pages[currentPage].bgColor.opacity(0.3),
                                radius: 6,
                                x: 0,
                                y: 3
                            )
                            .animation(.spring(response: 0.4), value: currentPage)
                        }
                        .padding(.horizontal, spacing.buttonHorizontal)
                        .padding(.bottom, spacing.bottomPadding)
                    }
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, isPad ? 32 : 16)
                .frame(width: fullGeo.size.width, height: fullGeo.size.height, alignment: .center)
            }
        }
    }
    
    // MARK: - Dynamic Sizing Functions
    
    private func getCircleSize(for category: ScreenCategory, isLandscape: Bool) -> CGFloat {
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
    
    private func getIconSize(for category: ScreenCategory, isLandscape: Bool) -> CGFloat {
        let circleSize = getCircleSize(for: category, isLandscape: isLandscape)
        return circleSize * 0.56
    }
    
    private func getTitleFont(for category: ScreenCategory, isLandscape: Bool, width: CGFloat) -> Font {
        switch category {
        case .iPhoneSmall:
            return .system(size: 28, weight: .bold)
        case .iPhoneMedium:
            return .largeTitle.bold()
        case .iPhoneLarge:
            return .system(size: 34, weight: .bold)
        case .iPadSmall:
            return .system(size: 36, weight: .bold)
        case .iPadMedium, .iPadLarge:
            return .system(size: 42, weight: .bold)
        }
    }
    
    private func getSubtitleFont(for category: ScreenCategory, isLandscape: Bool) -> Font {
        switch category {
        case .iPhoneSmall:
            return .body
        case .iPhoneMedium:
            return .title3
        case .iPhoneLarge:
            return .title2
        case .iPadSmall:
            return .title
        case .iPadMedium, .iPadLarge:
            return .system(size: 26)
        }
    }
    
    private func getButtonFont(for category: ScreenCategory, isLandscape: Bool) -> Font {
        switch category {
        case .iPhoneSmall:
            return .system(size: 17, weight: .semibold)
        case .iPhoneMedium:
            return .headline
        case .iPhoneLarge:
            return .system(size: 19, weight: .semibold)
        case .iPadSmall:
            return .system(size: 22, weight: .semibold)
        case .iPadMedium, .iPadLarge:
            return .system(size: 24, weight: .semibold)
        }
    }
    
    private func getMaxContentWidth(for category: ScreenCategory, width: CGFloat) -> CGFloat {
        switch category {
        case .iPhoneSmall, .iPhoneMedium:
            return 460
        case .iPhoneLarge:
            return 500
        case .iPadSmall:
            return min(600, width * 0.8)
        case .iPadMedium:
            return min(700, width * 0.75)
        case .iPadLarge:
            return min(800, width * 0.7)
        }
    }
    
    private func getSpacing(for category: ScreenCategory, isLandscape: Bool) -> SpacingValues {
        switch category {
        case .iPhoneSmall:
            return SpacingValues(
                main: 20,
                text: 10,
                textHorizontal: 8,
                afterIcon: 30,
                button: 14,
                buttonPadding: 14,
                buttonHorizontal: 6,
                bottomPadding: 16,
                indicator: 8,
                indicatorWidth: 12,
                indicatorWidthActive: 28,
                indicatorHeight: 8,
                indicatorBottom: 10
            )
        case .iPhoneMedium:
            return SpacingValues(
                main: 28,
                text: 12,
                textHorizontal: 8,
                afterIcon: 40,
                button: 16,
                buttonPadding: 16,
                buttonHorizontal: 6,
                bottomPadding: 26,
                indicator: 8,
                indicatorWidth: 12,
                indicatorWidthActive: 32,
                indicatorHeight: 8,
                indicatorBottom: 12
            )
        case .iPhoneLarge:
            return SpacingValues(
                main: 32,
                text: 14,
                textHorizontal: 10,
                afterIcon: 50,
                button: 18,
                buttonPadding: 18,
                buttonHorizontal: 8,
                bottomPadding: 30,
                indicator: 10,
                indicatorWidth: 14,
                indicatorWidthActive: 36,
                indicatorHeight: 10,
                indicatorBottom: 14
            )
        case .iPadSmall:
            return SpacingValues(
                main: 36,
                text: 16,
                textHorizontal: 22,
                afterIcon: 40,
                button: 20,
                buttonPadding: 20,
                buttonHorizontal: 16,
                bottomPadding: 30,
                indicator: 12,
                indicatorWidth: 16,
                indicatorWidthActive: 40,
                indicatorHeight: 12,
                indicatorBottom: 20
            )
        case .iPadMedium, .iPadLarge:
            return SpacingValues(
                main: 40,
                text: 18,
                textHorizontal: 24,
                afterIcon: 50,
                button: 24,
                buttonPadding: 22,
                buttonHorizontal: 16,
                bottomPadding: 34,
                indicator: 14,
                indicatorWidth: 18,
                indicatorWidthActive: 44,
                indicatorHeight: 14,
                indicatorBottom: 22
            )
        }
    }
    
    private struct SpacingValues {
        let main: CGFloat
        let text: CGFloat
        let textHorizontal: CGFloat
        let afterIcon: CGFloat
        let button: CGFloat
        let buttonPadding: CGFloat
        let buttonHorizontal: CGFloat
        let bottomPadding: CGFloat
        let indicator: CGFloat
        let indicatorWidth: CGFloat
        let indicatorWidthActive: CGFloat
        let indicatorHeight: CGFloat
        let indicatorBottom: CGFloat
    }

    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        viewModel.locationManager.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proceedToNextPage()
        }
    }

    private func proceedToNextPage() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            if currentPage < pages.count - 1 {
                currentPage += 1
            } else {
                didCompleteOnboarding = true
            }
        }
    }
}

// Delegate for location permission changes
class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        Debug.log("Location authorization status changed: \(status)")
    }
}
