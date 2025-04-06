import SwiftUI
import MapKit

struct SettingsView: View {
    @Binding var selectedMapType: MKMapType
    @Environment(\.dismiss) var dismiss
    
    // Store the enum directly
    @AppStorage("appearance") private var appearance: Appearance = .system
    
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarItems(trailing:
                                    Button("Done") {
                dismiss()
            }
            )
        }
    }
}
