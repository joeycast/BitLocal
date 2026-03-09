import SwiftUI

@available(iOS 17.0, *)
struct MerchantAlertsView: View {
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @State private var showingCityPicker = false

    var body: some View {
        List {
            if showsStatusSection {
                statusSection
            }
            citySection
            if merchantAlertsManager.currentSubscription != nil {
                latestDigestSection
            }
            infoSection
        }
        .navigationTitle("Merchant Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingCityPicker) {
            MerchantAlertCityPickerView { choice in
                Task {
                    await merchantAlertsManager.enableNotifications(for: choice)
                }
            }
        }
        .task {
            await merchantAlertsManager.refreshStatus()
        }
    }

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
    }

    private var citySection: some View {
        Section("Your City") {
            if let subscription = merchantAlertsManager.currentSubscription {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.displayName)
                        .font(.headline)
                    Text("We'll let you know when new places start accepting Bitcoin here.")
                        .foregroundStyle(.secondary)
                }

                Button("Change City") {
                    showingCityPicker = true
                }

                Button("Stop Alerts", role: .destructive) {
                    Task {
                        await merchantAlertsManager.disableNotifications()
                    }
                }
            } else {
                Text("Pick a city and we'll notify you when new businesses start accepting Bitcoin there.")
                    .foregroundStyle(.secondary)

                Button("Pick a City") {
                    showingCityPicker = true
                }
                .disabled(!merchantAlertsManager.canEnableAlerts)
            }
        }
    }

    private var latestDigestSection: some View {
        Section("Latest Update") {
            if let digest = merchantAlertsManager.lastDigest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(digest.cityDisplayName)
                        .font(.headline)
                    Text(digest.summaryLine)
                        .foregroundStyle(.secondary)
                    if let digestWindowEnd = digest.digestWindowEnd {
                        Text(digestWindowEnd.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("View Details") {
                    merchantAlertsManager.presentLastDigest()
                }
            } else {
                Text("Nothing yet! You'll see updates here as new merchants pop up.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        Section("How It Works") {
            Text("BitLocal checks for new Bitcoin-accepting businesses in your city every day. When we find new ones, you’ll get a notification with the details.")
                .foregroundStyle(.secondary)
            Text("Alerts require iCloud sign-in and notification permission.")
                .foregroundStyle(.secondary)
        }
    }

}
