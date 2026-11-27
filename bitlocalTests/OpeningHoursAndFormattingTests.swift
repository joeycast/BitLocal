import XCTest
@testable import bitlocal

final class OpeningHoursAndFormattingTests: XCTestCase {
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

    func testTwentyFourSevenIsAlwaysOpen() {
        // Wednesday 03:30 UTC
        let date = makeUTCDate(year: 2026, month: 6, day: 10, hour: 3, minute: 30)
        XCTAssertTrue(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "24/7", now: date, calendar: utcCalendar))
    }

    func testWeekdayRangeEvaluatesOpenAndClosedBoundaries() {
        // 2026-06-10 is Wednesday
        let midDay = makeUTCDate(year: 2026, month: 6, day: 10, hour: 12, minute: 0)
        let afterClose = makeUTCDate(year: 2026, month: 6, day: 10, hour: 17, minute: 0)
        let sundayMidDay = makeUTCDate(year: 2026, month: 6, day: 14, hour: 12, minute: 0)

        XCTAssertTrue(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: midDay, calendar: utcCalendar))
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: afterClose, calendar: utcCalendar))
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Mo-Fr 09:00-17:00", now: sundayMidDay, calendar: utcCalendar))
    }

    func testOvernightHoursCarryIntoNextMorning() {
        // 2026-06-12 is Friday; 2026-06-13 is Saturday
        let fridayNight = makeUTCDate(year: 2026, month: 6, day: 12, hour: 23, minute: 30)
        let saturdayEarly = makeUTCDate(year: 2026, month: 6, day: 13, hour: 1, minute: 15)
        let saturdayMorningClosed = makeUTCDate(year: 2026, month: 6, day: 13, hour: 2, minute: 30)

        XCTAssertTrue(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: fridayNight, calendar: utcCalendar))
        XCTAssertTrue(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: saturdayEarly, calendar: utcCalendar))
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "Fr 18:00-02:00", now: saturdayMorningClosed, calendar: utcCalendar))
    }

    func testInvalidOrEmptyOpeningHoursReturnFalse() {
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: nil, calendar: utcCalendar))
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "   ", calendar: utcCalendar))
        XCTAssertFalse(OpeningHoursLiveStatus.isOpenNow(rawOpeningHours: "by appointment", calendar: utcCalendar))
    }

    // MARK: - WeeklyHours OSM Formatting

    func testWeeklyHoursToOSMFormatGroupsConsecutiveDays() {
        let open9 = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
        let close17 = Calendar.current.date(from: DateComponents(hour: 17, minute: 0))!
        let open10 = Calendar.current.date(from: DateComponents(hour: 10, minute: 0))!
        let close14 = Calendar.current.date(from: DateComponents(hour: 14, minute: 0))!

        var hours = WeeklyHours()
        for day in [WeeklyHours.Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            hours[day] = DayHours(isOpen: true, openTime: open9, closeTime: close17)
        }
        hours[.saturday] = DayHours(isOpen: true, openTime: open10, closeTime: close14)

        XCTAssertEqual(hours.toOSMFormat(), "Mo-Fr 09:00-17:00; Sa 10:00-14:00")
        XCTAssertTrue(hours.hasAnyOpen)
    }

    func testWeeklyHoursAllClosedFormatsEmpty() {
        let hours = WeeklyHours()
        XCTAssertEqual(hours.toOSMFormat(), "")
        XCTAssertFalse(hours.hasAnyOpen)
    }

    // MARK: - String & UserDefaults Extensions

    func testDisplayablePhoneNumberCollapsesRepeatedSpaces() {
        XCTAssertEqual("  + 1   615    555-0100  ".displayablePhoneNumber(), "+1 615 555-0100")
        XCTAssertEqual("   ".displayablePhoneNumber(), "   ")
    }

    func testCleanedForDisplayStripsSchemeWWWAndTrailingSlashes() {
        XCTAssertEqual("https://www.BitLocal.app///".cleanedForDisplay(), "BitLocal.app")
        XCTAssertEqual("HTTP://example.org/cafe/".cleanedForDisplay(), "example.org/cafe")
    }

    func testUserDefaultsSetAndGetElementsUsesReceiverSuite() {
        let suiteName = "ExtensionsUserDefaultsTests-\(UUID().uuidString)"
        let customDefaults = UserDefaults(suiteName: suiteName)!
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

        XCTAssertEqual(customDefaults.getElements(forKey: key)?.map(\.id), ["suite-1"])
        XCTAssertNil(UserDefaults.standard.data(forKey: key))
    }

    // MARK: - BTCMapDateParser

    func testBTCMapDateParserHandlesFractionalBasicAndDateOnly() {
        XCTAssertNotNil(BTCMapDateParser.parse("2026-06-10T12:34:56.789Z"))
        XCTAssertNotNil(BTCMapDateParser.parse("2026-06-10T12:34:56Z"))
        XCTAssertNotNil(BTCMapDateParser.parse("2026-06-10"))
        XCTAssertNil(BTCMapDateParser.parse("not-a-date"))
    }

    // MARK: - Localized Country List

    func testCountryListLocalizesRegionsForLocale() {
        let english = CountryList.localizedCountries(for: Locale(identifier: "en_US"))
        let german = CountryList.localizedCountries(for: Locale(identifier: "de_DE"))

        XCTAssertGreaterThan(english.count, 150)
        XCTAssertTrue(english.contains("United States"))
        XCTAssertTrue(english.contains("Germany"))
        XCTAssertTrue(german.contains("Deutschland"))
    }
}
