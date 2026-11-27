//
//  OnboardingView.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/27/25.
//

import SwiftUI
import CoreLocation
import Foundation // for DebugUtils

struct OnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(ContentViewModel.self) var viewModel
    @Environment(MerchantAlertsManager.self) var merchantAlertsManager
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State var currentPage = 0
    @State var alertCityPickerModel = MerchantAlertCityPickerModel()
    @State var selectedAlertCity: MerchantAlertCityChoice?
    @State var hasManuallySelectedAlertCity = false
    @State var isEnablingAlerts = false
    @State var alertsErrorMessage: String?
    @State private var locationPermissionAdvanceTask: Task<Void, Never>?

    @ScaledMetric(relativeTo: .largeTitle) private var iPadSmallTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var iPadLargeTitleSize: CGFloat = 42
    @ScaledMetric(relativeTo: .title) private var iPadSubtitleSize: CGFloat = 26
    @ScaledMetric(relativeTo: .headline) private var iPhoneLargeButtonSize: CGFloat = 19
    @ScaledMetric(relativeTo: .title2) private var iPadLargeButtonSize: CGFloat = 24

    typealias ScreenCategory = OnboardingScreenCategory

    private func screenSizeCategory(width: CGFloat, height: CGFloat) -> OnboardingScreenCategory {
        OnboardingLayoutResolver.screenCategory(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            width: width,
            height: height
        )
    }

    let pages: [OnboardingPage] = OnboardingStepProgression.defaultPages

    var body: some View {
        GeometryReader { fullGeo in
            let screenCategory = screenSizeCategory(width: fullGeo.size.width, height: fullGeo.size.height)
            let isLandscape = fullGeo.size.width > fullGeo.size.height
            let isCompactHeight = fullGeo.size.height < 720
            
            // Dynamic sizing based on container dimensions
            let circleSize = getCircleSize(for: screenCategory, isLandscape: isLandscape)
            let iconSize = getIconSize(for: screenCategory, isLandscape: isLandscape)
            let titleFont = getTitleFont(for: screenCategory, isLandscape: isLandscape, width: fullGeo.size.width)
            let subtitleFont = getSubtitleFont(for: screenCategory, isLandscape: isLandscape)
            let spacing = getSpacing(for: screenCategory, isLandscape: isLandscape)
            let buttonFont = getButtonFont(for: screenCategory, isLandscape: isLandscape)
            let maxContentWidth = getMaxContentWidth(for: screenCategory, width: fullGeo.size.width)
            let topAnchorFactor = OnboardingLayoutResolver.topAnchorFactor(
                for: screenCategory,
                pageKind: pages[currentPage].kind,
                containerHeight: fullGeo.size.height
            )
            let topSpacerHeight = max(12, fullGeo.size.height * topAnchorFactor - circleSize / 2)

            ZStack {
                // Background layers
                pages[currentPage].bgColor.ignoresSafeArea()
                Color(uiColor: .systemBackground)
                    .opacity(0.95)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: topSpacerHeight)

                            onboardingIcon(circleSize: circleSize, iconSize: iconSize)

                            onboardingTextBlock(
                                titleFont: titleFont,
                                subtitleFont: subtitleFont,
                                spacing: spacing
                            )
                            .padding(.top, isCompactHeight ? min(spacing.afterIcon, 24) : spacing.afterIcon)

                            if pages[currentPage].kind == .alertsSetup {
                                alertSupplementaryContent(
                                    maxContentWidth: maxContentWidth,
                                    screenCategory: screenCategory
                                )
                                .padding(.top, min(28, spacing.afterIcon * 0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)

                    onboardingIndicator(spacing: spacing)
                        .padding(.top, 8)
                        .padding(.bottom, spacing.indicatorBottom)

                    pageControls(
                        spacing: spacing,
                        buttonFont: buttonFont,
                        maxContentWidth: maxContentWidth
                    )
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, screenCategory.usesGenerousMargins ? 32 : 16)
                .frame(width: fullGeo.size.width, height: fullGeo.size.height, alignment: .center)
            }
        }
        .onDisappear {
            locationPermissionAdvanceTask?.cancel()
        }
        .task(id: alertContextRefreshID) {
            guard pages[currentPage].kind == .alertsSetup else { return }
            if let refreshError = await merchantAlertsManager.refreshStatus() {
                alertsErrorMessage = refreshError
            }
            await alertCityPickerModel.syncContext(
                userLocation: viewModel.userLocation,
                authorizationStatus: viewModel.locationManager.authorizationStatus,
                activeSubscription: merchantAlertsManager.currentSubscription
            )
            syncSelectedAlertCityIfNeeded()
        }
    }
    
    // MARK: - Dynamic Sizing Functions
    
    private func getCircleSize(for category: ScreenCategory, isLandscape: Bool) -> CGFloat {
        OnboardingLayoutResolver.circleSize(for: category)
    }

    private func getIconSize(for category: ScreenCategory, isLandscape: Bool) -> CGFloat {
        let circleSize = getCircleSize(for: category, isLandscape: isLandscape)
        return circleSize * 0.56
    }

    private func getTitleFont(for category: ScreenCategory, isLandscape: Bool, width: CGFloat) -> Font {
        switch category {
        case .iPhoneSmall:
            return .title.bold()
        case .iPhoneMedium, .iPhoneLarge:
            return .largeTitle.bold()
        case .iPadSmall:
            return .system(size: iPadSmallTitleSize, weight: .bold)
        case .iPadMedium, .iPadLarge:
            return .system(size: iPadLargeTitleSize, weight: .bold)
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
            return .system(size: iPadSubtitleSize)
        }
    }

    private func getButtonFont(for category: ScreenCategory, isLandscape: Bool) -> Font {
        switch category {
        case .iPhoneSmall, .iPhoneMedium:
            return .headline
        case .iPhoneLarge:
            return .system(size: iPhoneLargeButtonSize, weight: .semibold)
        case .iPadSmall:
            return .title2.weight(.semibold)
        case .iPadMedium, .iPadLarge:
            return .system(size: iPadLargeButtonSize, weight: .semibold)
        }
    }

    private func getMaxContentWidth(for category: ScreenCategory, width: CGFloat) -> CGFloat {
        OnboardingLayoutResolver.maxContentWidth(for: category, containerWidth: width)
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

    func getAlertsSupplementHeight(for category: ScreenCategory) -> CGFloat {
        OnboardingLayoutResolver.alertsSupplementHeight(for: category)
    }
    
    struct SpacingValues {
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

    private func onboardingIcon(circleSize: CGFloat, iconSize: CGFloat) -> some View {
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

            Image(systemName: pages[currentPage].symbolName)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.white)
                .offset(
                    y: pages[currentPage].symbolName == "location.fill" ? 2 : 0
                )
                .offset(
                    x: pages[currentPage].symbolName == "location.fill" ? -4 : 0
                )
                .offset(
                    x: pages[currentPage].symbolName == "bitcoinsign.circle.fill" ? 1 : 0
                )
        }
        .id(currentPage)
        .animation(BitLocalMotion.animation(.easeInOut(duration: 0.5), reduceMotion: reduceMotion), value: currentPage)
    }

    private func onboardingTextBlock(
        titleFont: Font,
        subtitleFont: Font,
        spacing: SpacingValues
    ) -> some View {
        VStack(spacing: spacing.text) {
            Text(LocalizedStringKey(pages[currentPage].titleKey))
                .font(titleFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                .id("title\(currentPage)")
                .animation(BitLocalMotion.animation(.spring(), reduceMotion: reduceMotion), value: currentPage)

            Text(LocalizedStringKey(pages[currentPage].subtitleKey))
                .font(subtitleFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, spacing.textHorizontal)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                .id("subtitle\(currentPage)")
                .animation(BitLocalMotion.animation(.spring(response: 0.6), reduceMotion: reduceMotion), value: currentPage)
        }
    }

    private func onboardingIndicator(spacing: SpacingValues) -> some View {
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
                    .animation(BitLocalMotion.animation(.easeInOut(duration: 0.25), reduceMotion: reduceMotion), value: currentPage)
            }
        }
    }

    @ViewBuilder
    private func pageControls(
        spacing: SpacingValues,
        buttonFont: Font,
        maxContentWidth: CGFloat
    ) -> some View {
        switch pages[currentPage].kind {
        case .locationPermission:
            locationControls(
                spacing: spacing,
                buttonFont: buttonFont,
                maxContentWidth: maxContentWidth
            )
        case .alertsSetup:
            alertsControls(
                spacing: spacing,
                buttonFont: buttonFont,
                maxContentWidth: maxContentWidth
            )
        case .info:
            defaultControls(
                spacing: spacing,
                buttonFont: buttonFont,
                maxContentWidth: maxContentWidth
            )
        }
    }

    private func locationControls(
        spacing: SpacingValues,
        buttonFont: Font,
        maxContentWidth: CGFloat
    ) -> some View {
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
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 14))
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
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, spacing.buttonHorizontal)
        .padding(.bottom, spacing.bottomPadding)
    }

    private func defaultControls(
        spacing: SpacingValues,
        buttonFont: Font,
        maxContentWidth: CGFloat
    ) -> some View {
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
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(
                color: pages[currentPage].bgColor.opacity(0.3),
                radius: 6,
                x: 0,
                y: 3
            )
            .animation(BitLocalMotion.animation(.spring(response: 0.4), reduceMotion: reduceMotion), value: currentPage)
        }
        .padding(.horizontal, spacing.buttonHorizontal)
        .padding(.bottom, spacing.bottomPadding)
    }

    private func requestLocationPermission() {
        Debug.log("OnboardingView: User tapped Enable Location button")

        // Use the ContentViewModel's location manager to ensure consistency
        viewModel.requestWhenInUseLocationPermission()

        // Proceed to next page after a brief delay
        locationPermissionAdvanceTask?.cancel()
        locationPermissionAdvanceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            proceedToNextPage()
        }
    }

    func proceedToNextPage() {
        withAnimation(BitLocalMotion.animation(.spring(response: 0.5, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
            let next = OnboardingStepProgression.nextState(
                currentPage: currentPage,
                pageCount: pages.count
            )
            currentPage = next.nextPage
            if next.didComplete {
                didCompleteOnboarding = true
            }
        }
    }
}
