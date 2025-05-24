import SwiftUI
import MapKit

struct SettingsView: View {
    @Binding var selectedMapType: MKMapType
    @Environment(\.colorScheme) var systemColorScheme

    // Store the enum directly
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    var onDone: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Map Type")
                        Spacer()
                        Picker("", selection: $selectedMapType) {
                            Text("Standard").tag(MKMapType.standard)
                            Text("Satellite").tag(MKMapType.satellite)
                            Text("Hybrid").tag(MKMapType.hybrid)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                }

                Section {
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Picker("", selection: $appearance) {
                            Text("System").tag(Appearance.system)
                            Text("Light").tag(Appearance.light)
                            Text("Dark").tag(Appearance.dark)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                }

                Section {
                    HStack {
                        Text("Distance Unit")
                        Spacer()
                        Picker("", selection: $distanceUnit) {
                            ForEach(DistanceUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarItems(trailing:
                Button("Done") {
                    onDone?()
                }
            )
        }
        .id("\(appearance)-\(systemColorScheme)")
    }
}
