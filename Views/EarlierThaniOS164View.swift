import SwiftUI

struct EarlierThaniOS164View: View {
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
                
                Text("BitLocal Requires iOS 16.4 or Later")   
                    .font(.headline)
                
                Text("")
                
                Text("Open Settings > General > Software Update to update.")
                
                Spacer()
                Spacer()
                
                Button(action: {
                    openSettings()
                }) {
                    Text("Open Settings")
                        .font(.headline)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.orange) // Set background color to orange
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

struct EarlierThaniOS164View_Previews: PreviewProvider {
    static var previews: some View {
        EarlierThaniOS164View()
    }
}
