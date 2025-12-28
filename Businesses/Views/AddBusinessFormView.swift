import SwiftUI

@available(iOS 17.0, *)
struct AddBusinessFormView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = BusinessSubmissionViewModel()

    var body: some View {
        NavigationView {
            Form {
                submitterSection
                businessInfoSection
                addressSection
                contactSection
                hoursSection
                bitcoinPaymentSection
            }
            .navigationTitle(Text("add_business_form_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("submit_button") {
                        viewModel.validateAndSubmit()
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $viewModel.showingMailComposer) {
                MailComposerView(
                    recipients: ["support@bitlocal.app"],
                    subject: viewModel.emailSubject(),
                    body: viewModel.emailBody()
                ) { result in
                    viewModel.handleMailResult(result)
                    if case .success(let mailResult) = result, mailResult == .sent {
                        dismiss()
                    }
                }
            }
            .alert("validation_error_title", isPresented: $viewModel.showingValidationErrors) {
                Button("ok_button", role: .cancel) { }
            } message: {
                Text(validationErrorMessage())
            }
        }
    }

    private var submitterSection: some View {
        Section {
            TextField(text: $viewModel.submission.submitterName) {
                Text("submitter_name_label")
            }
            TextField(text: $viewModel.submission.submitterEmail) {
                Text("submitter_email_label")
            }
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocapitalization(.none)

            Picker(selection: $viewModel.submission.relationship) {
                ForEach(BusinessSubmission.SubmitterRelationship.allCases, id: \.self) { relationship in
                    Text(LocalizedStringKey(relationship.localizedKey))
                        .tag(relationship)
                }
            } label: {
                Text("submitter_relationship_label")
            }
        } header: {
            Text("submitter_section_header")
        } footer: {
            Text("submitter_section_footer")
        }
    }

    private var businessInfoSection: some View {
        Section {
            TextField(text: $viewModel.submission.businessName) {
                Text("business_name_label")
            }
            TextField(text: $viewModel.submission.businessDescription, axis: .vertical) {
                Text("business_description_label")
            }
            .lineLimit(3...6)
        } header: {
            Text("business_info_section_header")
        }
    }

    private var addressSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(text: $viewModel.submission.streetNumber) {
                    Text("street_number_label")
                }
                .keyboardType(.numbersAndPunctuation)
                .frame(maxWidth: 80)

                TextField(text: $viewModel.submission.streetName) {
                    Text("street_name_label")
                }
            }

            TextField(text: $viewModel.submission.city) {
                Text("city_label")
            }

            TextField(text: $viewModel.submission.stateProvince) {
                Text("state_province_label")
            }

            TextField(text: $viewModel.submission.country) {
                Text("country_label")
            }

            TextField(text: $viewModel.submission.postalCode) {
                Text("postal_code_label")
            }
            .keyboardType(.numbersAndPunctuation)
        } header: {
            Text("address_section_header")
        }
    }

    private var contactSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(text: $viewModel.submission.phoneCountryCode) {
                    Text("+1")
                }
                .keyboardType(.phonePad)
                .frame(maxWidth: 60)

                TextField(text: $viewModel.submission.phoneNumber) {
                    Text("phone_number_label")
                }
                .keyboardType(.phonePad)
            }

            TextField(text: $viewModel.submission.website) {
                Text("website_label")
            }
            .keyboardType(.URL)
            .textContentType(.URL)
            .autocapitalization(.none)
        } header: {
            Text("contact_section_header")
        }
    }

    private var hoursSection: some View {
        Section {
            ForEach(WeeklyHours.Weekday.allCases, id: \.self) { day in
                let dayHours = dayHoursBinding(for: day)
                
                VStack(spacing: 0) {
                    // Header Row: Day Name + Open/Close
                    HStack {
                        Text(LocalizedStringKey(day.localizedKey))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundColor(dayHours.isOpen.wrappedValue ? .primary : .secondary)

                        Spacer()

                        Picker(selection: dayHours.isOpen) {
                            Text("hours_closed").tag(false)
                            Text("hours_open").tag(true)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .padding(.vertical, 4)

                    // Time Picker Row (Visible only if Open)
                    if dayHours.isOpen.wrappedValue {
                        
                        HStack {
                            
                            Spacer()
                            
                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_open")
                                    .font(.caption2)
                                    .textCase(.uppercase)
                                    .foregroundColor(.secondary)
                                DatePicker(selection: dayHours.openTime, displayedComponents: .hourAndMinute) {
                                    EmptyView()
                                }
                                .labelsHidden()
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 10) // Align visually with picker text

                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_close")
                                    .font(.caption2)
                                    .textCase(.uppercase)
                                    .foregroundColor(.secondary)
                                DatePicker(selection: dayHours.closeTime, displayedComponents: .hourAndMinute) {
                                    EmptyView()
                                }
                                .labelsHidden()
                            }
                            
                            Spacer()

                        }
                        .padding(.vertical, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: dayHours.isOpen.wrappedValue)
            }
        } header: {
            HStack {
                Text("business_hours_section_header")
            }
        } 
    }

    private func dayHoursBinding(for day: WeeklyHours.Weekday) -> Binding<DayHours> {
        Binding(
            get: { viewModel.submission.weeklyHours[day] },
            set: { newValue in
                viewModel.submission.weeklyHours[day] = newValue
            }
        )
    }

    private var bitcoinPaymentSection: some View {
        Section {
            HStack {
                Text("payment_onchain_label")
                    .font(.body)

                Spacer()

                Picker(selection: $viewModel.submission.acceptsOnChain) {
                    Text("payment_not_accepted").tag(false)
                    Text("payment_accepted").tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack {
                Text("payment_lightning_label")
                    .font(.body)

                Spacer()

                Picker(selection: $viewModel.submission.acceptsLightning) {
                    Text("payment_not_accepted").tag(false)
                    Text("payment_accepted").tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack {
                Text("payment_lightning_contactless_label")
                    .font(.body)

                Spacer()

                Picker(selection: $viewModel.submission.acceptsContactlessLightning) {
                    Text("payment_not_accepted").tag(false)
                    Text("payment_accepted").tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        } header: {
            Text("bitcoin_payment_section_header")
        } footer: {
            Text("bitcoin_payment_section_footer")
        }
    }

    private func validationErrorMessage() -> String {
        let errors = viewModel.submission.validationErrors()
        let errorMessages = errors.map { error in
            switch error {
            case .missingField(let field):
                return NSLocalizedString(error.localizedKey, comment: "") + ": " + NSLocalizedString(field, comment: "")
            default:
                return NSLocalizedString(error.localizedKey, comment: "")
            }
        }
        return errorMessages.joined(separator: "\n")
    }
}
