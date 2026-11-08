import MapKit
import StoreKit
import SwiftUI
import BitLocalDesign

/// One native list (ui-redesign 6.9): Map, Appearance, Merchant Alerts,
/// Contribute, About. Every row is a system control.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Binding var selectedMapType: MKMapType
    @Binding var currentDetent: PresentationDetent
    var onDone: (() -> Void)? = nil

    @EnvironmentObject private var viewModel: ContentViewModel
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var releaseNotesController: ReleaseNotesController
    @EnvironmentObject private var merchantAlertsManager: MerchantAlertsManager
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    @State private var showingAbout = false
    @State private var showingAddBusiness = false
    @State private var copiedVersion = false

    private let reportIssueURL = URL(string: "mailto:support@bitlocal.app?subject=BitLocal%20issue")!
    private let privacyPolicyURL = URL(string: "https://www.bitlocal.app/privacy")!

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
            Section("Map") {
                Picker("Map style", selection: $selectedMapType) {
                    Text("Standard").tag(MKMapType.standard)
                    Text("Satellite").tag(MKMapType.hybrid)
                }
                Picker("Distance units", selection: $distanceUnit) {
                    Text("Auto").tag(DistanceUnit.auto)
                    Text("Miles").tag(DistanceUnit.miles)
                    Text("Kilometers").tag(DistanceUnit.kilometers)
                }
                Toggle("Show ATMs", isOn: showATMsBinding)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearanceManager.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                merchantAlertsRow
            } footer: {
                if !merchantAlertsManager.isCloudKitAvailable {
                    Text("Merchant alerts need iCloud. Sign in to iCloud in the Settings app to turn them on.")
                }
            }

            Section("Contribute") {
                Button {
                    showingAddBusiness = true
                } label: {
                    Label("Add a business", systemImage: "storefront")
                }
                Link(destination: reportIssueURL) {
                    Label("Report an issue", systemImage: "exclamationmark.bubble")
                }
            }

            Section {
                Button {
                    showingAbout = true
                } label: {
                    Label("About BitLocal", systemImage: "info.circle")
                }
                Button {
                    releaseNotesController.presentCurrentReleaseNotes()
                    close()
                } label: {
                    Label("What's New", systemImage: "sparkles")
                }
                Link(destination: privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Button {
                    requestReview()
                } label: {
                    Label("Rate BitLocal", systemImage: "star")
                }
                versionRow
            } header: {
                Text("About")
            } footer: {
                attributionFooter
            }
        }
        .tint(BrandColor.brandInk)
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: close) {
                    Text("done_button").bold()
                }
            }
        }
        .task {
            await merchantAlertsManager.refreshStatus()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingAddBusiness) {
            AddBusinessInfoView()
        }
    }

    private func close() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    // MARK: - Rows

    /// `hideATMsFromMapAndList` is stored inverted; the toggle reads as "show".
    private var showATMsBinding: Binding<Bool> {
        Binding(
            get: { !viewModel.hideATMsFromMapAndList },
            set: { viewModel.setHideATMsFromMapAndList(!$0) }
        )
    }

    @ViewBuilder
    private var merchantAlertsRow: some View {
        if merchantAlertsManager.isCloudKitAvailable {
            NavigationLink {
                MerchantAlertsView(currentDetent: $currentDetent)
            } label: {
                merchantAlertsLabel
            }
            .featureHintAnchor(.merchantAlerts)
        } else {
            merchantAlertsLabel
                .foregroundStyle(.secondary)
                .featureHintAnchor(.merchantAlerts)
        }
    }

    private var merchantAlertsLabel: some View {
        LabeledContent {
            Text(merchantAlertsStatus)
        } label: {
            Label("Merchant Alerts", systemImage: "bell.badge")
        }
    }

    private var merchantAlertsStatus: String {
        guard merchantAlertsManager.isCloudKitAvailable else {
            return NSLocalizedString("Unavailable", comment: "Settings: merchant alerts status when iCloud is unavailable")
        }
        guard let subscription = merchantAlertsManager.currentSubscription else {
            return NSLocalizedString("Off", comment: "Settings: merchant alerts status when no city is chosen")
        }
        return String(
            format: NSLocalizedString("%@ · On", comment: "Settings: merchant alerts status, e.g. 'Nashville · On'"),
            subscription.city
        )
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var versionRow: some View {
        LabeledContent("Version") {
            Text(copiedVersion ? NSLocalizedString("Copied", comment: "Settings: version copied to clipboard") : versionString)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            UIPasteboard.general.string = versionString
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            copiedVersion = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedVersion = false }
        }
        .accessibilityHint("Long press to copy")
    }

    private var attributionFooter: some View {
        Text("Place data from [BTC Map](https://btcmap.org/) and [OpenStreetMap](https://openstreetmap.org/copyright) contributors.")
    }
}
