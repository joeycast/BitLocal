import MapKit
import SwiftUI

@available(iOS 17.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMapType: MKMapType
    @Binding var currentDetent: PresentationDetent

    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    init(
        selectedMapType: Binding<MKMapType>,
        currentDetent: Binding<PresentationDetent> = .constant(.large)
    ) {
        self._selectedMapType = selectedMapType
        self._currentDetent = currentDetent
    }

    var body: some View {
        VStack(spacing: 24) {
            pickerRow(label: "Map", selection: $selectedMapType) {
                Text("Standard").tag(MKMapType.standard)
                Text("Hybrid").tag(MKMapType.hybrid)
            }

            pickerRow(label: "Theme", selection: $appearanceManager.appearance) {
                Text("System").tag(Appearance.system)
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
            }

            pickerRow(label: "Distance", selection: $distanceUnit) {
                Text("Auto").tag(DistanceUnit.auto)
                Text("Miles").tag(DistanceUnit.miles)
                Text("Km").tag(DistanceUnit.kilometers)
            }

            Divider()
                .padding(.top, 4)

            merchantAlertsRow

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { dismiss() }) {
                    Text("done_button")
                        .bold()
                }
            }
        }
        .task {
            await merchantAlertsManager.refreshStatus()
        }
    }

    // MARK: - Picker row

    private func pickerRow<SelectionValue: Hashable, Content: View>(
        label: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Picker(label, selection: selection, content: content)
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }

    // MARK: - Merchant Alerts

    private var merchantAlertsRow: some View {
        NavigationLink {
            MerchantAlertsView(currentDetent: $currentDetent)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.title3)
                    .foregroundStyle(.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(merchantAlertsManager.currentSubscription?.displayName ?? "Merchant Alerts")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(merchantAlertsManager.currentSubscription == nil
                         ? "Get notified about new Bitcoin merchants."
                         : "Following this city for new merchants.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
