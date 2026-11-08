//
//  OnboardingView.swift
//  bitlocal
//
//  Three steps (Welcome, Location, Alerts) on a card over the live map
//  (ui-redesign 6.8). RootView blurs the map behind the card until the
//  person allows location; then the map clears and flies to them.
//

import SwiftUI
import CoreLocation
import BitLocalDesign

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case location
    case alerts
}

struct OnboardingView: View {
    /// Set to true once the map behind the card should stop being blurred.
    @Binding var revealsMap: Bool

    @EnvironmentObject private var viewModel: ContentViewModel
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var isAwaitingLocationAnswer = false
    @StateObject private var alertCityPickerModel = MerchantAlertCityPickerModel()
    @State private var selectedAlertCity: MerchantAlertCityChoice?
    @State private var hasManuallySelectedAlertCity = false
    @State private var isEnablingAlerts = false

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            card
                .frame(maxWidth: isWide ? 480 : .infinity)
                .padding(.horizontal, isWide ? 0 : Spacing.s)
                .padding(.bottom, isWide ? 0 : Spacing.xs)
            if isWide { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(revealsMap ? 0 : 0.08).ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            finishLocationStepIfAnswered()
            // The new authorization status can land just after the app is active
            // again (seen on iPhone Duo), so look once more a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finishLocationStepIfAnswered() }
        }
        .onChange(of: viewModel.userLocation) { _, location in
            guard location != nil else { return }
            reveal()
            finishLocationStepIfAnswered()
        }
        .task(id: alertContextRefreshID) {
            guard step == .alerts else { return }
            await merchantAlertsManager.refreshStatus()
            await alertCityPickerModel.syncContext(
                userLocation: viewModel.userLocation,
                authorizationStatus: viewModel.locationManager.authorizationStatus,
                activeSubscription: merchantAlertsManager.currentSubscription
            )
            syncSelectedAlertCityIfNeeded()
        }
        .onAppear {
            if isLocationAuthorized { revealsMap = true }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            stepIndicator

            Group {
                switch step {
                case .welcome: welcomeStep
                case .location: locationStep
                case .alerts: alertsStep
                }
            }
            .id(step)
            .transition(stepTransition)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .legibleSurface(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? BrandColor.brand : Color.secondary.opacity(0.25))
                    .frame(width: item == step ? 20 : 8, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("Step %d of %d", comment: "Onboarding progress"),
            step.rawValue + 1,
            OnboardingStep.allCases.count
        )))
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.custom("Fredoka-Medium", size: 28, relativeTo: .title))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primaryButton(
        _ key: LocalizedStringKey,
        systemImage: String? = nil,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isBusy {
                    ProgressView().tint(BrandColor.onBrandFill)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(key)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.headline)
            .foregroundStyle(BrandColor.onBrandFill)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(BrandColor.brandFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private func textButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.minimumHitTarget)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title("Find places that accept bitcoin")
                bodyText("Shops, cafés and services near you, from the BTC Map community.")
            }
            primaryButton("Get started") { advance() }
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title("See what's near you")
                bodyText("BitLocal uses your location to show the closest places first. It stays on your phone.")
            }
            VStack(spacing: Spacing.xxs) {
                primaryButton("Allow location", systemImage: "location.fill") {
                    requestLocation()
                }
                textButton("Not now") { advance() }
            }
        }
    }

    private var alertsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title("Hear about new places near you")
                bodyText("Get a morning note when a place in your city starts accepting bitcoin.")
            }

            if merchantAlertsManager.isCloudKitAvailable {
                alertCityPicker
            } else {
                cloudKitStatusRow
            }

            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(BrandColor.closed)
            }

            if merchantAlertsManager.notificationSettings?.authorizationStatus == .denied {
                Button("Open Settings") { merchantAlertsManager.openSystemSettings() }
                    .font(.footnote.weight(.semibold))
                    .tint(BrandColor.brandInk)
            }

            VStack(spacing: Spacing.xxs) {
                if merchantAlertsManager.isCloudKitAvailable {
                    primaryButton("Turn on alerts", systemImage: "bell.badge.fill", isBusy: isEnablingAlerts) {
                        Task { await enableSelectedCityAlerts() }
                    }
                    .disabled(selectedAlertCity == nil || isEnablingAlerts || !merchantAlertsManager.canEnableAlerts)
                    .opacity(selectedAlertCity == nil ? 0.5 : 1)
                }
                if merchantAlertsManager.isCloudKitAvailable {
                    textButton("Skip") { finish() }
                } else {
                    // Alerts can't be turned on here, so this is the step's only way forward.
                    primaryButton("Continue") { finish() }
                }
            }
        }
    }

    // MARK: - Alerts city picker

    private var alertCityPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search city", text: $alertCityPickerModel.searchText)
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
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: LayoutMetrics.minimumHitTarget)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xs) {
                    if alertCityPickerModel.isShowingSearchResults {
                        searchResultRows
                    } else {
                        suggestedCityRows
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 190)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var suggestedCityRows: some View {
        if alertCityPickerModel.isLoadingBrowseContent {
            ProgressView("Finding your city…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
        } else {
            if let current = alertCityPickerModel.currentLocationCity {
                cityRow(title: current.choice.city, subtitle: current.displayName, badge: "Near you", choice: current.choice)
            }
            if let active = alertCityPickerModel.activeAlertCity {
                cityRow(title: active.city, subtitle: active.displayName, badge: "Current", choice: active)
            }
            ForEach(alertCityPickerModel.recommendedCities.prefix(2)) { result in
                cityRow(title: result.city, subtitle: result.displayName, badge: nil, choice: result.choice)
            }
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        if alertCityPickerModel.isLoading && alertCityPickerModel.results.isEmpty {
            ProgressView("Searching cities…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
        } else if alertCityPickerModel.results.isEmpty {
            Text("No city matches yet. Try a city name, state, or country.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
        } else {
            ForEach(alertCityPickerModel.results.prefix(4)) { result in
                cityRow(title: result.city, subtitle: result.displayName, badge: nil, choice: result.choice)
            }
        }
    }

    private func cityRow(
        title: String,
        subtitle: String,
        badge: LocalizedStringKey?,
        choice: MerchantAlertCityChoice
    ) -> some View {
        let isSelected = selectedAlertCity?.locationID == choice.locationID
        return Button {
            selectedAlertCity = choice
            hasManuallySelectedAlertCity = true
        } label: {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrandColor.brandInk)
                        }
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(BrandColor.brand) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.minimumHitTarget, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(BrandColor.selectionFill) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cloudKitStatusRow: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(merchantAlertsManager.cloudKitStatusSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("You can turn on alerts later in Settings once iCloud is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var isLocationAuthorized: Bool {
        let status = viewModel.locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(Motion.unlessReduced(Motion.move, reduceMotion: reduceMotion)) {
            step = next
        }
    }

    private func finish() {
        reveal()
        didCompleteOnboarding = true
    }

    private func reveal() {
        guard !revealsMap else { return }
        withAnimation(Motion.unlessReduced(.easeOut(duration: 0.45), reduceMotion: reduceMotion)) {
            revealsMap = true
        }
    }

    private func requestLocation() {
        switch viewModel.locationManager.authorizationStatus {
        case .notDetermined:
            isAwaitingLocationAnswer = true
            viewModel.requestWhenInUseLocationPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            viewModel.requestWhenInUseLocationPermission()
            reveal()
            advance()
        default:
            advance()
        }
    }

    /// The system permission alert makes the app inactive; when it becomes
    /// active again the person has answered.
    private func finishLocationStepIfAnswered() {
        guard isAwaitingLocationAnswer, step == .location else { return }
        guard viewModel.locationManager.authorizationStatus != .notDetermined else { return }
        isAwaitingLocationAnswer = false
        if isLocationAuthorized {
            reveal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { advance() }
        } else {
            advance()
        }
    }

    private var alertContextRefreshID: String {
        let locationKey = viewModel.userLocation.map {
            ReverseGeocodingSpatialKey.key(for: $0.coordinate, precision: 3)
        } ?? "no-location"
        let subscriptionKey = merchantAlertsManager.currentSubscription?.locationID ?? "no-subscription"
        return "\(step.rawValue)|\(viewModel.locationManager.authorizationStatus.rawValue)|\(locationKey)|\(subscriptionKey)"
    }

    private func syncSelectedAlertCityIfNeeded() {
        guard !hasManuallySelectedAlertCity else { return }
        selectedAlertCity = alertCityPickerModel.currentLocationCity?.choice
            ?? alertCityPickerModel.activeAlertCity
            ?? alertCityPickerModel.recommendedCities.first?.choice
    }

    private func enableSelectedCityAlerts() async {
        guard let selectedAlertCity, !isEnablingAlerts else { return }
        isEnablingAlerts = true
        defer { isEnablingAlerts = false }

        await merchantAlertsManager.enableNotifications(for: selectedAlertCity)

        if merchantAlertsManager.currentSubscription?.locationID == selectedAlertCity.locationID {
            finish()
        }
    }
}
