import SwiftUI

@available(iOS 16.4, *)
struct AboutView: View {
    
    // For dismissing the SettingsView sheet
    @Environment(\.dismiss) var dismiss
    
    @State private var showingLogs = false
    
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
    
    // Settings Page
    var body: some View {
        
        NavigationView {
            Form {
                // Header section
                Section {
                    Text("\(ContentView().appName) is an app developed by Joe Castagnaro in Nashville, TN. \(ContentView().appName)'s mission is to support hyperbitcoinization by connecting people with local businesses that accept bitcoin and is my contribution to the bitcoin community. Location data displayed in \(ContentView().appName) is retrieved from OpenStreetMap through the BTC Map API.")
                }
                // Contribute section
                Section(header: Text("Contribute"), 
                        footer: Text("At this time, adding businesses is not supported in-app but is being considered as a feature for a future release. Until then, email us by tapping \"Suggest a Business\" above.")) {
                    Link(destination: suggestABusinessEmail, label: {
                        Label("Suggest a Business", systemImage: "bag")
                    })                    
                }
                // Contact section
                Section(header: Text("Contact")) {
                    Link(destination: generalSupportInquiriesEmail, label: {
                        Label("General Support Inquiries", systemImage: "paperplane")
                    })
                    Link(destination: reportABugEmail, label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    })
                    Link(destination: suggestAFeatureEmail, label: {
                        Label("Suggest a Feature", systemImage: "plus.app")
                    })                    
                }
                // Socials section
                Section(header: Text("Socials")) {
                    Link(destination: twitterURL, 
                         label: {
                        Label("X / Twitter", systemImage: "bird")    
                    })
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
                    Link(destination: bitlocalWebsite, 
                         label: {
                        Label("BitLocal Website", systemImage: "globe")
                    })
                    Link(destination: privacyPolicyURL, 
                         label: {
                        Label("Privacy Policy", systemImage: "hand.raised")    
                    })
                    Link(destination: btcMapURL,
                         label: {
                        Label("BTC Map", systemImage: "mappin.circle")
                    })
                    Link(destination: openStreetMapURL,
                         label: {
                        Label("OpenStreetMap", systemImage: "map.circle")
                    })
                    Link(destination: bitcoinResourcesURL, 
                         label: {
                        Label("Bitcoin Resources", systemImage: "bitcoinsign.circle")    
                    })
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
                                    Button("Done") {
                dismiss()
            })
        }
    }
}

// View preview
@available(iOS 16.4, *)
struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
