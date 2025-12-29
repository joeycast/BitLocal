import SwiftUI

@available(iOS 17.0, *)
struct AddBusinessFormView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = BusinessSubmissionViewModel()
    @State private var currentStep: BusinessSubmissionStep = .location
    private let actionButtonSize: CGFloat = 56
    private let actionBarBottomPadding: CGFloat = 12
    private let actionBarSafeAreaPadding: CGFloat = 8
    private let contentBottomClearance: CGFloat = 12

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                stepIndicator

                ZStack(alignment: .bottom) {
                    Group {
                        switch currentStep {
                        case .location:
                            LocationSearchView(
                                submission: $viewModel.submission
                            )
                        case .details:
                            BusinessDetailsView(
                                submission: $viewModel.submission
                            )
                        case .payments:
                            BusinessPaymentsView(
                                submission: $viewModel.submission
                            )
                        case .hours:
                            BusinessHoursView(
                                submission: $viewModel.submission
                            )
                        case .review:
                            ReviewSubmissionView(
                                submission: $viewModel.submission
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: contentBottomInset)
                    }

                    HStack {
                        if currentStep != .location {
                            Button(action: { goToPreviousStep() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: actionButtonSize, height: actionButtonSize)
                                    .background(Color.gray.opacity(0.7))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            }
                        }

                        Spacer()

                        if currentStep == .review {
                            Button(action: { submitForm() }) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: actionButtonSize, height: actionButtonSize)
                                    .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.5))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            }
                            .disabled(!canSubmit)
                        } else {
                            Button(action: { goToNextStep() }) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: actionButtonSize, height: actionButtonSize)
                                    .background(canContinue ? Color.accentColor : Color.gray.opacity(0.5))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            }
                            .disabled(!canContinue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, actionBarBottomPadding)
                    .safeAreaPadding(.bottom, actionBarSafeAreaPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button") {
                        dismiss()
                    }
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private var stepIndicator: some View {
        VStack(spacing: 4) {
            // Progress circles and lines
            HStack(spacing: 0) {
                ForEach(BusinessSubmissionStep.allCases, id: \.self) { step in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)

                        Text(step.title)
                            .font(.caption2)
                            .foregroundColor(step == currentStep ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                            .lineLimit(2)
                    }

                    if step != BusinessSubmissionStep.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .padding(.bottom, 20)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func goToNextStep() {
        guard let nextStep = BusinessSubmissionStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        withAnimation {
            currentStep = nextStep
        }
    }

    private func goToPreviousStep() {
        guard let previousStep = BusinessSubmissionStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        withAnimation {
            currentStep = previousStep
        }
    }

    private func submitForm() {
        viewModel.validateAndSubmit()
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

    private var canContinue: Bool {
        switch currentStep {
        case .location:
            return viewModel.submission.latitude != nil && viewModel.submission.longitude != nil
        case .details:
            return true // Optional step
        case .payments:
            return viewModel.submission.hasAtLeastOneBitcoinPayment
        case .hours:
            return true // Optional step
        case .review:
            return false // Uses canSubmit
        }
    }

    private var canSubmit: Bool {
        !viewModel.submission.submitterName.isEmpty &&
        viewModel.submission.isValidEmail(viewModel.submission.submitterEmail)
    }

    private var contentBottomInset: CGFloat {
        actionButtonSize + actionBarBottomPadding + actionBarSafeAreaPadding + contentBottomClearance
    }
}
