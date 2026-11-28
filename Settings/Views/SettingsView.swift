import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var selectedMapType: MKMapType
    @Binding var currentDetent: PresentationDetent
    var onDone: (() -> Void)? = nil

    @Environment(ContentViewModel.self) private var viewModel
    @Environment(AppearanceManager.self) private var appearanceManager
    @Environment(MerchantAlertsManager.self) private var merchantAlertsManager
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    @State private var showingAddBusinessForm = false
    @State private var isRefreshingMerchants = false

    private static let supportBitLocalURL = URL(string: "https://strike.me/joeycast/")

    init(
        selectedMapType: Binding<MKMapType>,
        currentDetent: Binding<PresentationDetent> = .constant(.large),
        onDone: (() -> Void)? = nil
    ) {
        self._selectedMapType = selectedMapType
        self._currentDetent = currentDetent
        self.onDone = onDone
    }

    var body: some View {
        List {
            mapAndDisplaySection
            alertsAndDataSection
            contributeSection
            if locale.region?.identifier == "US", let supportBitLocalURL = Self.supportBitLocalURL {
                supportSection(url: supportBitLocalURL)
            }
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: handleDone) {
                    Text("done_button")
                        .bold()
                }
            }
        }
        .disableVerticalToolbarIfAvailable()
        .task {
            await merchantAlertsManager.refreshStatus()
        }
        .sheet(isPresented: $showingAddBusinessForm) {
            AddBusinessInfoView()
        }
        .sensoryFeedback(.selection, trigger: selectedMapType)
        .sensoryFeedback(.selection, trigger: appearanceManager.appearance)
        .sensoryFeedback(.selection, trigger: distanceUnit)
        .sensoryFeedback(.selection, trigger: viewModel.hideATMsFromMapAndList)
        .sensoryFeedback(.impact(weight: .light), trigger: isRefreshingMerchants) { _, isRefreshing in
            isRefreshing
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showingAddBusinessForm) { _, isShowing in
            isShowing
        }
    }

    // MARK: - Sections

    private var mapAndDisplaySection: some View {
        @Bindable var appearanceManager = appearanceManager
        return Section {
            Picker(selection: $selectedMapType) {
                Text("Standard").tag(MKMapType.standard)
                Text("Hybrid").tag(MKMapType.hybrid)
            } label: {
                Label("Map", systemImage: "map")
            }

            Picker(selection: $appearanceManager.appearance) {
                Text("System").tag(Appearance.system)
                Text("Light").tag(Appearance.light)
                Text("Dark").tag(Appearance.dark)
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }

            Picker(selection: $distanceUnit) {
                Text("Auto").tag(DistanceUnit.auto)
                Text("Miles").tag(DistanceUnit.miles)
                Text("Km").tag(DistanceUnit.kilometers)
            } label: {
                Label("Distance", systemImage: "ruler")
            }

            Toggle(isOn: showATMsBinding) {
                Label("Show ATMs", systemImage: "banknote")
            }
            .tint(.accentColor)
        }
    }

    private var alertsAndDataSection: some View {
        Section {
            if merchantAlertsManager.isCloudKitAvailable {
                NavigationLink {
                    MerchantAlertsView(currentDetent: $currentDetent)
                } label: {
                    merchantAlertsRowLabel
                }
                .featureHintAnchor(.merchantAlerts)
            } else {
                merchantAlertsRowLabel
                    .opacity(0.6)
                    .featureHintAnchor(.merchantAlerts)
            }

            Button {
                refreshMerchants()
            } label: {
                HStack(spacing: 12) {
                    if isRefreshingMerchants || viewModel.isLoading {
                        ProgressView()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body)
                            .foregroundStyle(.accent)
                            .frame(width: 22, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refresh Merchants")
                            .foregroundStyle(.primary)
                        Text(merchantRefreshSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(isRefreshingMerchants || viewModel.isLoading)
        } footer: {
            if !merchantAlertsManager.isCloudKitAvailable {
                Text("Merchant alerts require iCloud be enabled for your device.")
            }
        }
    }

    private var contributeSection: some View {
        Section(header: Text("contribute_section")) {
            Button {
                showingAddBusinessForm = true
            } label: {
                Label {
                    Text("add_business_to_map")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "storefront")
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    private func supportSection(url: URL) -> some View {
        Section(
            header: Text("support_bitlocal_section"),
            footer: Text("support_bitlocal_footer")
        ) {
            Link(destination: url) {
                HStack {
                    Label {
                        Text("support_bitlocal_button_label")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "heart")
                            .foregroundStyle(.accent)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView(
                    currentDetent: $currentDetent,
                    onDismissSheet: handleDone
                )
            } label: {
                HStack {
                    Label {
                        Text("about_title")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.accent)
                    }
                    Spacer(minLength: 8)
                    if let version = appVersionString {
                        Text(version)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var showATMsBinding: Binding<Bool> {
        Binding(
            get: { !viewModel.hideATMsFromMapAndList },
            set: { showATMs in
                viewModel.setHideATMsFromMapAndList(!showATMs)
            }
        )
    }

    private var merchantAlertsRowLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: merchantAlertsManager.currentSubscription == nil ? "bell.badge" : "bell.badge.fill")
                .font(.body)
                .foregroundStyle(merchantAlertsManager.isCloudKitAvailable ? .accent : .secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("Merchant Alerts")
                    .foregroundStyle(.primary)
                Text(merchantAlertsSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if merchantAlertsManager.currentSubscription != nil {
                Text("On")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var merchantAlertsSubtitle: String {
        if let subscription = merchantAlertsManager.currentSubscription {
            return subscription.displayName
        }
        return String(
            localized: "Get notified when new merchants appear in your city.",
            comment: "Settings subtitle explaining Merchant Alerts before a city is selected"
        )
    }

    private var merchantRefreshSubtitle: String {
        if isRefreshingMerchants || viewModel.isLoading {
            return String(localized: "Updating…", comment: "Status while merchant catalog refresh is in progress")
        }
        if let relative = viewModel.lastSuccessfulSyncRelativeDescription {
            return String(
                localized: "Updated \(relative)",
                comment: "Relative last-synced label, e.g. Updated 5 minutes ago"
            )
        }
        return String(localized:
            "Fetch new and changed merchants since the last sync.",
            comment: "About subtitle explaining incremental merchant refresh"
        )
    }

    private var appVersionString: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return nil
        }
        return "v\(version)"
    }

    private func refreshMerchants() {
        guard !isRefreshingMerchants else { return }
        isRefreshingMerchants = true
        viewModel.refreshMerchantData(userInitiated: true) {
            isRefreshingMerchants = false
        }
    }

    private func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
