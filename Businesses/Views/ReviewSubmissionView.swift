import SwiftUI

@available(iOS 17.0, *)
struct ReviewSubmissionView: View {
    @Binding var submission: BusinessSubmission

    var body: some View {
        Form {
            submitterSection
            reviewSection
#if DEBUG
            Section {
                Text(submission.emailBody())
                    .font(.caption)
                    .textSelection(.enabled)
            } header: {
                Text("Debug Email Preview")
            }
#endif
        }
    }

    private var submitterSection: some View {
        Section {
            TextField(text: $submission.submitterName) {
                Text("submitter_name_label")
            }

            TextField(text: $submission.submitterEmail) {
                Text("submitter_email_label")
            }
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocapitalization(.none)

            Picker(selection: $submission.relationship) {
                ForEach(BusinessSubmission.SubmitterRelationship.allCases, id: \.self) { relationship in
                    Text(LocalizedStringKey(relationship.localizedKey))
                        .tag(relationship)
                }
            } label: {
                Text("submitter_relationship_label")
            }
        } header: {
            Text("step_review_submitter_header")
        } footer: {
            Text("step_review_submitter_footer")
        }
    }

    private var reviewSection: some View {
        Section {
            ReviewRow(label: "business_name_label", value: submission.businessName)

            if let categoryValue = categorySummaryValue() {
                ReviewRow(label: "business_category_label", value: categoryValue)
            }

            ReviewRow(
                label: "address_section_header",
                value: formatAddress()
            )

            if !submission.businessDescription.isEmpty {
                ReviewRow(label: "business_description_label", value: submission.businessDescription)
            }

            if !submission.phoneNumber.isEmpty {
                ReviewRow(
                    label: "phone_number_label",
                    value: "\(submission.phoneCountryCode) \(submission.phoneNumber)"
                )
            }

            if !submission.website.isEmpty {
                ReviewRow(label: "website_label", value: submission.website)
            }

            ReviewRow(
                label: "bitcoin_payment_section_header",
                value: formatPaymentMethods()
            )

            let hoursString = submission.weeklyHours.toOSMFormat()
            if !hoursString.isEmpty {
                ReviewRow(label: "business_hours_section_header", value: hoursString)
            }
        } header: {
            Text("step_review_summary_header")
        } footer: {
            Text("step_review_summary_footer")
        }
    }

    private func categorySummaryValue() -> String? {
        if submission.osmFeatureType == .custom {
            let custom = submission.osmCustomTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if custom.isEmpty {
                return nil
            }
            let groupLabel = NSLocalizedString("osm_feature_group_other", comment: "")
            return "\(groupLabel): \(custom)"
        }
        if submission.osmFeatureType == .unset {
            return nil
        }
        if let groupKey = OSMFeatureType.groupedOptions.first(where: { $0.1.contains(submission.osmFeatureType) })?.0 {
            let groupLabel = NSLocalizedString(groupKey, comment: "")
            let typeLabel = NSLocalizedString(submission.osmFeatureType.localizedKey, comment: "")
            return "\(groupLabel): \(typeLabel)"
        }
        return NSLocalizedString(submission.osmFeatureType.localizedKey, comment: "")
    }

    private func formatAddress() -> String {
        var parts: [String] = []
        parts.append("\(submission.streetNumber) \(submission.streetName)")
        parts.append(submission.city)
        parts.append(submission.stateProvince)
        if !submission.postalCode.isEmpty {
            parts.append(submission.postalCode)
        }
        parts.append(submission.country)
        return parts.joined(separator: ", ")
    }

    private func formatPaymentMethods() -> String {
        var methods: [String] = []
        if submission.acceptsOnChain {
            methods.append(NSLocalizedString("payment_onchain_label", comment: ""))
        }
        if submission.acceptsLightning {
            methods.append(NSLocalizedString("payment_lightning_label", comment: ""))
        }
        if submission.acceptsContactlessLightning {
            methods.append(NSLocalizedString("payment_lightning_contactless_label", comment: ""))
        }
        return methods.joined(separator: ", ")
    }
}

@available(iOS 17.0, *)
struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
