import SwiftUI
import MapKit

struct CompactSettingsPopoverView: View {
    @Binding var selectedMapType: MKMapType
    @EnvironmentObject var appearanceManager: AppearanceManager
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    var onDone: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 20) {

                // Map Type Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("map_type_label")
                        .font(.caption)
                    Picker(selection: $selectedMapType, label: EmptyView()) {
                        Text("map_type_standard").tag(MKMapType.standard)
                        Text("map_type_hybrid").tag(MKMapType.hybrid)
                    }
                    .pickerStyle(.segmented)
                }

                // Appearance Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("theme_label")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Picker(selection: $appearanceManager.appearance, label: EmptyView()) {
                        Text("theme_system").tag(Appearance.system)
                        Text("theme_light").tag(Appearance.light)
                        Text("theme_dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }

                // Distance Unit Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("distance_units_label")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Picker(selection: $distanceUnit, label: EmptyView()) {
                        Text("distance_units_auto").tag(DistanceUnit.auto)
                        Text("distance_units_miles").tag(DistanceUnit.miles)
                        Text("distance_units_kilometers").tag(DistanceUnit.kilometers)
                    }
                    .pickerStyle(.segmented)
                }

                // Done Button
                Button(action: { onDone?() }) {
                    Text("done_button")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.90))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 6)
            .frame(width: 300)
        }
        .frame(width: 350, height: 360) // match or slightly larger than the inner frame
    }
}
