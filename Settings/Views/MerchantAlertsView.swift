import SwiftUI
import UserNotifications

@available(iOS 17.0, *)
struct MerchantAlertsView: View {
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @State private var showingCityPicker = false

    var body: some View {
        List {
            statusSection
            citySection
            latestDigestSection
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

    private var statusSection: some View {
        Section("Status") {
            Label(
                merchantAlertsManager.isCloudKitAvailable ? "iCloud Ready" : "iCloud Required",
                systemImage: merchantAlertsManager.isCloudKitAvailable ? "checkmark.icloud.fill" : "icloud.slash"
            )

            Text(merchantAlertsManager.cloudKitStatusSummary)
                .foregroundStyle(.secondary)

            if let settings = merchantAlertsManager.notificationSettings {
                Text(notificationStatusText(settings.authorizationStatus))
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = merchantAlertsManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if merchantAlertsManager.notificationSettings?.authorizationStatus == .denied {
                Button("Open Notification Settings") {
                    merchantAlertsManager.openSystemSettings()
                }
            }
        }
    }

    private var citySection: some View {
        Section("City") {
            if let subscription = merchantAlertsManager.currentSubscription {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.displayName)
                        .font(.headline)
                    Text("Daily new-merchant digests are enabled for this city.")
                        .foregroundStyle(.secondary)
                }

                Button("Change City") {
                    showingCityPicker = true
                }

                Button("Turn Off Alerts", role: .destructive) {
                    Task {
                        await merchantAlertsManager.disableNotifications()
                    }
                }
            } else {
                Text("Choose a city and BitLocal will subscribe this device to daily new-merchant digests for that location.")
                    .foregroundStyle(.secondary)

                Button("Choose City") {
                    showingCityPicker = true
                }
                .disabled(!merchantAlertsManager.canEnableAlerts)
            }
        }
    }

    private var latestDigestSection: some View {
        Section("Latest Digest") {
            if let digest = merchantAlertsManager.lastDigest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(digest.cityDisplayName)
                        .font(.headline)
                    Text(digest.summaryLine)
                        .foregroundStyle(.secondary)
                    if let digestWindowEnd = digest.digestWindowEnd {
                        Text("Received \(digestWindowEnd.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Open Digest") {
                    merchantAlertsManager.presentLastDigest()
                }
            } else {
                Text("No city digests have been received on this device yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        Section("How It Works") {
            Text("BitLocal stores daily city digests in CloudKit’s public database, then uses a CloudKit query subscription to notify devices that follow a matching city.")
                .foregroundStyle(.secondary)
            Text("This version requires iCloud and standard notification permission. Users who are not signed in to iCloud can still browse the app, but they cannot enable merchant alerts.")
                .foregroundStyle(.secondary)
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Notifications are enabled for merchant alerts."
        case .provisional:
            return "Notifications are provisionally allowed."
        case .denied:
            return "Notifications are disabled for BitLocal."
        case .notDetermined:
            return "BitLocal has not requested notification permission yet."
        case .ephemeral:
            return "Notifications are temporarily available."
        @unknown default:
            return "Notification permission status is unknown."
        }
    }
}
