import SwiftUI

struct SettingsButtonView: View {
    var onSettingsSelected: (() -> Void)? = nil

    var body: some View {
        Button("settings_label_accessibility", systemImage: "gearshape.fill") {
            onSettingsSelected?()
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .foregroundStyle(.accent)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
}
