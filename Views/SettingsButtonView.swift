import SwiftUI
import MapKit

struct SettingsButtonView: View {
    @Binding var selectedMapType: MKMapType

    @State private var showingSettings = false
    var onSettingsSelected: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Button(action: {
                withAnimation {
                    showingSettings.toggle()
                }
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            .frame(width: 44)
            .offset(x: -7, y: +2)

            if showingSettings {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { showingSettings = false }
                    }

                VStack {
                    SettingsView(
                        selectedMapType: $selectedMapType,
                        onDone: { showingSettings = false }
                    )
                    .frame(width: 340, height: 340)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .shadow(radius: 16)
                    )
                }
                .transition(.scale)
            }
        }
    }
}

struct SettingsButtonView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsButtonView(selectedMapType: .constant(.standard))
    }
}
