import Foundation

enum BusinessSubmissionStep: Int, CaseIterable {
    case location = 0
    case details = 1
    case payments = 2
    case hours = 3
    case review = 4

    var title: String {
        switch self {
        case .location:
            return NSLocalizedString("step_location_title", comment: "")
        case .details:
            return NSLocalizedString("step_details_title", comment: "")
        case .payments:
            return NSLocalizedString("step_payments_title", comment: "")
        case .hours:
            return NSLocalizedString("step_hours_title", comment: "")
        case .review:
            return NSLocalizedString("step_review_title", comment: "")
        }
    }

    var stepNumber: Int {
        return rawValue + 1
    }

    var isOptional: Bool {
        return self == .hours
    }

    func canProceed(with submission: BusinessSubmission) -> Bool {
        switch self {
        case .location:
            // Must have business name and address fields
            return !submission.businessName.isEmpty &&
                   !submission.streetNumber.isEmpty &&
                   !submission.streetName.isEmpty &&
                   !submission.city.isEmpty &&
                   !submission.stateProvince.isEmpty &&
                   !submission.country.isEmpty
        case .details:
            // Optional step, always can proceed
            return true
        case .payments:
            // Must have at least one payment method
            return submission.hasAtLeastOneBitcoinPayment
        case .hours:
            // Optional step, always can proceed
            return true
        case .review:
            // Must have submitter info
            return !submission.submitterName.isEmpty &&
                   submission.isValidEmail(submission.submitterEmail)
        }
    }
}
