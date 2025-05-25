import SwiftUI
import MapKit

struct CompactSettingsPopoverView: View {
    @Binding var selectedMapType: MKMapType
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    var onDone: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 20) {

                // Map Type Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Map Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker(selection: $selectedMapType, label: EmptyView()) {
                        Label("Standard", systemImage: "map").tag(MKMapType.standard)
                        Label("Hybrid", systemImage: "globe.europe.africa.fill").tag(MKMapType.hybrid)
                    }
                    .pickerStyle(.segmented)
                }

                // Appearance Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker(selection: $appearance, label: EmptyView()) {
                        Label("System", systemImage: "circle.lefthalf.fill").tag(Appearance.system)
                        Label("Light", systemImage: "sun.max").tag(Appearance.light)
                        Label("Dark", systemImage: "moon").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }

                // Distance Unit Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Units")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker(selection: $distanceUnit, label: EmptyView()) {
                        Text("Auto").tag(DistanceUnit.auto)
                        Text("km").tag(DistanceUnit.kilometers)
                        Text("mi").tag(DistanceUnit.miles)
                    }
                    .pickerStyle(.segmented)
                }

                // Done Button
                Button(action: { onDone?() }) {
                    Text("Done")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
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
