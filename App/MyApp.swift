import SwiftUI

@main
@available(iOS 16.4, *)
struct MyApp: App {
    
    // Add the environment property to track the app's scene phase
    @Environment(\.scenePhase) var scenePhase
    
    // Initialize your API manager
    let apiManager = APIManager()
    
    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
            // Use .onChange(of:) to react to changes in the scenePhase
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // The app has become active; trigger API call
                        apiManager.getElements { _ in
                            // Handle the fetched data
                            // Note: Ensure any UI updates are dispatched on the main thread
                        }
                    }
                }
        }
    }
}
