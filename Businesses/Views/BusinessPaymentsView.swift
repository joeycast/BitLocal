import SwiftUI

struct BusinessPaymentsView: View {
    @Binding var submission: BusinessSubmission

    var body: some View {
        Form {
                Section {
                    LabeledContent("payment_onchain_label") {
                        Picker("payment_onchain_label", selection: $submission.acceptsOnChain) {
                            Text("payment_not_accepted").tag(false)
                            Text("payment_accepted").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    LabeledContent("payment_lightning_label") {
                        Picker("payment_lightning_label", selection: $submission.acceptsLightning) {
                            Text("payment_not_accepted").tag(false)
                            Text("payment_accepted").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    LabeledContent("payment_lightning_contactless_label") {
                        Picker("payment_lightning_contactless_label", selection: $submission.acceptsContactlessLightning) {
                            Text("payment_not_accepted").tag(false)
                            Text("payment_accepted").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
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
}
