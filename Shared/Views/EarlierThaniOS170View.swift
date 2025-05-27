import SwiftUI

struct EarlierThaniOS170View: View {
    var body: some View {
        ZStack{
            // Support system light/dark mode
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                Image("BitLocalAppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit) // Maintain aspect ratio
                    .frame(width: 150, height: 150) // Set desired size
                    .padding() // Add padding around the image
                
                Text(LocalizedStringKey("version_requirement_title"))
                    .font(.headline)
                    .padding(.bottom, 16)

                Text(LocalizedStringKey("version_requirement_update_instruction"))
                
                Spacer()
                Spacer()
                
                Button(action: {
                    openSettings()
                }) {
                    Text(LocalizedStringKey("open_settings_button"))
                        .font(.headline)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.accentColor) // Set background color to orange
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .padding()
    }
    
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

struct EarlierThaniOS170View_Previews: PreviewProvider {
    static var previews: some View {
        EarlierThaniOS170View()
    }
}
