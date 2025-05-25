import SwiftUI

struct MainView: View {
    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentView()
        } else {
            EarlierThaniOS170View()
        }
    }
}
