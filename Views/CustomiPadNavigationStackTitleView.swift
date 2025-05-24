import SwiftUI

struct CustomiPadNavigationStackTitleView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("bit")
                .font(.custom("Ubuntu-LightItalic", size: 32))
                .foregroundColor(.orange)
            Text("local")
                .font(.custom("Ubuntu-MediumItalic", size: 32))
                .foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: -8)
    }
}