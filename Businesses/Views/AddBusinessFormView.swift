import SwiftUI

struct AddBusinessFormView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = BusinessSubmissionViewModel()
    @State private var currentStep: BusinessSubmissionStep = .location
    @State private var isSubmitting = false
    private let actionButtonSize: CGFloat = 56
    private let actionBarBottomPadding: CGFloat = 12
    private let actionBarSafeAreaPadding: CGFloat = 8
    private let contentBottomClearance: CGFloat = 12

    var body: some View {
        NavigationStack {
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
                            Button("back_button", systemImage: "chevron.left", action: goToPreviousStep)
                                .labelStyle(.iconOnly)
                                .buttonStyle(
                                    CircularActionButtonStyle(
                                        size: actionButtonSize,
                                        backgroundColor: Color.gray.opacity(0.7)
                                    )
                                )
                        }

                        Spacer()

                        if currentStep == .review {
                            Button("submit_button", systemImage: "paperplane.fill", action: submitForm)
                                .labelStyle(.iconOnly)
                                .buttonStyle(
                                    CircularActionButtonStyle(
                                        size: actionButtonSize,
                                        backgroundColor: (canSubmit && !isSubmitting) ? Color.accentColor : Color.gray.opacity(0.5)
                                    )
                                )
                                .disabled(!canSubmit || isSubmitting)
                        } else {
                            Button("onboarding_button_next", systemImage: "arrow.right", action: goToNextStep)
                                .labelStyle(.iconOnly)
                                .buttonStyle(
                                    CircularActionButtonStyle(
                                        size: actionButtonSize,
                                        backgroundColor: canContinue ? Color.accentColor : Color.gray.opacity(0.5)
                                    )
                                )
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
            .sheet(isPresented: $viewModel.showingMailComposer, onDismiss: {
                isSubmitting = false
            }) {
                MailComposerView(
                    recipients: ["support@bitlocal.app"],
                    subject: viewModel.emailSubject(),
                    body: viewModel.emailBody()
                ) { result in
                    isSubmitting = false
                    viewModel.handleMailResult(result)
                    if case .success(let mailResult) = result, mailResult == .sent {
                        dismiss()
                    }
                }
            }
            .alert("validation_error_title", isPresented: $viewModel.showingValidationErrors) {
            } message: {
                Text(validationErrorMessage())
            }
            .onChange(of: viewModel.showingValidationErrors) { _, isShowing in
                if !isShowing {
                    isSubmitting = false
                }
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
                            .font(.caption)
                            .foregroundStyle(step == currentStep ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 52, maxWidth: .infinity)
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
        withAnimation(BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion)) {
            currentStep = nextStep
        }
    }

    private func goToPreviousStep() {
        guard let previousStep = BusinessSubmissionStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        withAnimation(BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)) {
            currentStep = previousStep
        }
    }

    private func submitForm() {
        guard !isSubmitting else { return }
        isSubmitting = true
        viewModel.validateAndSubmit()
        if !viewModel.showingMailComposer && !viewModel.showingValidationErrors {
            isSubmitting = false
        }
    }

    private func validationErrorMessage() -> String {
        let errors = viewModel.submission.validationErrors()
        let errorMessages = errors.map { error in
            let errorText = String(localized: String.LocalizationValue(error.localizedKey))
            switch error {
            case .missingField(let field):
                let fieldText = String(localized: String.LocalizationValue(field))
                return String(localized: "\(errorText): \(fieldText)")
            default:
                return errorText
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

private struct CircularActionButtonStyle: ButtonStyle {
    let size: CGFloat
    let backgroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(backgroundColor)
            .clipShape(.circle)
            .contentShape(.circle)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
