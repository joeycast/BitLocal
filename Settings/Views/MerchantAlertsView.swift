import SwiftUI
import BitLocalDesign

struct MerchantAlertsView: View {
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @Binding var currentDetent: PresentationDetent
    @State private var showingCityPicker = false
    @State private var confirmingTurnOff = false

    var body: some View {
        List {
            if showsStatusSection {
                statusSection
            }

            if let subscription = merchantAlertsManager.currentSubscription {
                activeCitySection(subscription)
                latestUpdateSection
            } else {
                welcomeSection
            }
        }
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .clearNavigationContainerBackgroundIfAvailable()
        .navigationTitle("Merchant Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingCityPicker) {
            MerchantAlertCityPickerView(currentDetent: $currentDetent) { choice in
                Task {
                    await merchantAlertsManager.enableNotifications(for: choice)
                }
            }
        }
        .task {
            await merchantAlertsManager.refreshStatus()
        }
    }

    // MARK: - Status

    private var showsStatusSection: Bool {
        !merchantAlertsManager.isCloudKitAvailable
            || merchantAlertsManager.notificationSettings?.authorizationStatus == .denied
            || merchantAlertsManager.errorMessage != nil
    }

    private var statusSection: some View {
        Section {
            if !merchantAlertsManager.isCloudKitAvailable {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud is needed for alerts")
                        Text(merchantAlertsManager.cloudKitStatusSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }

            if let settings = merchantAlertsManager.notificationSettings,
               settings.authorizationStatus == .denied {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications are off for BitLocal")
                        Button("Open Settings") {
                            merchantAlertsManager.openSystemSettings()
                        }
                        .font(.footnote.weight(.semibold))
                        .tint(BrandColor.brandInk)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandColor.brand)
                }
            }

            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(BrandColor.closed)
            }
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Welcome (no city chosen)

    private var welcomeSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 40))
                    .foregroundStyle(BrandColor.brand)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                Text("Get a morning note when a place in your city starts accepting bitcoin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    guard merchantAlertsManager.canEnableAlerts else { return }
                    showingCityPicker = true
                } label: {
                    Text("Choose a city")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(pickCityButtonForegroundStyle)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(pickCityButtonBackgroundColor)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white.opacity(pickCityButtonBorderOpacity))
                                }
                        }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(merchantAlertsManager.canEnableAlerts)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } footer: {
            if !merchantAlertsManager.canEnableAlerts {
                Text(merchantAlertsDisabledReason)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Active subscription

    private func activeCitySection(_ subscription: CitySubscription) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(BrandColor.brand)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.displayName)
                        .font(.headline)
                    Text("Daily morning digest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button("Change city") {
                showingCityPicker = true
            }
            .tint(BrandColor.brandInk)

            Button("Turn off", role: .destructive) {
                confirmingTurnOff = true
            }
            .confirmationDialog(
                "Turn off alerts for \(subscription.city)?",
                isPresented: $confirmingTurnOff,
                titleVisibility: .visible
            ) {
                Button("Turn off", role: .destructive) {
                    Task {
                        await merchantAlertsManager.disableNotifications()
                    }
                }
            }
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Latest update

    private var latestUpdateSection: some View {
        Section("Latest update") {
            if let digest = merchantAlertsManager.lastDigest {
                Button {
                    merchantAlertsManager.presentLastDigest()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(digest.summaryLine)
                                .foregroundStyle(.primary)
                            if let digestWindowEnd = digest.digestWindowEnd {
                                Text(digestWindowEnd.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Nothing yet — you’ll see updates here as new merchants pop up.")
                    .foregroundStyle(.secondary)
            }
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    private var shouldHideSheetBackground: Bool {
        currentDetent != .large
    }

    private var shouldUseGlassyRows: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return currentDetent != .large
    }

    private var secondaryTextColor: Color {
        Color(uiColor: .secondaryLabel)
    }

    private var pickCityButtonBackgroundColor: Color {
        if merchantAlertsManager.canEnableAlerts {
            return BrandColor.brandFill
        }

        if shouldUseGlassyRows {
            return Color.white.opacity(0.08)
        }

        return Color(uiColor: .tertiarySystemFill)
    }

    private var pickCityButtonForegroundStyle: Color {
        merchantAlertsManager.canEnableAlerts ? BrandColor.onBrandFill : Color(uiColor: .secondaryLabel)
    }

    private var merchantAlertsDisabledReason: String {
        if !merchantAlertsManager.isCloudKitAvailable {
            return NSLocalizedString("Sign in to iCloud in the Settings app to choose a city.", comment: "Merchant alerts: why the Choose a city button is disabled")
        }
        return NSLocalizedString("Turn on notifications for BitLocal to choose a city.", comment: "Merchant alerts: why the Choose a city button is disabled when notifications are off")
    }

    private var pickCityButtonBorderOpacity: Double {
        merchantAlertsManager.canEnableAlerts ? 0.0 : (shouldUseGlassyRows ? 0.12 : 0.06)
    }
}
