import SwiftUI
import CoreLocation

extension OnboardingView {
    func alertsControls(
        spacing: SpacingValues,
        buttonFont: Font,
        maxContentWidth: CGFloat
    ) -> some View {
        VStack(spacing: 14) {
            if let errorMessage = alertsErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 14))
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
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .padding(.horizontal, spacing.buttonHorizontal)
        .padding(.bottom, spacing.bottomPadding)
    }

    func alertsSelectionPanel(maxContentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowCloudKitStatusCard {
                alertCloudKitStatusCard
            } else {
                alertSearchBar

                ScrollView {
                    Group {
                        if alertCityPickerModel.isShowingSearchResults {
                            alertSearchResults
                        } else {
                            alertSuggestedCities
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
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

    func alertSupplementaryContent(
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
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .id("alertSupplement\(currentPage)")
        .animation(BitLocalMotion.animation(.spring(response: 0.45, dampingFraction: 0.82), reduceMotion: reduceMotion), value: currentPage)
    }

    private var alertCloudKitStatusTitle: String {
        switch merchantAlertsManager.cloudKitAccountStatus {
        case .couldNotDetermine:
            return String(localized: "Checking iCloud", comment: "Onboarding iCloud status title while checking availability")
        case .temporarilyUnavailable:
            return String(localized: "iCloud is temporarily unavailable", comment: "Onboarding iCloud status title when temporarily unavailable")
        case .restricted:
            return String(localized: "iCloud isn't available", comment: "Onboarding iCloud status title when restricted")
        case .noAccount:
            return String(localized: "iCloud Required", comment: "Onboarding iCloud status title when signed out")
        case .available:
            return String(localized: "iCloud is ready", comment: "Onboarding iCloud status title when available")
        @unknown default:
            return String(localized: "iCloud is unavailable", comment: "Onboarding iCloud status fallback title")
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
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    alertCityPickerModel.searchText = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, 12)
        .padding(.trailing, alertCityPickerModel.searchText.isEmpty ? 12 : 4)
        .padding(.vertical, 2)
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
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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

    var alertContextRefreshID: String {
        let locationKey = viewModel.userLocation.map {
            ReverseGeocodingSpatialKey.key(for: $0.coordinate, precision: 3)
        } ?? "no-location"
        let subscriptionKey = merchantAlertsManager.currentSubscription?.locationID ?? "no-subscription"
        return "\(currentPage)|\(viewModel.locationManager.authorizationStatus.rawValue)|\(locationKey)|\(subscriptionKey)"
    }

    private var alertPrimaryButtonTitle: String {
        if selectedAlertCity != nil, alertCityPickerModel.currentLocationCity != nil {
            return String(localized: "Turn On Alerts", comment: "Primary onboarding button title for enabling merchant alerts")
        }
        if let selectedAlertCity {
            return String(
                localized: "Turn On Alerts for \(selectedAlertCity.city)",
                comment: "Primary onboarding button title for enabling merchant alerts for the selected city"
            )
        }
        return String(localized: "Choose a City First", comment: "Disabled onboarding alert button title shown before the user selects a city")
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
            return String(localized: "Search any city, or use the suggestion when it appears.", comment: "Helper text shown in onboarding when alert city suggestions may appear")
        }

        return String(localized: "Search for a city to turn on alerts.", comment: "Helper text shown in onboarding when the user must search to choose an alert city")
    }

    private var alertEmptyBrowseText: String? {
        if isLocationAuthorizedForAlerts {
            return String(localized: "We’ll suggest your current city when it’s ready, or you can search for any city.", comment: "Empty state text shown while the current city suggestion is not yet available during onboarding")
        }

        return nil
    }

    func syncSelectedAlertCityIfNeeded() {
        selectedAlertCity = OnboardingStepProgression.preferredAlertCity(
            hasManuallySelected: hasManuallySelectedAlertCity,
            currentSelected: selectedAlertCity,
            currentLocationCity: alertCityPickerModel.currentLocationCity?.choice,
            activeAlertCity: alertCityPickerModel.activeAlertCity,
            firstRecommendedCity: alertCityPickerModel.recommendedCities.first?.choice
        )
    }

    private func enableSelectedCityAlerts() async {
        guard let selectedAlertCity else { return }
        guard !isEnablingAlerts else { return }

        isEnablingAlerts = true
        alertsErrorMessage = nil
        defer { isEnablingAlerts = false }

        alertsErrorMessage = await merchantAlertsManager.enableNotifications(for: selectedAlertCity)

        if merchantAlertsManager.currentSubscription?.locationID == selectedAlertCity.locationID {
            proceedToNextPage()
        }
    }
}
