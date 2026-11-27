import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.formatting))
struct OpeningHoursAndFormattingTests {
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date!
    }

    // MARK: - OpeningHoursLiveStatus

    @Test func twentyFourSevenIsAlwaysOpen() {
        let date = makeUTCDate(year: 2026, month: 6, day: 10, hour: 3, minute: 30)
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "24/7", now: date, calendar: utcCalendar))
    }

    @Test func weekdayRangeEvaluatesOpenAndClosedBoundaries() {
        // 2026-06-10 is Wednesday
        let midDay = makeUTCDate(year: 2026, month: 6, day: 10, hour: 12, minute: 0)
        let afterClose = makeUTCDate(year: 2026, month: 6, day: 10, hour: 17, minute: 0)
        let sundayMidDay = makeUTCDate(year: 2026, month: 6, day: 14, hour: 12, minute: 0)

        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: midDay, calendar: utcCalendar))
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: afterClose, calendar: utcCalendar) == false)
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: sundayMidDay, calendar: utcCalendar) == false)
    }

    @Test func overnightHoursCarryIntoNextMorning() {
        // 2026-06-12 is Friday; 2026-06-13 is Saturday
        let fridayNight = makeUTCDate(year: 2026, month: 6, day: 12, hour: 23, minute: 30)
        let saturdayEarly = makeUTCDate(year: 2026, month: 6, day: 13, hour: 1, minute: 15)
        let saturdayMorningClosed = makeUTCDate(year: 2026, month: 6, day: 13, hour: 2, minute: 30)

        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: fridayNight, calendar: utcCalendar))
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: saturdayEarly, calendar: utcCalendar))
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: saturdayMorningClosed, calendar: utcCalendar) == false)
    }

    @Test(arguments: [nil, "   ", "by appointment"])
    func invalidOrEmptyOpeningHoursReturnFalse(raw: String?) {
        #expect(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: raw, calendar: utcCalendar) == false)
    }

    // MARK: - WeeklyHours OSM Formatting

    @Test func weeklyHoursToOSMFormatGroupsConsecutiveDays() {
        let open9 = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let close17 = Calendar.current.date(from: DateComponents(hour: 17, minute: 0))!
        let open10 = Calendar.current.date(from: DateComponents(hour: 10, minute: 0))!
        let close14 = Calendar.current.date(from: DateComponents(hour: 14, minute: 0))!

        var hours = WeeklyHours()
        for day in [WeeklyHours.Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            hours[day] = DayHours(isOpen: true, openTime: open9, closeTime: close17)
        }
        hours[.saturday] = DayHours(isOpen: true, openTime: open10, closeTime: close14)

        #expect(hours.toOSMFormat() == "Mo-Fr 09:00-17:00; Sa 10:00-14:00")
        #expect(hours.hasAnyOpen)
    }

    @Test func weeklyHoursAllClosedFormatsEmpty() {
        let hours = WeeklyHours()
        #expect(hours.toOSMFormat() == "")
        #expect(hours.hasAnyOpen == false)
    }

    // MARK: - String & UserDefaults Extensions

    @Test func displayablePhoneNumberCollapsesRepeatedSpaces() {
        #expect("  + 1   615    555-0100  ".displayablePhoneNumber() == "+1 615 555-0100")
        #expect("   ".displayablePhoneNumber() == "   ")
    }

    @Test(arguments: [
        ("https://www.BitLocal.app///", "BitLocal.app"),
        ("HTTP://example.org/cafe/", "example.org/cafe")
    ])
    func cleanedForDisplayStripsSchemeWWWAndTrailingSlashes(raw: String, expected: String) {
        #expect(raw.cleanedForDisplay() == expected)
    }

    @Test func userDefaultsSetAndGetElementsUsesReceiverSuite() throws {
        let suiteName = "ExtensionsUserDefaultsTests-\(UUID().uuidString)"
        let customDefaults = try #require(UserDefaults(suiteName: suiteName))
        customDefaults.removePersistentDomain(forName: suiteName)
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let key = "test_elements_\(UUID().uuidString)"
        let osmJSON = OsmJSON(
            changeset: nil, id: nil, lat: 1, lon: 2, tags: nil,
            timestamp: nil, type: .node, uid: nil, user: nil, version: nil,
            bounds: nil, geometry: nil, nodes: nil, members: nil
        )
        let element = Element(id: "suite-1", osmJSON: osmJSON, tags: nil, createdAt: "2026-01-01T00:00:00Z", updatedAt: nil, deletedAt: nil)

        customDefaults.setElements([element], forKey: key)

        #expect(customDefaults.getElements(forKey: key)?.map(\.id) == ["suite-1"])
        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }

    // MARK: - BTCMapDateParser

    @Test(arguments: [
        "2026-06-10T12:34:56.789Z",
        "2026-06-10T12:34:56Z",
        "2026-06-10"
    ])
    func btcMapDateParserHandlesValidFormats(rawDate: String) {
        #expect(BTCMapDateParser.parse(rawDate) != nil)
    }

    @Test func btcMapDateParserRejectsInvalidInput() {
        #expect(BTCMapDateParser.parse("not-a-date") == nil)
    }

    // MARK: - Localized Country List

    @Test func countryListLocalizesRegionsForLocale() {
        let english = CountryList.localizedCountries(for: Locale(identifier: "en_US"))
        let german = CountryList.localizedCountries(for: Locale(identifier: "de_DE"))

        #expect(english.count > 150)
        #expect(english.contains("United States"))
        #expect(english.contains("Germany"))
        #expect(german.contains("Deutschland"))
    }

    // MARK: - Salvaged Opening Hours & String Edge Cases (from PR #54)

    @Test func openingHoursParserHandlesWraparoundRangeAndSplitShifts() throws {
        let wraparound = try #require(OSMOpeningHoursParser.parseWeekSchedule("Fr-Mo 10:00-18:00"))
        let openDays = Set(wraparound.days.filter { !$0.ranges.isEmpty }.map(\.weekday))
        #expect(openDays == [.friday, .saturday, .sunday, .monday])

        let split = try #require(OSMOpeningHoursParser.parseWeekSchedule("Mo 09:00-12:00, 14:00-18:00; Tu off"))
        let monday = try #require(split.days.first { $0.weekday == .monday })
        let tuesday = try #require(split.days.first { $0.weekday == .tuesday })
        #expect(monday.ranges.count == 2)
        #expect(tuesday.ranges.isEmpty)
    }

    @Test func cleanedWebsiteURLAndPhoneCleanupHandleEdgeCases() {
        #expect("example.com/menu".cleanedWebsiteURL()?.absoluteString == "https://example.com/menu")
        #expect("https://bitlocal.app".cleanedWebsiteURL()?.absoluteString == "https://bitlocal.app")
        #expect("currency:XBT=yes".cleanedWebsiteURL() == nil)
        #expect("   ".cleanedWebsiteURL() == nil)
        let phone = "+1 (615) 555-0100".cleanedPhoneNumber()
        #expect(phone.cleaned == "+16155550100")
        #expect(phone.isValid)
    }

    // MARK: - BusinessSubmission Validation & OSM Email Body (from PR #54)

    @Test func businessSubmissionValidationReportsMissingRequiredFieldsAndAcceptsCompleteData() {
        let emptyErrors = BusinessSubmission().validationErrors()
        #expect(emptyErrors.map(\.id) == [
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
        #expect(BusinessSubmission().isValid == false)

        var valid = makeValidSubmission()
        #expect(valid.isValid)
        #expect(valid.validationErrors().isEmpty)

        valid.website = "currency:XBT=yes"
        #expect(valid.isWebsiteValidIfProvided == false)
        #expect(valid.validationErrors().map(\.id) == ["invalid_website"])
    }

    @Test func businessSubmissionAnySinglePaymentMethodSatisfiesRequirement() {
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
            #expect(submission.isValid == false)

            setter(&submission)
            #expect(submission.hasAtLeastOneBitcoinPayment)
            #expect(submission.isValid)
        }
    }

    @Test func businessSubmissionEmailBodyEmitsCorePaymentCoordinateAndCategoryTags() throws {
        var submission = makeValidSubmission()
        submission.osmFeatureType = .amenityCafe
        submission.acceptsLightning = true
        submission.acceptsOnChain = false
        submission.acceptsContactlessLightning = true
        submission.latitude = 30.25
        submission.longitude = -97.75
        submission.website = "example.com/menu"
        submission.phoneCountryCode = "+44"
        submission.phoneNumber = "2071234567"

        let lines = submission.emailBody().components(separatedBy: .newlines)
        #expect(lines.contains("addr:housenumber=21"))
        #expect(lines.contains("addr:street=Main Street"))
        #expect(lines.contains("addr:city=Austin"))
        #expect(lines.contains("currency:XBT=yes"))
        #expect(lines.contains("amenity=cafe"))
        #expect(lines.contains("payment:lightning=yes"))
        #expect(lines.contains("payment:onchain=no"))
        #expect(lines.contains("payment:lightning_contactless=yes"))
        #expect(lines.contains("contact:website=https://example.com/menu"))
        #expect(lines.contains("contact:phone=+442071234567"))
        #expect(lines.contains("=== COORDINATES ==="))

        let encoded = try JSONEncoder().encode(submission)
        let decoded = try JSONDecoder().decode(BusinessSubmission.self, from: encoded)
        #expect(decoded.emailBody() == submission.emailBody())
    }

    private func makeValidSubmission() -> BusinessSubmission {
        var submission = BusinessSubmission()
        submission.submitterName = "Satoshi"
        submission.submitterEmail = "satoshi@example.com"
        submission.relationship = .owner
        submission.businessName = "Block Cafe"
        submission.streetNumber = "21"
        submission.streetName = "Main Street"
        submission.city = "Austin"
        submission.stateProvince = "TX"
        submission.postalCode = "78701"
        submission.country = "United States"
        submission.acceptsLightning = true
        return submission
    }
}
