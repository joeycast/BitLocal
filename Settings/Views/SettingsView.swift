import MapKit
import SwiftUI

@available(iOS 17.0, *)
struct SettingsView: View {
    @Binding var selectedMapType: MKMapType

    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    var body: some View {
        List {
            mapSection
            appearanceSection
            distanceSection
            merchantAlertsSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await merchantAlertsManager.refreshStatus()
        }
    }

    private var mapSection: some View {
        Section("Map Type") {
            Picker("Map Type", selection: $selectedMapType) {
                Text("Standard").tag(MKMapType.standard)
                Text("Hybrid").tag(MKMapType.hybrid)
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        Section("Theme") {
            Picker("Theme", selection: $appearanceManager.appearance) {
                Text("System").tag(Appearance.system)
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
            }
            .pickerStyle(.segmented)
        }
    }

    private var distanceSection: some View {
        Section("Distance Units") {
            Picker("Distance Units", selection: $distanceUnit) {
                Text("Auto").tag(DistanceUnit.auto)
                Text("Miles").tag(DistanceUnit.miles)
                Text("Kilometers").tag(DistanceUnit.kilometers)
            }
            .pickerStyle(.segmented)
        }
    }

    private var merchantAlertsSection: some View {
        Section("Merchant Alerts") {
            NavigationLink {
                MerchantAlertsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(merchantAlertsManager.currentSubscription?.displayName ?? "New Merchant Alerts")
                            .foregroundStyle(.primary)
                        Text(merchantAlertsManager.currentSubscription == nil ? "Get notified when new places start accepting Bitcoin." : "You're following this city for new Bitcoin merchants.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "bell.badge")
                        .foregroundStyle(.accent)
                }
                .padding(.vertical, 4)
            }
        }
    }

}
