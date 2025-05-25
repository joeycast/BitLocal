import SwiftUI
import MapKit

private struct ButtonFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

struct SettingsButtonView: View {
    @Binding var selectedMapType: MKMapType
    @Binding var appearance: Appearance
    @Binding var distanceUnit: DistanceUnit
    var onSettingsSelected: (() -> Void)? = nil
    var onButtonFrameChange: ((CGRect) -> Void)? = nil

    var body: some View {
        Button(action: {
            onSettingsSelected?()
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ButtonFramePreferenceKey.self, value: proxy.frame(in: .global))
            }
        )
        .onPreferenceChange(ButtonFramePreferenceKey.self) { value in
            onButtonFrameChange?(value)
        }
    }
}
