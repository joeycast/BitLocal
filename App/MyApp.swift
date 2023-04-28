import SwiftUI

@main
@available(iOS 16.4, *)
struct MyApp: App {
    
    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
