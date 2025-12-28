import SwiftUI

@available(iOS 17.0, *)
struct BusinessDetailsView: View {
    @Binding var submission: BusinessSubmission

    var body: some View {
        Form {
                Section {
                    TextField(text: $submission.businessDescription, axis: .vertical) {
                        Text("business_description_label")
                    }
                    .lineLimit(3...6)
                } header: {
                    Text("step_details_description_header")
                } footer: {
                    Text("step_details_optional_footer")
                }

                Section {
                    Picker(selection: $submission.osmFeatureType) {
                        ForEach(OSMFeatureType.groupedOptions, id: \.0) { group in
                            Section(LocalizedStringKey(group.0)) {
                                ForEach(group.1) { featureType in
                                    Text(LocalizedStringKey(featureType.localizedKey))
                                        .tag(featureType)
                                }
                            }
                        }
                    } label: {
                        Text("osm_feature_type_label")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("business_category_section_header")
                }

                if submission.osmFeatureType == .custom {
                    Section {
                        TextField(
                            text: $submission.osmCustomTag,
                            prompt: Text("osm_custom_tag_placeholder")
                        ) {
                            Text("osm_custom_tag_label")
                        }
                    }
                }

                Section {
                    HStack(spacing: 8) {
                        TextField(text: $submission.phoneCountryCode) {
                            Text("+1")
                        }
                        .keyboardType(.phonePad)
                        .frame(maxWidth: 60)

                        TextField(text: $submission.phoneNumber) {
                            Text("phone_number_label")
                        }
                        .keyboardType(.phonePad)
                    }

                    TextField(text: $submission.website) {
                        Text("website_label")
                    }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                } header: {
                    Text("contact_section_header")
                } footer: {
                    Text("step_details_optional_footer")
                }
            }
    }
}
