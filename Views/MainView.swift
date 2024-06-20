import SwiftUI

struct MainView: View {
    @ViewBuilder
    var body: some View {
        if #available(iOS 16.4, *) {
            ContentView()
        } else {
            EarlierThaniOS164View()
        }
    }
}
