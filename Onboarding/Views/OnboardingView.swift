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

enum OnboardingPageKind {
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

struct OnboardingView: View {
    @EnvironmentObject private var viewModel: ContentViewModel
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var currentPage = 0
    @State private var iconScale: CGFloat = 1.0
    @StateObject private var alertCityPickerModel = MerchantAlertCityPickerModel()
    @State private var selectedAlertCity: MerchantAlertCityChoice?
    @State private var hasManuallySelectedAlertCity = false
    @State private var isEnablingAlerts = false

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

                    onboardingIcon(circleSize: circleSize, iconSize: iconSize)

                    onboardingTextBlock(
                        titleFont: titleFont,
                        subtitleFont: subtitleFont,
                        spacing: spacing
                    )
                    .padding(.top, spacing.afterIcon)

                    if pages[currentPage].kind == .alertsSetup {
                        alertSupplementaryContent(
                            maxContentWidth: maxContentWidth,
                            screenCategory: screenCategory
                        )
                        .padding(.top, min(28, spacing.afterIcon * 0.5))
                    }

                    Spacer()

                    onboardingIndicator(spacing: spacing)
                        .padding(.bottom, spacing.indicatorBottom)

                    pageControls(
                        spacing: spacing,
                        buttonFont: buttonFont,
                        maxContentWidth: maxContentWidth
                    )
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, isPad ? 32 : 16)
                .frame(width: fullGeo.size.width, height: fullGeo.size.height, alignment: .center)
            }
        }
        .task(id: alertContextRefreshID) {
            guard pages[currentPage].kind == .alertsSetup else { return }
            await merchantAlertsManager.refreshStatus()
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

    private func getAlertsSupplementHeight(for category: ScreenCategory) -> CGFloat {
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
                .scaleEffect(iconScale)
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
        .animation(.easeInOut(duration: 0.5), value: currentPage)
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
                .transition(.move(edge: .leading).combined(with: .opacity))
                .id("title\(currentPage)")
                .animation(.spring(), value: currentPage)

            Text(LocalizedStringKey(pages[currentPage].subtitleKey))
                .font(subtitleFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, spacing.textHorizontal)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .id("subtitle\(currentPage)")
                .animation(.spring(response: 0.6), value: currentPage)
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
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
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
    }

    private func alertsControls(
        spacing: SpacingValues,
        buttonFont: Font,
        maxContentWidth: CGFloat
    ) -> some View {
        VStack(spacing: 14) {
            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            if merchantAlertsManager.notificationSettings?.authorizationStatus == .denied {
                Button(LocalizedStringKey("Open Settings")) {
                    merchantAlertsManager.openSystemSettings()
                }
                .font(.footnote.weight(.semibold))
            }

            if shouldShowEnableAlertsButton {
                Button {
                    Task {
                        await enableSelectedCityAlerts()
                    }
                } label: {
                    HStack {
                        if isEnablingAlerts {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "bell.badge.fill")
                        }
                        Text(alertPrimaryButtonTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .font(buttonFont)
                    .frame(maxWidth: min(maxContentWidth * 0.9, 500))
                    .padding(.vertical, spacing.buttonPadding)
                    .background(pages[currentPage].bgColor.opacity(selectedAlertCity == nil || isEnablingAlerts ? 0.45 : 1))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(
                        color: pages[currentPage].bgColor.opacity(0.25),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
                }
                .disabled(selectedAlertCity == nil || isEnablingAlerts || !merchantAlertsManager.canEnableAlerts)
            }

            Button {
                proceedToNextPage()
            } label: {
                Text(LocalizedStringKey("Skip for now"))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, spacing.buttonHorizontal)
        .padding(.bottom, spacing.bottomPadding)
    }

    private func alertsSelectionPanel(maxContentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowCloudKitStatusCard {
                alertCloudKitStatusCard
            } else {
                alertSearchBar

                ScrollView(showsIndicators: false) {
                    Group {
                        if alertCityPickerModel.isShowingSearchResults {
                            alertSearchResults
                        } else {
                            alertSuggestedCities
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: min(maxContentWidth * 0.92, 500), maxHeight: .infinity, alignment: .top)
    }

    private var shouldShowCloudKitStatusCard: Bool {
        merchantAlertsManager.cloudKitAccountStatus != .available
    }

    private var shouldShowEnableAlertsButton: Bool {
        merchantAlertsManager.isCloudKitAvailable
    }

    private var alertCloudKitStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: alertCloudKitStatusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(alertCloudKitStatusTint)
                    .frame(width: 40, height: 40)
                    .background(alertCloudKitStatusTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(alertCloudKitStatusTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(merchantAlertsManager.cloudKitStatusSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(LocalizedStringKey("You can finish onboarding now and turn on city alerts later from Settings once iCloud is available."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func alertSupplementaryContent(
        maxContentWidth: CGFloat,
        screenCategory: ScreenCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let alertSelectionSupportText {
                Text(alertSelectionSupportText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            alertsSelectionPanel(maxContentWidth: maxContentWidth)
        }
        .frame(
            maxWidth: min(maxContentWidth * 0.92, 500),
            minHeight: getAlertsSupplementHeight(for: screenCategory),
            maxHeight: getAlertsSupplementHeight(for: screenCategory),
            alignment: .top
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .id("alertSupplement\(currentPage)")
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentPage)
    }

    private var alertCloudKitStatusTitle: String {
        switch merchantAlertsManager.cloudKitAccountStatus {
        case .couldNotDetermine:
            return "Checking iCloud"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .restricted:
            return "iCloud isn't available"
        case .noAccount:
            return "iCloud Required"
        case .available:
            return "iCloud is ready"
        @unknown default:
            return "iCloud is unavailable"
        }
    }

    private var alertCloudKitStatusIcon: String {
        switch merchantAlertsManager.cloudKitAccountStatus {
        case .couldNotDetermine:
            return "icloud"
        case .temporarilyUnavailable:
            return "icloud.slash"
        case .restricted:
            return "icloud.slash"
        case .noAccount:
            return "person.crop.circle.badge.exclamationmark"
        case .available:
            return "icloud"
        @unknown default:
            return "icloud.slash"
        }
    }

    private var alertCloudKitStatusTint: Color {
        switch merchantAlertsManager.cloudKitAccountStatus {
        case .couldNotDetermine:
            return .blue
        case .available:
            return .green
        default:
            return .orange
        }
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

    private var alertSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(LocalizedStringKey("Search city"), text: $alertCityPickerModel.searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !alertCityPickerModel.searchText.isEmpty {
                Button {
                    alertCityPickerModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var alertSuggestedCities: some View {
        if alertCityPickerModel.isLoadingBrowseContent {
            ProgressView(LocalizedStringKey("Finding a city for you…"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 8) {
                if let currentLocationCity = alertCityPickerModel.currentLocationCity {
                    alertCityCard(
                        title: currentLocationCity.choice.city,
                        subtitle: currentLocationCity.displayName,
                        badge: LocalizedStringKey("Current Location"),
                        systemImage: "location.fill",
                        accent: .blue,
                        choice: currentLocationCity.choice
                    )
                }

                if let activeAlertCity = alertCityPickerModel.activeAlertCity {
                    alertCityCard(
                        title: activeAlertCity.city,
                        subtitle: activeAlertCity.displayName,
                        badge: LocalizedStringKey("Current Alert"),
                        systemImage: "bell.badge.fill",
                        accent: .orange,
                        choice: activeAlertCity
                    )
                }

                if alertCityPickerModel.currentLocationCity == nil,
                   alertCityPickerModel.activeAlertCity == nil,
                   alertCityPickerModel.recommendedCities.isEmpty {
                    if let alertEmptyBrowseText {
                        Text(alertEmptyBrowseText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 18)
                    }
                } else {
                    ForEach(alertCityPickerModel.recommendedCities.prefix(2)) { result in
                        alertCityCard(
                            title: result.city,
                            subtitle: result.displayName,
                            badge: nil,
                            systemImage: "mappin.circle.fill",
                            accent: .accentColor,
                            choice: result.choice
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var alertSearchResults: some View {
        if alertCityPickerModel.isLoading && alertCityPickerModel.results.isEmpty {
            ProgressView(LocalizedStringKey("Searching cities…"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if alertCityPickerModel.results.isEmpty {
            Text(LocalizedStringKey("No city matches yet. Try a city name, state, or country."))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 18)
        } else {
            VStack(spacing: 8) {
                ForEach(alertCityPickerModel.results.prefix(3)) { result in
                    alertCityCard(
                        title: result.city,
                        subtitle: result.displayName,
                        badge: nil,
                        systemImage: "mappin.circle.fill",
                        accent: .accentColor,
                        choice: result.choice
                    )
                }
            }
        }
    }

    private func alertCityCard(
        title: String,
        subtitle: String,
        badge: LocalizedStringKey?,
        systemImage: String,
        accent: Color,
        choice: MerchantAlertCityChoice
    ) -> some View {
        let isSelected = selectedAlertCity?.locationID == choice.locationID

        return Button {
            selectedAlertCity = choice
            hasManuallySelectedAlertCity = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accent.opacity(0.12), in: Capsule())
                                .lineLimit(1)
                        }
                    }

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(pages[currentPage].bgColor) : AnyShapeStyle(.tertiary))
                    .font(.title3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var alertContextRefreshID: String {
        let locationKey = viewModel.userLocation.map {
            ReverseGeocodingSpatialKey.key(for: $0.coordinate, precision: 3)
        } ?? "no-location"
        let subscriptionKey = merchantAlertsManager.currentSubscription?.locationID ?? "no-subscription"
        return "\(currentPage)|\(viewModel.locationManager.authorizationStatus.rawValue)|\(locationKey)|\(subscriptionKey)"
    }

    private var alertPrimaryButtonTitle: String {
        if selectedAlertCity != nil, alertCityPickerModel.currentLocationCity != nil {
            return NSLocalizedString("Turn On Alerts", comment: "Primary onboarding button title for enabling merchant alerts")
        }
        if let selectedAlertCity {
            return String(
                format: NSLocalizedString("Turn On Alerts for %@", comment: "Primary onboarding button title for enabling merchant alerts for the selected city"),
                selectedAlertCity.city
            )
        }
        return NSLocalizedString("Choose a City First", comment: "Disabled onboarding alert button title shown before the user selects a city")
    }

    private var isLocationAuthorizedForAlerts: Bool {
        let status = viewModel.locationManager.authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    private var alertSelectionSupportText: String? {
        if alertCityPickerModel.currentLocationCity != nil, isLocationAuthorizedForAlerts {
            return nil
        }

        if isLocationAuthorizedForAlerts {
            return NSLocalizedString("Search any city, or use the suggestion when it appears.", comment: "Helper text shown in onboarding when alert city suggestions may appear")
        }

        return NSLocalizedString("Search for a city to turn on alerts.", comment: "Helper text shown in onboarding when the user must search to choose an alert city")
    }

    private var alertEmptyBrowseText: String? {
        if isLocationAuthorizedForAlerts {
            return NSLocalizedString("We’ll suggest your current city when it’s ready, or you can search for any city.", comment: "Empty state text shown while the current city suggestion is not yet available during onboarding")
        }

        return nil
    }

    private func syncSelectedAlertCityIfNeeded() {
        guard !hasManuallySelectedAlertCity else { return }
        selectedAlertCity = alertCityPickerModel.currentLocationCity?.choice
            ?? alertCityPickerModel.activeAlertCity
            ?? alertCityPickerModel.recommendedCities.first?.choice
    }

    private func requestLocationPermission() {
        Debug.log("OnboardingView: User tapped Enable Location button")
        
        // Use the ContentViewModel's location manager to ensure consistency
        viewModel.requestWhenInUseLocationPermission()
        
        // Proceed to next page after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proceedToNextPage()
        }
    }

    private func enableSelectedCityAlerts() async {
        guard let selectedAlertCity else { return }
        guard !isEnablingAlerts else { return }

        isEnablingAlerts = true
        defer { isEnablingAlerts = false }

        await merchantAlertsManager.enableNotifications(for: selectedAlertCity)

        if merchantAlertsManager.currentSubscription?.locationID == selectedAlertCity.locationID {
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
