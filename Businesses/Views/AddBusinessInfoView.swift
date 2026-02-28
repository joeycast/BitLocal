import SwiftUI

@available(iOS 17.0, *)
struct AddBusinessInfoView: View {
    @Environment(\.dismiss) var dismiss

    private let btcMapAddLocationURL = URL(string: "https://btcmap.org/add-location")!

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header section
                    VStack(spacing: 16) {
                        Image(systemName: "storefront.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)

                        Text("add_business_info_title")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Info cards
                    VStack(spacing: 16) {
                        InfoCard(
                            icon: "handshake.fill",
                            title: "add_business_info_data_source_title",
                            description: "add_business_info_data_source_description"
                        )

                        InfoCard(
                            icon: "person.3.fill",
                            title: "add_business_info_volunteers_title",
                            description: "add_business_info_volunteers_description"
                        )

                        InfoCard(
                            icon: "clock.fill",
                            title: "add_business_info_timing_title",
                            description: "add_business_info_timing_description"
                        )
                    }

                    // CTA Button
                    Link(destination: btcMapAddLocationURL) {
                        HStack {
                            Text("add_business_info_cta_button")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.up.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Text("add_business_info_leaving_app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("add_business_to_map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("done_button") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct InfoCard: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

@available(iOS 17.0, *)
struct AddBusinessInfoView_Previews: PreviewProvider {
    static var previews: some View {
        AddBusinessInfoView()
    }
}
