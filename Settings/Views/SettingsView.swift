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

            merchantAlertsSection

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

    private var merchantAlertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if merchantAlertsManager.isCloudKitAvailable {
                    NavigationLink {
                        MerchantAlertsView(currentDetent: $currentDetent)
                    } label: {
                        merchantAlertsRow(showChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    merchantAlertsRow(showChevron: false)
                }
            }

            if !merchantAlertsManager.isCloudKitAvailable {
                Text("Merchant alerts require iCloud be enabled for your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var merchantAlertsSubtitle: String {
        "Get notified when new merchants appear in your city."
    }

    @ViewBuilder
    private func merchantAlertsRow(showChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: merchantAlertsManager.currentSubscription == nil ? "bell.badge" : "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(merchantAlertsManager.isCloudKitAvailable ? .accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Merchant Alerts")
                        .font(.headline)
                        .foregroundStyle(merchantAlertsManager.isCloudKitAvailable ? .primary : .secondary)

                    Text(merchantAlertsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .frame(height: 28)
                }
            }
        }
        .padding(.vertical, 8)
        .opacity(merchantAlertsManager.isCloudKitAvailable ? 1 : 0.65)
        .contentShape(Rectangle())
    }
}
