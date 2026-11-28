import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(ReleaseNotesController.self) private var releaseNotesController
    @Binding var currentDetent: PresentationDetent
    var onDismissSheet: (() -> Void)? = nil

    // Contact links with prefilled subjects
    private let generalSupportInquiriesEmail = URL(string: "mailto:support@bitlocal.app?subject=BitLocal%20Support")!
    private let reportABugEmail = URL(string: "mailto:support@bitlocal.app?subject=BitLocal%20Bug%20Report")!
    private let suggestAFeatureEmail = URL(string: "mailto:support@bitlocal.app?subject=BitLocal%20Feature%20Request")!

    // Socials
    private let twitterURL = URL(string: "https://twitter.com/bitlocal_app")!

    // More from Brink 13 Labs
    private let bitcoinLivePriceChartURL = URL(string: "https://brink13labs.com")!
    private let movematesMoveTogetherURL = URL(string: "https://apps.apple.com/us/app/movemates-move-together/id6748308903")!
    private let dandelionURL = URL(string: "https://apps.apple.com/app/id6757363901")!

    // Links & Credits
    private let brink13LabsWebsite = URL(string: "https://brink13labs.com")!
    private let bitlocalWebsite = URL(string: "https://www.bitlocal.app")!
    private let privacyPolicyURL = URL(string: "https://www.bitlocal.app/privacy")!
    private let btcMapURL = URL(string: "https://btcmap.org/")!
    private let openStreetMapURL = URL(string: "https://openstreetmap.org/copyright")!
    private let bitcoinResourcesURL = URL(string: "https://www.lopp.net/bitcoin-information.html")!

    init(
        currentDetent: Binding<PresentationDetent> = .constant(.large),
        onDismissSheet: (() -> Void)? = nil
    ) {
        self._currentDetent = currentDetent
        self.onDismissSheet = onDismissSheet
    }

    private var versionBuildLabel: String? {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (shortVersion, build) {
        case let (v?, b?) where !v.isEmpty && !b.isEmpty:
            return String(localized: "Version \(v) (\(b))", comment: "App version and build number label")
        case let (v?, _) where !v.isEmpty:
            return String(localized: "Version \(v)", comment: "App version label")
        default:
            return nil
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("bitlocal")
                            .font(.custom("Fredoka-Medium", size: 26, relativeTo: .title2))
                            .foregroundStyle(.accent)

                        if let versionBuildLabel {
                            Text(versionBuildLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("about_description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("contact_section")) {
                externalLinkRow(
                    destination: generalSupportInquiriesEmail,
                    titleKey: "general_support_inquiries",
                    systemImage: "paperplane"
                )
                externalLinkRow(
                    destination: reportABugEmail,
                    titleKey: "report_a_bug",
                    systemImage: "ladybug"
                )
                externalLinkRow(
                    destination: suggestAFeatureEmail,
                    titleKey: "suggest_a_feature",
                    systemImage: "lightbulb"
                )
                Link(destination: twitterURL) {
                    HStack {
                        Label {
                            Text("x_twitter_label")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(.xLogoFill)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundStyle(.accent)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }

            Section(header: Text("other_section")) {
                externalLinkRow(destination: bitlocalWebsite, titleKey: "bitlocal_website", systemImage: "safari")
                externalLinkRow(destination: brink13LabsWebsite, titleKey: "brink_13_labs_website", systemImage: "safari")
                externalLinkRow(destination: privacyPolicyURL, titleKey: "privacy_policy", systemImage: "hand.raised")
                externalLinkRow(destination: btcMapURL, titleKey: "btc_map", systemImage: "mappin.and.ellipse")
                externalLinkRow(destination: openStreetMapURL, titleKey: "open_street_map", systemImage: "globe")
                externalLinkRow(destination: bitcoinResourcesURL, titleKey: "bitcoin_resources", systemImage: "bitcoinsign.circle")
            }

            Section(header: Text("more_from_brink_13_Labs_section")) {
                externalLinkRow(
                    destination: bitcoinLivePriceChartURL,
                    titleKey: "bitcoin_live_price_chart_button_label",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                if locale.region?.identifier == "US" {
                    externalLinkRow(
                        destination: movematesMoveTogetherURL,
                        titleKey: "Movemates: Move Together",
                        systemImage: "figure.run"
                    )
                }
                externalLinkRow(
                    destination: dandelionURL,
                    titleKey: "Dandelion: Write and Let Go",
                    systemImage: "camera.macro"
                )
            }

            Section {
                Button {
                    BitLocalHaptics.selection()
                    releaseNotesController.presentCurrentReleaseNotes()
                    dismissSheet()
                } label: {
                    Label {
                        Text("show_whats_new_button")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.accent)
                    }
                }

                Button {
                    BitLocalHaptics.selection()
                    UserDefaults.standard.set(false, forKey: "didCompleteOnboarding")
                    dismissSheet()
                } label: {
                    Label {
                        Text("show_onboarding_button")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.accent)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("about_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            currentDetent = .large
        }
    }

    private func externalLinkRow(
        destination: URL,
        titleKey: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Link(destination: destination) {
            HStack {
                Label {
                    Text(titleKey)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.accent)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func dismissSheet() {
        if let onDismissSheet {
            onDismissSheet()
        } else {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .environment(ReleaseNotesController())
    }
}
