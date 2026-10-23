import XCTest
@testable import bitlocal

final class BusinessSubmissionValidationTests: XCTestCase {
    func testCompleteSubmissionIsValid() {
        let submission = makeValidSubmission()

        XCTAssertTrue(submission.isValid)
        XCTAssertTrue(submission.validationErrors().isEmpty)
    }

    func testEmptySubmissionReportsEveryRequiredField() {
        let errors = BusinessSubmission().validationErrors()

        XCTAssertEqual(errors.map(\.id), [
            "missing_submitter_name_label",
            "invalid_email",
            "missing_business_name_label",
            "missing_street_number_label",
            "missing_street_name_label",
            "missing_city_label",
            "missing_state_province_label",
            "missing_country_label",
            "no_bitcoin_payment"
        ])
        XCTAssertFalse(BusinessSubmission().isValid)
    }

    func testAnySinglePaymentMethodSatisfiesPaymentRequirement() {
        let setters: [(inout BusinessSubmission) -> Void] = [
            { $0.acceptsOnChain = true },
            { $0.acceptsLightning = true },
            { $0.acceptsContactlessLightning = true }
        ]

        for setter in setters {
            var submission = makeValidSubmission()
            submission.acceptsOnChain = false
            submission.acceptsLightning = false
            submission.acceptsContactlessLightning = false
            XCTAssertFalse(submission.isValid)

            setter(&submission)
            XCTAssertTrue(submission.hasAtLeastOneBitcoinPayment)
            XCTAssertTrue(submission.isValid)
        }
    }

    func testEmailValidation() {
        let submission = BusinessSubmission()

        for valid in ["joe@example.com", "first.last+tag@sub.example.co.uk", "A_B%c-d@x-y.io"] {
            XCTAssertTrue(submission.isValidEmail(valid), valid)
        }
        for invalid in ["", "joe", "joe@", "joe@example", "@example.com", "joe@example.c", "joe example@x.com"] {
            XCTAssertFalse(submission.isValidEmail(invalid), invalid)
        }
    }

    func testWebsiteIsOptionalButMustBeUsableWhenProvided() {
        var submission = makeValidSubmission()

        submission.website = ""
        XCTAssertTrue(submission.isWebsiteValidIfProvided)

        submission.website = "example.com"
        XCTAssertTrue(submission.isWebsiteValidIfProvided)

        submission.website = "currency:XBT=yes"
        XCTAssertFalse(submission.isWebsiteValidIfProvided)
        XCTAssertFalse(submission.isValid)
        XCTAssertEqual(submission.validationErrors().map(\.id), ["invalid_website"])
    }

    func testOptionalFieldsDoNotAffectValidity() {
        var submission = makeValidSubmission()
        submission.postalCode = ""
        submission.phoneNumber = ""
        submission.businessDescription = ""
        submission.latitude = nil
        submission.longitude = nil

        XCTAssertTrue(submission.isValid)
    }

    func testValidationErrorLocalizedKeys() {
        XCTAssertEqual(BusinessSubmission.ValidationError.missingField("x").localizedKey, "validation_error_missing_field")
        XCTAssertEqual(BusinessSubmission.ValidationError.invalidEmail.localizedKey, "validation_error_invalid_email")
        XCTAssertEqual(BusinessSubmission.ValidationError.invalidWebsite.localizedKey, "validation_error_invalid_website")
        XCTAssertEqual(BusinessSubmission.ValidationError.noBitcoinPaymentMethod.localizedKey, "validation_error_no_bitcoin_payment")
    }

    func testSubmissionRoundTripsThroughCodable() throws {
        var submission = makeValidSubmission()
        submission.relationship = .customer
        submission.osmFeatureType = .shopBakery
        submission.weeklyHours.monday.isOpen = true

        let data = try JSONEncoder().encode(submission)
        let decoded = try JSONDecoder().decode(BusinessSubmission.self, from: data)

        XCTAssertEqual(decoded.emailBody(), submission.emailBody())
        XCTAssertEqual(decoded.relationship, .customer)
        XCTAssertEqual(decoded.osmFeatureType, .shopBakery)
        XCTAssertEqual(decoded.weeklyHours, submission.weeklyHours)
    }
}

final class BusinessSubmissionEmailBodyTests: XCTestCase {
    func testIncludesSubmitterAddressAndCoreTags() {
        let lines = bodyLines(makeValidSubmission())

        XCTAssertTrue(lines.contains("Name: Satoshi"))
        XCTAssertTrue(lines.contains("Email: satoshi@example.com"))
        XCTAssertTrue(lines.contains("Relationship: Owner"))
        XCTAssertTrue(lines.contains("addr:housenumber=21"))
        XCTAssertTrue(lines.contains("addr:street=Main Street"))
        XCTAssertTrue(lines.contains("addr:city=Austin"))
        XCTAssertTrue(lines.contains("addr:state=TX"))
        XCTAssertTrue(lines.contains("addr:postcode=78701"))
        XCTAssertTrue(lines.contains("currency:XBT=yes"))
        XCTAssertTrue(lines.contains("name=Block Cafe"))
    }

    func testCheckDatesUseToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let lines = bodyLines(makeValidSubmission())

        XCTAssertTrue(lines.contains("check_date=\(today)"))
        XCTAssertTrue(lines.contains("check_date:currency:XBT=\(today)"))
    }

    func testPaymentTags() {
        var submission = makeValidSubmission()
        submission.acceptsLightning = true
        submission.acceptsOnChain = false
        submission.acceptsContactlessLightning = false

        var lines = bodyLines(submission)
        XCTAssertTrue(lines.contains("payment:lightning=yes"))
        XCTAssertTrue(lines.contains("payment:onchain=no"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("payment:lightning_contactless") })

        submission.acceptsOnChain = true
        submission.acceptsContactlessLightning = true
        lines = bodyLines(submission)
        XCTAssertTrue(lines.contains("payment:onchain=yes"))
        XCTAssertTrue(lines.contains("payment:lightning_contactless=yes"))
    }

    func testCoordinatesSectionOnlyAppearsWithBothCoordinates() {
        var submission = makeValidSubmission()
        submission.latitude = 30.25
        submission.longitude = -97.75

        var lines = bodyLines(submission)
        XCTAssertTrue(lines.contains("=== COORDINATES ==="))
        XCTAssertTrue(lines.contains("Latitude: 30.25"))
        XCTAssertTrue(lines.contains("Longitude: -97.75"))
        XCTAssertTrue(lines.contains("OSM URL: https://www.openstreetmap.org/?mlat=30.25&mlon=-97.75#map=18/30.25/-97.75"))

        submission.longitude = nil
        lines = bodyLines(submission)
        XCTAssertFalse(lines.contains("=== COORDINATES ==="))
    }

    func testOptionalContactAndDescriptionTags() {
        var submission = makeValidSubmission()

        var lines = bodyLines(submission)
        XCTAssertFalse(lines.contains { $0.hasPrefix("contact:phone=") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("contact:website=") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("description=") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("opening_hours=") })

        submission.phoneCountryCode = "+44"
        submission.phoneNumber = "2071234567"
        submission.website = "example.com/menu"
        submission.businessDescription = "Coffee and pastries"
        submission.weeklyHours.saturday = DayHours(
            isOpen: true,
            openTime: Calendar.current.date(from: DateComponents(hour: 8, minute: 0))!,
            closeTime: Calendar.current.date(from: DateComponents(hour: 12, minute: 0))!
        )

        lines = bodyLines(submission)
        XCTAssertTrue(lines.contains("contact:phone=+442071234567"))
        XCTAssertTrue(lines.contains("contact:website=https://example.com/menu"))
        XCTAssertTrue(lines.contains("description=Coffee and pastries"))
        XCTAssertTrue(lines.contains("opening_hours=Sa 08:00-12:00"))
    }

    func testKnownFeatureTypeEmitsKeyValueTag() {
        var submission = makeValidSubmission()
        submission.osmFeatureType = .amenityCafe
        XCTAssertTrue(bodyLines(submission).contains("amenity=cafe"))

        submission.osmFeatureType = .healthcareOptometrist
        XCTAssertTrue(bodyLines(submission).contains("healthcare=optometrist"))
    }

    func testUnsetFeatureTypeEmitsNoCategoryTag() {
        var submission = makeValidSubmission()
        submission.osmFeatureType = .unset
        submission.osmCustomTag = "shop=ignored"

        let lines = bodyLines(submission)

        XCTAssertFalse(lines.contains("shop=ignored"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("custom_category=") })
    }

    func testCustomFeatureTypeHandling() {
        var submission = makeValidSubmission()
        submission.osmFeatureType = .custom

        submission.osmCustomTag = "  craft=roaster  "
        XCTAssertTrue(bodyLines(submission).contains("craft=roaster"))

        submission.osmCustomTag = "coffee roaster"
        XCTAssertTrue(bodyLines(submission).contains("custom_category=coffee roaster"))

        submission.osmCustomTag = "   "
        let lines = bodyLines(submission)
        XCTAssertFalse(lines.contains { $0.hasPrefix("custom_category=") })
    }

    private func bodyLines(_ submission: BusinessSubmission) -> [String] {
        submission.emailBody().components(separatedBy: "\n")
    }
}

final class OSMFeatureTypeTests: XCTestCase {
    func testOnlyUnsetAndCustomLackOSMTags() {
        for type in OSMFeatureType.allCases {
            if type == .unset || type == .custom {
                XCTAssertNil(type.osmTagKey, type.rawValue)
                XCTAssertNil(type.osmTagValue, type.rawValue)
            } else {
                XCTAssertNotNil(type.osmTagKey, type.rawValue)
                XCTAssertNotNil(type.osmTagValue, type.rawValue)
            }
        }
    }

    func testTagKeyMatchesCaseNamePrefix() {
        for type in OSMFeatureType.allCases {
            guard let key = type.osmTagKey else { continue }
            let prefix = String(type.rawValue.prefix { $0.isLowercase })
            XCTAssertEqual(key, prefix, type.rawValue)
        }
    }

    func testLocalizedKeyFollowsTagNaming() {
        for type in OSMFeatureType.allCases {
            guard let key = type.osmTagKey, let value = type.osmTagValue else { continue }
            XCTAssertEqual(type.localizedKey, "osm_feature_type_\(key)_\(value)", type.rawValue)
        }
    }

    func testTagPairsAreUnique() {
        let pairs = OSMFeatureType.allCases.compactMap { type -> String? in
            guard let key = type.osmTagKey, let value = type.osmTagValue else { return nil }
            return "\(key)=\(value)"
        }

        XCTAssertEqual(pairs.count, Set(pairs).count)
    }

    func testGroupedOptionsListEveryTypeExactlyOnce() {
        let grouped = OSMFeatureType.groupedOptions.flatMap { $0.1 }

        XCTAssertEqual(grouped.count, OSMFeatureType.allCases.count)
        XCTAssertEqual(Set(grouped), Set(OSMFeatureType.allCases))
    }

    func testTypesSitInTheGroupForTheirTagKey() {
        for (group, types) in OSMFeatureType.groupedOptions {
            for type in types {
                guard let key = type.osmTagKey else { continue }
                XCTAssertEqual(group, "osm_feature_group_\(key)", type.rawValue)
            }
        }
    }
}

final class BusinessSubmissionStepTests: XCTestCase {
    func testStepNumbersAndOptionality() {
        XCTAssertEqual(BusinessSubmissionStep.allCases.map(\.stepNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(BusinessSubmissionStep.allCases.filter(\.isOptional), [.hours])
    }

    func testLocationStepNeedsNameAndAddress() {
        var submission = makeValidSubmission()
        XCTAssertTrue(BusinessSubmissionStep.location.canProceed(with: submission))

        let clearers: [(inout BusinessSubmission) -> Void] = [
            { $0.businessName = "" },
            { $0.streetNumber = "" },
            { $0.streetName = "" },
            { $0.city = "" },
            { $0.stateProvince = "" },
            { $0.country = "" }
        ]
        for clear in clearers {
            submission = makeValidSubmission()
            clear(&submission)
            XCTAssertFalse(BusinessSubmissionStep.location.canProceed(with: submission))
        }

        submission = makeValidSubmission()
        submission.postalCode = ""
        XCTAssertTrue(BusinessSubmissionStep.location.canProceed(with: submission))
    }

    func testOptionalStepsAlwaysProceed() {
        let empty = BusinessSubmission()

        XCTAssertTrue(BusinessSubmissionStep.details.canProceed(with: empty))
        XCTAssertTrue(BusinessSubmissionStep.hours.canProceed(with: empty))
    }

    func testPaymentsStepNeedsAPaymentMethod() {
        var submission = BusinessSubmission()
        XCTAssertFalse(BusinessSubmissionStep.payments.canProceed(with: submission))

        submission.acceptsContactlessLightning = true
        XCTAssertTrue(BusinessSubmissionStep.payments.canProceed(with: submission))
    }

    func testReviewStepNeedsSubmitterNameAndValidEmail() {
        var submission = BusinessSubmission()
        submission.submitterName = "Satoshi"
        submission.submitterEmail = "not-an-email"
        XCTAssertFalse(BusinessSubmissionStep.review.canProceed(with: submission))

        submission.submitterEmail = "satoshi@example.com"
        XCTAssertTrue(BusinessSubmissionStep.review.canProceed(with: submission))

        submission.submitterName = ""
        XCTAssertFalse(BusinessSubmissionStep.review.canProceed(with: submission))
    }

    func testStepThatPassesEveryGateMakesAValidSubmission() {
        let submission = makeValidSubmission()

        XCTAssertTrue(BusinessSubmissionStep.allCases.allSatisfy { $0.canProceed(with: submission) })
        XCTAssertTrue(submission.isValid)
    }
}

final class BusinessSubmissionViewModelTests: XCTestCase {
    func testEmailSubjectIncludesTrimmedBusinessName() {
        let viewModel = BusinessSubmissionViewModel()
        viewModel.submission.businessName = "  Block Cafe  "

        let subject = viewModel.emailSubject()

        XCTAssertTrue(subject.contains("Block Cafe"))
        XCTAssertFalse(subject.contains("  Block Cafe"))
    }

    func testBlankBusinessNameUsesGenericSubject() {
        let viewModel = BusinessSubmissionViewModel()
        let generic = viewModel.emailSubject()

        viewModel.submission.businessName = "   "

        XCTAssertEqual(viewModel.emailSubject(), generic)
        XCTAssertFalse(generic.isEmpty)
    }

    func testEmailBodyDelegatesToSubmission() {
        let viewModel = BusinessSubmissionViewModel()
        viewModel.submission = makeValidSubmission()

        XCTAssertEqual(viewModel.emailBody(), viewModel.submission.emailBody())
    }

    func testInvalidSubmissionShowsValidationErrorsWithoutOpeningMail() {
        let viewModel = BusinessSubmissionViewModel()

        viewModel.validateAndSubmit()

        XCTAssertTrue(viewModel.showingValidationErrors)
        XCTAssertFalse(viewModel.showingMailComposer)
    }
}

final class BusinessSubmissionLocalizationTests: XCTestCase {
    func testEveryUserFacingKeyHasATranslation() {
        var keys: [String] = []
        keys += OSMFeatureType.allCases.map(\.localizedKey)
        keys += OSMFeatureType.groupedOptions.map { $0.0 }
        keys += BusinessSubmission.SubmitterRelationship.allCases.map(\.localizedKey)
        keys += WeeklyHours.Weekday.allCases.map(\.localizedKey)
        keys += [
            BusinessSubmission.ValidationError.missingField("").localizedKey,
            BusinessSubmission.ValidationError.invalidEmail.localizedKey,
            BusinessSubmission.ValidationError.invalidWebsite.localizedKey,
            BusinessSubmission.ValidationError.noBitcoinPaymentMethod.localizedKey
        ]
        keys += BusinessSubmission().validationErrors().compactMap { error in
            if case .missingField(let field) = error { return field }
            return nil
        }

        let missingMarker = "__missing_localization__"
        for key in keys {
            let value = Bundle.main.localizedString(forKey: key, value: missingMarker, table: nil)
            XCTAssertNotEqual(value, missingMarker, "Missing localization for \(key)")
        }
    }

    func testStepTitlesAreLocalized() {
        for step in BusinessSubmissionStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.title.hasPrefix("step_"), "Missing localization for \(step)")
        }
    }
}

private func makeValidSubmission() -> BusinessSubmission {
    var submission = BusinessSubmission()
    submission.submitterName = "Satoshi"
    submission.submitterEmail = "satoshi@example.com"
    submission.businessName = "Block Cafe"
    submission.streetNumber = "21"
    submission.streetName = "Main Street"
    submission.city = "Austin"
    submission.stateProvince = "TX"
    submission.country = "United States"
    submission.postalCode = "78701"
    submission.acceptsLightning = true
    return submission
}
