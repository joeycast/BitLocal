import SwiftUI

struct MerchantAlertsView: View {
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @Binding var currentDetent: PresentationDetent
    @State private var showingCityPicker = false

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
                Label(
                    "iCloud Required",
                    systemImage: "icloud.slash"
                )

                Text(merchantAlertsManager.cloudKitStatusSummary)
                    .foregroundStyle(.secondary)
            }

            if let settings = merchantAlertsManager.notificationSettings,
               settings.authorizationStatus == .denied {
                Text("Notifications are turned off for BitLocal. You can turn them on in Settings.")
                    .foregroundStyle(.secondary)

                Button("Open Settings") {
                    merchantAlertsManager.openSystemSettings()
                }
            }

            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Welcome (no city chosen)

    private var welcomeSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "bell.and.waves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.accent)
                    .padding(.top, 8)

                Text("Stay in the loop")
                    .font(.headline)

                Text("Pick a city and we’ll send a daily morning digest when new businesses start accepting Bitcoin there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    guard merchantAlertsManager.canEnableAlerts else { return }
                    showingCityPicker = true
                } label: {
                    Text("Pick a City")
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
            Text("BitLocal sends a daily morning digest for your city when it finds new Bitcoin-accepting businesses there.")
                .foregroundStyle(secondaryTextColor)
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Active subscription

    private func activeCitySection(_ subscription: CitySubscription) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.displayName)
                        .font(.headline)
                    Text("We’ll send a daily morning digest when new places start accepting Bitcoin here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button("Change City") {
                showingCityPicker = true
            }
        } footer: {
            Button("Stop Alerts", role: .destructive) {
                Task {
                    await merchantAlertsManager.disableNotifications()
                }
            }
            .font(.footnote)
            .padding(.top, 8)
        }
        .groupedCardListRowBackground(if: shouldUseGlassyRows)
    }

    // MARK: - Latest update

    private var latestUpdateSection: some View {
        Section("Latest Update") {
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
            return .accentColor
        }

        if shouldUseGlassyRows {
            return Color.white.opacity(0.08)
        }

        return Color(uiColor: .tertiarySystemFill)
    }

    private var pickCityButtonForegroundStyle: Color {
        merchantAlertsManager.canEnableAlerts ? .white : Color(uiColor: .secondaryLabel)
    }

    private var pickCityButtonBorderOpacity: Double {
        merchantAlertsManager.canEnableAlerts ? 0.0 : (shouldUseGlassyRows ? 0.12 : 0.06)
    }
}
