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
        "New Business Submission: \(submission.businessName)"
    }

    func emailBody() -> String {
        var lines: [String] = []

        // Submitter info (not OSM tags, just context)
        lines.append("=== SUBMITTER INFORMATION ===")
        lines.append("Name: \(submission.submitterName)")
        lines.append("Email: \(submission.submitterEmail)")
        lines.append("Relationship: \(submission.relationship.rawValue)")
        lines.append("")

        // OpenStreetMap tags
        lines.append("=== OPENSTREETMAP TAGS ===")

        // Address
        if !submission.city.isEmpty {
            lines.append("addr:city=\(submission.city)")
        }
        if !submission.streetNumber.isEmpty {
            lines.append("addr:housenumber=\(submission.streetNumber)")
        }
        if !submission.postalCode.isEmpty {
            lines.append("addr:postcode=\(submission.postalCode)")
        }
        if !submission.stateProvince.isEmpty {
            lines.append("addr:state=\(submission.stateProvince)")
        }
        if !submission.streetName.isEmpty {
            lines.append("addr:street=\(submission.streetName)")
        }

        // Add check_date (today's date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        lines.append("check_date=\(today)")
        lines.append("check_date:currency:XBT=\(today)")

        // Contact info
        if !submission.phoneNumber.isEmpty {
            let fullPhone = "\(submission.phoneCountryCode)\(submission.phoneNumber)"
            lines.append("contact:phone=\(fullPhone)")
        }
        if let websiteURL = submission.website.cleanedWebsiteURL() {
            lines.append("contact:website=\(websiteURL.absoluteString)")
        }

        // Currency and payment
        lines.append("currency:XBT=yes")

        // Description
        if !submission.businessDescription.isEmpty {
            lines.append("description=\(submission.businessDescription)")
        }

        // Business name
        lines.append("name=\(submission.businessName)")

        // Opening hours
        let hoursString = submission.weeklyHours.toOSMFormat()
        if !hoursString.isEmpty {
            lines.append("opening_hours=\(hoursString)")
        }

        // Payment methods
        lines.append("payment:lightning=\(submission.acceptsLightning ? "yes" : "no")")
        if submission.acceptsContactlessLightning {
            lines.append("payment:lightning_contactless=yes")
        }
        lines.append("payment:onchain=\(submission.acceptsOnChain ? "yes" : "no")")

        return lines.joined(separator: "\n")
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
