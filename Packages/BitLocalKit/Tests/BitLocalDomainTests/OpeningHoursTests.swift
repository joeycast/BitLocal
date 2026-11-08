import Foundation
import Testing
@testable import BitLocalDomain

@Suite("OpeningHours")
struct OpeningHoursTests {
    typealias Day = OpeningHours.Weekday

    @Test func parsesWeekdaysAndOff() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 09:00-17:00; Sa 10:00-14:00; Su off"))
        #expect(hours[.monday] == [.init(start: 540, end: 1020)])
        #expect(hours[.saturday] == [.init(start: 600, end: 840)])
        #expect(hours[.sunday].isEmpty)
    }

    @Test func parsesTwentyFourSeven() throws {
        let hours = try #require(OpeningHours.parse("24/7"))
        #expect(hours.isAlwaysOpen)
        #expect(hours.status(weekday: .wednesday, minute: 200) == .open(closesAt: nil))
    }

    @Test func parsesSplitRangesListsAndWrappingDayRanges() throws {
        let hours = try #require(OpeningHours.parse("Mo,We 08:00-12:00,13:00-18:00; Sa-Mo 10:00-12:00"))
        #expect(hours[.wednesday].count == 2)
        #expect(hours[.sunday] == [.init(start: 600, end: 720)])
        // The later rule wins for Monday, as in OSM.
        #expect(hours[.monday] == [.init(start: 600, end: 720)])
        #expect(hours[.tuesday].isEmpty)
    }

    @Test func rulesWithoutDaysApplyToEveryDay() throws {
        let hours = try #require(OpeningHours.parse("07:00-19:00"))
        #expect(Day.allCases.allSatisfy { hours[$0] == [.init(start: 420, end: 1140)] })
    }

    @Test func ignoresPublicHolidayRules() throws {
        let hours = try #require(OpeningHours.parse("Mo-Su 10:00-20:00; PH off"))
        #expect(hours[.friday] == [.init(start: 600, end: 1200)])
    }

    @Test func rejectsUnsupportedSyntax() {
        #expect(OpeningHours.parse(nil) == nil)
        #expect(OpeningHours.parse("") == nil)
        #expect(OpeningHours.parse("Mo-Fr 18:00+") == nil)
        #expect(OpeningHours.parse("\"call ahead\"") == nil)
        #expect(OpeningHours.parse("Jan-Mar Mo 10:00-12:00") == nil)
        #expect(OpeningHours.parse("sunrise-sunset") == nil)
    }

    @Test func openStatusReportsClosingTime() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 09:00-17:00"))
        #expect(hours.status(weekday: .tuesday, minute: 600) == .open(closesAt: 1020))
        #expect(hours.status(weekday: .tuesday, minute: 1020) == .closed(opensAt: 540, daysAhead: 1))
        #expect(hours.status(weekday: .tuesday, minute: 300) == .closed(opensAt: 540, daysAhead: 0))
    }

    @Test func closedOverTheWeekendPointsToMonday() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 09:00-17:00"))
        #expect(hours.status(weekday: .saturday, minute: 600) == .closed(opensAt: 540, daysAhead: 2))
    }

    @Test func overnightRangesCarryIntoTheNextDay() throws {
        let hours = try #require(OpeningHours.parse("Fr-Sa 18:00-02:00"))
        #expect(hours.status(weekday: .friday, minute: 23 * 60) == .open(closesAt: 120))
        #expect(hours.status(weekday: .saturday, minute: 60) == .open(closesAt: 120))
        #expect(hours.status(weekday: .sunday, minute: 60) == .open(closesAt: 120))
        #expect(hours.status(weekday: .sunday, minute: 180) == .closed(opensAt: 1080, daysAhead: 5))
    }

    @Test func neverOpen() throws {
        let hours = try #require(OpeningHours.parse("Mo-Su off"))
        #expect(hours.status(weekday: .monday, minute: 0) == .closed(opensAt: nil, daysAhead: nil))
    }

    @Test func statusFromDateUsesTheCalendar() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 09:00-17:00"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        // Wednesday 2026-11-11 10:30 in Chicago.
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10, minute: 30))!
        #expect(hours.status(at: date, calendar: calendar) == .open(closesAt: 1020))
    }

    @Test func weekdayCalendarMapping() {
        #expect(Day(calendarWeekday: 1) == .sunday)
        #expect(Day(calendarWeekday: 2) == .monday)
        #expect(Day.allCases.allSatisfy { Day(calendarWeekday: $0.calendarWeekday) == $0 })
    }

    @Test func weekSummaryMergesIdenticalNeighbours() throws {
        let hours = try #require(OpeningHours.parse("Mo-Fr 09:00-17:00; Sa 10:00-14:00; Su off"))
        let summary = hours.weekSummary
        #expect(summary.count == 3)
        #expect(summary[0].first == .monday && summary[0].last == .friday)
        #expect(summary[2].isClosed)
        #expect(try #require(OpeningHours.parse("Mo-Su 10:00-18:00")).weekSummary.count == 1)
    }
}
