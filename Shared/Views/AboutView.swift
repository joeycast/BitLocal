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
    
    // Support BitLocal links
     let supportBitLocalURL = URL(string: "https://strike.me/joeycast/")!
    
    // Contact section links
    let generalSupportInquiriesEmail = URL(string:"mailto:support@bitlocal.app")!
    let reportABugEmail = URL(string:"mailto:support@bitlocal.app")!
    let suggestAFeatureEmail = URL(string:"mailto:support@bitlocal.app")!
    
    // Socials section links
    let twitterURL = URL(string:"https://twitter.com/bitlocal_app")!
    //    let nostrURL = URL(string:"")!
    
    // More from Brink 13 Labs links
    let bitcoinLivePriceChartURL = URL(string: "https://brink13labs.com")!
    let movematesMoveTogetherURL = URL(string: "https://apps.apple.com/us/app/movemates-move-together/id6748308903")!
    
    // Other section links
    let brink13LabsWebsite = URL(string: "https://brink13labs.com")!
    let bitlocalWebsite = URL(string: "https://www.bitlocal.app")!
    let privacyPolicyURL = URL(string: "https://github.com/joeycast/BitLocal.app/blob/main/Privacy_Policy.md")!
    let btcMapURL = URL(string: "https://btcmap.org/")!
    let openStreetMapURL = URL(string: "https://openstreetmap.org/copyright")!
    let bitcoinResourcesURL = URL(string: "https://www.lopp.net/bitcoin-information.html")!
    
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
                if Locale.current.region?.identifier == "US" {
                    Section(header: Text("support_bitlocal_section"),
                            footer: Text("support_bitlocal_footer")) {
                        Link(destination: supportBitLocalURL) {
                            HStack(spacing: 10) {
                                Image("hand-heart-fill")
                                    .aboutIconStyle(size: iconSize)
                                Text("support_bitlocal_button_label")
                                Spacer()
                            }
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
                }
                // More from Birnk 13 Labs section
                Section(header: Text("more_from_brink_13_Labs_section")) {
                    Link(destination: bitcoinLivePriceChartURL) {
                        HStack(spacing: 10) {
                            Image("chart-line-up-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("bitcoin_live_price_chart_button_label")
                            Spacer()
                        }
                    }
                    if Locale.current.region?.identifier == "US" {
                        Link(destination: movematesMoveTogetherURL) {
                            HStack(spacing: 10) {
                                Image("person-simple-run-bold")
                                    .aboutIconStyle(size: iconSize)
                                Text("Movemates: Move Together")
                                Spacer()
                            }
                        }
                    }
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
                    Link(destination: brink13LabsWebsite) {
                        HStack(spacing: 10) {
                            Image("compass-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("brink_13_labs_website")
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
