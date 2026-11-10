import SwiftUI
import BitLocalDesign

struct SettingsButtonView: View {
    enum Style {
        /// A bare glyph, for places that already draw their own chrome.
        case plain
        /// A gear on a filled disc, the size of the header's other controls.
        case circle
    }

    var onSettingsSelected: (() -> Void)? = nil
    var style: Style = .plain

    var body: some View {
        Button(action: {
            onSettingsSelected?()
        }) {
            switch style {
            case .plain:
                Image(systemName: "gearshape.fill")
                    .aboutIconStyle(size: 16)
            case .circle:
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BrandColor.brandInk)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .frame(width: LayoutMetrics.minimumHitTarget, height: LayoutMetrics.minimumHitTarget)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("settings_label_accessibility"))
    }
}
