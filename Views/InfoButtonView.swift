import SwiftUI

struct InfoButtonView: View {
    @Binding var showingAbout: Bool

    var body: some View {
        Button(action: