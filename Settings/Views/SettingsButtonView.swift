import SwiftUI

struct SettingsButtonView: View {
    var onSettingsSelected: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            onSettingsSelected?()
        }) {
            Image(systemName: "gearshape.fill")
                .aboutIconStyle(size: 16)
        }
        .accessibilityLabel(Text("settings_label_accessibility"))
    }
}
