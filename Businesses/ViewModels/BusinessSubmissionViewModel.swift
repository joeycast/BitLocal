import SwiftUI
import MessageUI

@available(iOS 17.0, *)
class BusinessSubmissionViewModel: ObservableObject {
    @Published var submission = BusinessSubmission()
    @Published var showingValidationErrors = false
    @Published var showingMailComposer = false
    @Published var mailComposeResult: Result<MFMailComposeResult, Error>?
    @Published var isSubmitting = false

    func validateAndSubmit() {
        let errors = submission.validationErrors()

        if errors.isEmpty {
            generateEmailAndPresent()
        } else {
            showingValidationErrors = true
        }
    }

    private func generateEmailAndPresent() {
        guard MFMailComposeViewController.canSendMail() else {
            // Fallback to mailto: URL
            openMailtoURL()
            return
        }

        showingMailComposer = true
    }

    func emailSubject() -> String {
        let name = submission.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return NSLocalizedString("New BitLocal Business Submission", comment: "Email subject for a new business submission without a business name")
        }
        return String(
            format: NSLocalizedString(
                "New BitLocal Business Submission: %@",
                comment: "Email subject for a new business submission with the business name"
            ),
            name
        )
    }

    func emailBody() -> String {
        submission.emailBody()
    }

    private func openMailtoURL() {
        let subject = emailSubject().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = emailBody().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:support@bitlocal.app?subject=\(subject)&body=\(body)") {
            UIApplication.shared.open(url)
        }
    }

    func handleMailResult(_ result: Result<MFMailComposeResult, Error>) {
        mailComposeResult = result
        showingMailComposer = false
    }
}
