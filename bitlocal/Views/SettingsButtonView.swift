import SwiftUI

struct SettingsButtonView: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        Button(action: {
            showingSettings.toggle()
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 18))
                .foregroundColor(.orange)
        }
        .frame(width: 44)
        .offset(x: -7, y: +2)
    }
}
