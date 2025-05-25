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
                    Text("Map Type")
                        .font(.caption)
                    Picker(selection: $selectedMapType, label: EmptyView()) {
                        Text("Standard").tag(MKMapType.standard)
                        Text("Hybrid").tag(MKMapType.hybrid)
                    }
                    .pickerStyle(.segmented)
                }

                // Appearance Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Picker(selection: $appearanceManager.appearance, label: EmptyView()) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }

                // Distance Unit Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distance Units")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Picker(selection: $distanceUnit, label: EmptyView()) {
                        Text("Auto").tag(DistanceUnit.auto)
                        Text("mi").tag(DistanceUnit.miles)
                        Text("km").tag(DistanceUnit.kilometers)
                    }
                    .pickerStyle(.segmented)
                }

                // Done Button
                Button(action: { onDone?() }) {
                    Text("Done")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.90))
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
