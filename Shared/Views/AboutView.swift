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
                    Text("\(appName) is an app developed by Joe Castagnaro in Nashville, TN. \(appName)'s mission is to support hyperbitcoinization by connecting people with local businesses that accept bitcoin and is my contribution to the bitcoin community. Location data displayed in \(appName) is retrieved from OpenStreetMap through the BTC Map API.")
                }
                // Contribute section
                Section(header: Text("Contribute"),
                        footer: Text("At this time, adding businesses is not supported in-app but is being considered as a feature for a future release. Until then, email us by tapping \"Suggest a Business\" above.")) {
                    Link(destination: suggestABusinessEmail) {
                        HStack(spacing: 10) {
                            Image("storefront-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("Suggest a Business")
                            Spacer()
                        }
                    }
                }
                // Contact section
                Section(header: Text("Contact")) {
                    Link(destination: generalSupportInquiriesEmail) {
                        HStack(spacing: 10) {
                            Image("paper-plane-tilt-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("General Support Inquiries")
                            Spacer()
                        }
                    }
                    Link(destination: reportABugEmail) {
                        HStack(spacing: 10) {
                            Image("bug-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("Report a Bug")
                            Spacer()
                        }
                    }
                    Link(destination: suggestAFeatureEmail) {
                        HStack(spacing: 10) {
                            Image("lightbulb-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("Suggest a Feature")
                            Spacer()
                        }
                    }
                }
                // Socials section
                Section(header: Text("Socials")) {
                    Link(destination: twitterURL) {
                        HStack(spacing: 10) {
                            Image("x-logo-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("X / Twitter")
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
                Section(header: Text("Other")) {
                    Link(destination: bitlocalWebsite) {
                        HStack(spacing: 10) {
                            Image("compass-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("BitLocal Website")
                            Spacer()
                        }
                    }
                    Link(destination: privacyPolicyURL) {
                        HStack(spacing: 10) {
                            Image("hand-palm-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("Privacy Policy")
                            Spacer()
                        }
                    }
                    Link(destination: btcMapURL) {
                        HStack(spacing: 10) {
                            Image("map-pin-line-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("BTC Map")
                            Spacer()
                        }
                    }
                    Link(destination: openStreetMapURL) {
                        HStack(spacing: 10) {
                            Image("globe-simple-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("OpenStreetMap")
                            Spacer()
                        }
                    }
                    Link(destination: bitcoinResourcesURL) {
                        HStack(spacing: 10) {
                            Image("currency-btc-fill")
                                .aboutIconStyle(size: iconSize)
                            Text("Bitcoin Resources")
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
            }
            // About page title
            // TODO: Figure out how to use the appName constant here
            .navigationTitle("About BitLocal")
            
            // Dismiss sheet when tapping Done.
            .navigationBarItems(trailing:
                Button(action: { dismiss() }) {
                    Text("Done")
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
