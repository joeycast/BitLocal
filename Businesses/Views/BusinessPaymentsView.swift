import SwiftUI

@available(iOS 17.0, *)
struct BusinessPaymentsView: View {
    @Binding var submission: BusinessSubmission

    var body: some View {
        Form {
                Section {
                    HStack {
                        Text("payment_onchain_label")
                            .font(.body)

                        Spacer()

                        Picker(selection: $submission.acceptsOnChain) {
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

                        Picker(selection: $submission.acceptsLightning) {
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

                        Picker(selection: $submission.acceptsContactlessLightning) {
                            Text("payment_not_accepted").tag(false)
                            Text("payment_accepted").tag(true)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                } header: {
                    Text("step_payments_header")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("step_payments_footer")
                    }
                }
            }
    }

    private var canContinue: Bool {
        submission.hasAtLeastOneBitcoinPayment
    }
}
