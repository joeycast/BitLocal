import SwiftUI

@available(iOS 17.0, *)
struct AboutView: View {
    
    // For dismissing the SettingsView sheet
    @Environment(\.dismiss) var dismiss
    
    @State private var showingLogs = false
    
    // App name
    let appName = "BitLocal"
    
    // Contribute section links
    let suggestABusinessEmail = URL(string:"mailto:support@bitlocal.app")!
    
    // Contact section links
    let generalSupportInquiriesEmail = URL(string:"mailto:support@bitlocal.app")!
    let reportABugEmail = URL(string:"mailto:support@bitlocal.app")!
    let suggestAFeatureEmail = URL(string:"mailto:support@bitlocal.app")!
    
    // Socials section links
    let twitterURL = URL(string:"https://twitter.com/bitlocal_app")!
    //    let discordURL = URL(string:"")!
    //    let nostrURL = URL(string:"")!
    
    // Other section links
    let bitcoinResourcesURL = URL(string: "https://www.lopp.net/bitcoin-information.html")!
    let privacyPolicyURL = URL(string: "https://github.com/joeycast/BitLocal.app/blob/main/Privacy_Policy.md")!
    let bitlocalWebsite = URL(string: "https://www.bitlocal.app")!
    let btcMapURL = URL(string: "https://btcmap.org/")!
    let openStreetMapURL = URL(string: "https://openstreetmap.org/copyright")!
    
    // Support Development links
    // let tipJarURL = URL(string: "")!
    
    let iconSize: CGFloat = 20
    
    // Settings Page
    var body: some View {
        
        NavigationView {
            Form {
                // Header section
                Section {
                    Text("about_description")
                }
                // Contribute section
                Section(header: Text("contribute_section"),
                        footer: Text("contribute_footer")) {
                    Link(destination: suggestABusinessEmail) {
                        HStack(spacing: 10) {
                            Image("storefront-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("suggest_a_business")
                            Spacer()
                        }
                    }
                }
                // Contact section
                Section(header: Text("contact_section")) {
                    Link(destination: generalSupportInquiriesEmail) {
                        HStack(spacing: 10) {
                            Image("paper-plane-tilt-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("general_support_inquiries")
                            Spacer()
                        }
                    }
                    Link(destination: reportABugEmail) {
                        HStack(spacing: 10) {
                            Image("bug-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("report_a_bug")
                            Spacer()
                        }
                    }
                    Link(destination: suggestAFeatureEmail) {
                        HStack(spacing: 10) {
                            Image("lightbulb-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("suggest_a_feature")
                            Spacer()
                        }
                    }
                }
                // Socials section
                Section(header: Text("socials_section")) {
                    Link(destination: twitterURL) {
                        HStack(spacing: 10) {
                            Image("x-logo-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("x_twitter_label")
                            Spacer()
                        }
                    }
                    //                    Link(destination: discordURL,
                    //                         label: {
                    //                        Label("Discord", systemImage: "link")
                    //                    })
                    //                    Link(destination: nostrURL,
                    //                         label: {
                    //                        Label("Nostr", systemImage: "link")
                    //                    })
                }
                // Other section
                Section(header: Text("other_section")) {
                    Link(destination: bitlocalWebsite) {
                        HStack(spacing: 10) {
                            Image("compass-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("bitlocal_website")
                            Spacer()
                        }
                    }
                    Link(destination: privacyPolicyURL) {
                        HStack(spacing: 10) {
                            Image("hand-palm-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("privacy_policy")
                            Spacer()
                        }
                    }
                    Link(destination: btcMapURL) {
                        HStack(spacing: 10) {
                            Image("map-pin-line-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("btc_map")
                            Spacer()
                        }
                    }
                    Link(destination: openStreetMapURL) {
                        HStack(spacing: 10) {
                            Image("globe-simple-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("open_street_map")
                            Spacer()
                        }
                    }
                    Link(destination: bitcoinResourcesURL) {
                        HStack(spacing: 10) {
                            Image("currency-btc-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("bitcoin_resources")
                            Spacer()
                        }
                    }
                }
                // Support Development section
                //                Section(header: Text("Support Development"),
                //                        footer: Text("Support developing by tipping using Bitcoin over Lightning.")) {
                //                    Label("Tip Jar", systemImage: "bolt.circle.fill")
                //                }
                //                Section(header: Text("Logs")) {
                //                    Button("Show Logs") {
                //                        self.showingLogs = true
                //                    }
                //                    .sheet(isPresented: $showingLogs) {
                //                        // Display logs in a scrollable text view
                //                        ScrollView {
                //                            Text(LogManager.shared.allLogs())
                //                                .padding()
                //                                .font(.system(.body, design: .monospaced))
                //                        }
                //                    }
                //                }
                Section {
                    Button {
                        UserDefaults.standard.set(false, forKey: "didCompleteOnboarding")
                        // Only dismiss the sheet if we're on an iPad
                        #if os(iOS)
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            dismiss()
                        }
                        #endif
                    } label: {
                        HStack(spacing: 10) {
                            Image("cards-three-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("show_onboarding_button")
                            Spacer()
                        }
                    }
                    Button("🧪 Test Cache Clear") {
                        UserDefaults.standard.set("1.9", forKey: "lastAppVersion")
                        APIManager.shared.checkAndHandleVersionChange()
                    }
                }
            }
            // About page title
            // TODO: Figure out how to use the appName constant here
            .navigationTitle(Text("about_title"))
            
            // Dismiss sheet when tapping Done.
            .navigationBarItems(trailing:
                Button(action: { dismiss() }) {
                    Text("done_button")
                        .bold() // or .fontWeight(.bold)
                }
            )
        }
    }
}

// View preview
@available(iOS 17.0, *)
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
