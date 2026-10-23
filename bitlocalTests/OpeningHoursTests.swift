import XCTest
@testable import bitlocal

final class OSMOpeningHoursParserTests: XCTestCase {
    func testTwentyFourSevenOpensEveryDayAllDay() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule(" 24/7 "))

        XCTAssertTrue(schedule.isTwentyFourSeven)
        XCTAssertEqual(schedule.days.map(\.weekday), WeeklyHours.Weekday.allCases)
    }

    func testExplicitAllDayRangeForEveryDayCountsAsTwentyFourSeven() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Mo-Su 00:00-24:00"))

        XCTAssertTrue(schedule.isTwentyFourSeven)
    }

    func testWeekdayRangeAndSingleDayRules() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Mo-Fr 09:00-17:00; Sa 10:00-14:30"))

        for day in [WeeklyHours.Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            XCTAssertEqual(ranges(schedule, day), [range(9, 0, 17, 0)], "\(day)")
        }
        XCTAssertEqual(ranges(schedule, .saturday), [range(10, 0, 14, 30)])
        XCTAssertEqual(ranges(schedule, .sunday), [])
        XCTAssertFalse(schedule.isTwentyFourSeven)
    }

    func testMultipleTimeRangesForSplitShifts() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Tu 09:00-12:00, 13:00-17:00"))

        XCTAssertEqual(ranges(schedule, .tuesday), [range(9, 0, 12, 0), range(13, 0, 17, 0)])
        XCTAssertEqual(ranges(schedule, .monday), [])
    }

    func testDayRangeWrapsAroundTheWeekend() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Fr-Mo 10:00-18:00"))

        let open = schedule.days.filter { !$0.ranges.isEmpty }.map(\.weekday)
        XCTAssertEqual(Set(open), [.friday, .saturday, .sunday, .monday])
    }

    func testCommaSeparatedDayList() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Mo,We,Fr 08:00-12:00"))

        let open = schedule.days.filter { !$0.ranges.isEmpty }.map(\.weekday)
        XCTAssertEqual(open, [.monday, .wednesday, .friday])
    }

    func testRuleWithoutDaySelectorAppliesToEveryDay() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("07:00-22:00"))

        XCTAssertTrue(schedule.days.allSatisfy { $0.ranges == [range(7, 0, 22, 0)] })
    }

    func testLaterOffRuleClosesEarlierDays() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Mo-Su 08:00-20:00; Su off"))

        XCTAssertEqual(ranges(schedule, .saturday), [range(8, 0, 20, 0)])
        XCTAssertEqual(ranges(schedule, .sunday), [])
    }

    func testClosedKeywordIsTreatedLikeOff() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Mo-Sa 09:00-17:00; Sa closed"))

        XCTAssertEqual(ranges(schedule, .friday), [range(9, 0, 17, 0)])
        XCTAssertEqual(ranges(schedule, .saturday), [])
    }

    func testMidnightCloseIsEndOfDay() throws {
        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule("Fr 18:00-24:00"))

        XCTAssertEqual(ranges(schedule, .friday), [OSMOpeningHoursTimeRange(startMinutes: 18 * 60, endMinutes: 24 * 60)])
    }

    func testUnsupportedOrMalformedValuesReturnNil() {
        let unsupported = [
            "",
            "   ",
            ";",
            "Mo-Fr",
            "sunrise-sunset",
            "Mo-Fr 09:00-17:00 || PH off",
            "Mo-Fr 09:00-17:00; PH off",
            "Xx 09:00-17:00",
            "Mo 25:00-26:00",
            "Mo 09:60-10:00",
            "Mo 24:30-01:00",
            "Mo 0900-1700",
            "Mo 09:00"
        ]

        for value in unsupported {
            XCTAssertNil(OSMOpeningHoursParser.parseWeekSchedule(value), "Expected nil for '\(value)'")
        }
    }

    private func ranges(_ schedule: OSMOpeningHoursWeekSchedule, _ day: WeeklyHours.Weekday) -> [OSMOpeningHoursTimeRange] {
        schedule.days.first { $0.weekday == day }?.ranges ?? []
    }

    private func range(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> OSMOpeningHoursTimeRange {
        OSMOpeningHoursTimeRange(startMinutes: startHour * 60 + startMinute, endMinutes: endHour * 60 + endMinute)
    }
}

final class WeeklyHoursTests: XCTestCase {
    func testAllClosedFormatsAsEmptyString() {
        let hours = WeeklyHours()

        XCTAssertEqual(hours.toOSMFormat(), "")
        XCTAssertFalse(hours.hasAnyOpen)
    }

    func testConsecutiveDaysWithSameHoursAreGrouped() {
        var hours = WeeklyHours()
        for day in [WeeklyHours.Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            hours[day] = open(9, 0, 17, 0)
        }

        XCTAssertEqual(hours.toOSMFormat(), "Mo-Fr 09:00-17:00")
        XCTAssertTrue(hours.hasAnyOpen)
    }

    func testDifferentHoursStartANewSegment() {
        var hours = WeeklyHours()
        hours.monday = open(10, 0, 19, 0)
        hours.tuesday = open(10, 0, 19, 0)
        hours.wednesday = open(10, 0, 19, 0)
        hours.thursday = open(8, 0, 20, 0)

        XCTAssertEqual(hours.toOSMFormat(), "Mo-We 10:00-19:00; Th 08:00-20:00")
    }

    func testClosedDayBreaksAGroupEvenWhenHoursMatch() {
        var hours = WeeklyHours()
        hours.monday = open(9, 0, 17, 0)
        hours.wednesday = open(9, 0, 17, 0)

        XCTAssertEqual(hours.toOSMFormat(), "Mo 09:00-17:00; We 09:00-17:00")
    }

    func testClosedDaysKeepTheirTimesOutOfTheOutput() {
        var hours = WeeklyHours()
        hours.sunday = DayHours(isOpen: false, openTime: time(1, 0), closeTime: time(2, 0))
        hours.saturday = open(11, 30, 15, 45)

        XCTAssertEqual(hours.toOSMFormat(), "Sa 11:30-15:45")
    }

    func testFormattedHoursParseBackToTheSameSchedule() throws {
        var hours = WeeklyHours()
        hours.monday = open(9, 0, 17, 0)
        hours.tuesday = open(9, 0, 17, 0)
        hours.friday = open(12, 0, 23, 0)
        hours.sunday = open(10, 15, 14, 0)

        let schedule = try XCTUnwrap(OSMOpeningHoursParser.parseWeekSchedule(hours.toOSMFormat()))

        for day in WeeklyHours.Weekday.allCases {
            let parsed = schedule.days.first { $0.weekday == day }?.ranges ?? []
            let dayHours = hours[day]
            if dayHours.isOpen {
                XCTAssertEqual(parsed, [OSMOpeningHoursTimeRange(
                    startMinutes: minutes(dayHours.openTime),
                    endMinutes: minutes(dayHours.closeTime)
                )], "\(day)")
            } else {
                XCTAssertEqual(parsed, [], "\(day)")
            }
        }
    }

    func testSubscriptReadsAndWritesEachDay() {
        var hours = WeeklyHours()
        for (offset, day) in WeeklyHours.Weekday.allCases.enumerated() {
            hours[day] = open(offset, 0, offset + 1, 0)
        }

        for (offset, day) in WeeklyHours.Weekday.allCases.enumerated() {
            XCTAssertEqual(hours[day], open(offset, 0, offset + 1, 0), "\(day)")
        }
        XCTAssertEqual(hours.monday, open(0, 0, 1, 0))
        XCTAssertEqual(hours.sunday, open(6, 0, 7, 0))
    }

    func testWeekdayOrderingAndKeys() {
        XCTAssertEqual(WeeklyHours.Weekday.allCases.map(\.sortOrder), Array(0...6))
        XCTAssertEqual(WeeklyHours.Weekday.allCases.map(\.rawValue), ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
        XCTAssertEqual(WeeklyHours.Weekday.monday.localizedKey, "weekday_mo")
    }

    func testWeeklyHoursRoundTripsThroughCodable() throws {
        var hours = WeeklyHours()
        hours.thursday = open(7, 30, 15, 0)

        let data = try JSONEncoder().encode(hours)
        let decoded = try JSONDecoder().decode(WeeklyHours.self, from: data)

        XCTAssertEqual(decoded, hours)
    }

    private func open(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> DayHours {
        DayHours(isOpen: true, openTime: time(startHour, startMinute), closeTime: time(endHour, endMinute))
    }

    private func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute))!
    }

    private func minutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
