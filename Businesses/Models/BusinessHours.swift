import Foundation

// Represents hours for a single day
struct DayHours: Codable, Equatable {
    var isOpen: Bool = false
    var openTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    var closeTime: Date = Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
}

// Represents a full week of business hours
struct WeeklyHours: Codable, Equatable {
    var monday = DayHours()
    var tuesday = DayHours()
    var wednesday = DayHours()
    var thursday = DayHours()
    var friday = DayHours()
    var saturday = DayHours()
    var sunday = DayHours()

    enum Weekday: String, CaseIterable {
        case monday = "Mo"
        case tuesday = "Tu"
        case wednesday = "We"
        case thursday = "Th"
        case friday = "Fr"
        case saturday = "Sa"
        case sunday = "Su"

        var localizedKey: String {
            "weekday_\(rawValue.lowercased())"
        }

        var sortOrder: Int {
            switch self {
            case .monday: return 0
            case .tuesday: return 1
            case .wednesday: return 2
            case .thursday: return 3
            case .friday: return 4
            case .saturday: return 5
            case .sunday: return 6
            }
        }
    }

    // Get hours for a specific day
    subscript(day: Weekday) -> DayHours {
        get {
            switch day {
            case .monday: return monday
            case .tuesday: return tuesday
            case .wednesday: return wednesday
            case .thursday: return thursday
            case .friday: return friday
            case .saturday: return saturday
            case .sunday: return sunday
            }
        }
        set {
            switch day {
            case .monday: monday = newValue
            case .tuesday: tuesday = newValue
            case .wednesday: wednesday = newValue
            case .thursday: thursday = newValue
            case .friday: friday = newValue
            case .saturday: saturday = newValue
            case .sunday: sunday = newValue
            }
        }
    }

    // Format to OpenStreetMap opening_hours syntax
    // Example: "Mo-We 10:00-19:00; Th 08:00-20:00"
    func toOSMFormat() -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        // Group consecutive days with same hours
        var segments: [(days: [Weekday], hours: DayHours)] = []

        for day in Weekday.allCases {
            let dayHours = self[day]
            guard dayHours.isOpen else { continue }

            // Check if we can add to the last segment
            if let lastSegment = segments.last,
               lastSegment.hours.openTime == dayHours.openTime,
               lastSegment.hours.closeTime == dayHours.closeTime,
               lastSegment.days.last!.sortOrder == day.sortOrder - 1 {
                segments[segments.count - 1].days.append(day)
            } else {
                segments.append((days: [day], hours: dayHours))
            }
        }

        // Format each segment
        let formattedSegments = segments.map { segment -> String in
            let dayRange: String
            if segment.days.count == 1 {
                dayRange = segment.days[0].rawValue
            } else {
                dayRange = "\(segment.days.first!.rawValue)-\(segment.days.last!.rawValue)"
            }

            let openTimeStr = timeFormatter.string(from: segment.hours.openTime)
            let closeTimeStr = timeFormatter.string(from: segment.hours.closeTime)

            return "\(dayRange) \(openTimeStr)-\(closeTimeStr)"
        }

        return formattedSegments.joined(separator: "; ")
    }

    var hasAnyOpen: Bool {
        Weekday.allCases.contains { self[$0].isOpen }
    }
}

struct OSMOpeningHoursTimeRange: Equatable {
    let startMinutes: Int
    let endMinutes: Int

    var isAllDay: Bool {
        startMinutes == 0 && endMinutes == 24 * 60
    }
}

struct OSMOpeningHoursDaySchedule: Equatable {
    let weekday: WeeklyHours.Weekday
    let ranges: [OSMOpeningHoursTimeRange]
}

struct OSMOpeningHoursWeekSchedule: Equatable {
    let days: [OSMOpeningHoursDaySchedule]

    var isTwentyFourSeven: Bool {
        days.allSatisfy { day in
            day.ranges.count == 1 && day.ranges[0].isAllDay
        }
    }
}

enum OSMOpeningHoursParser {
    static func parseWeekSchedule(_ rawValue: String) -> OSMOpeningHoursWeekSchedule? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased() == "24/7" {
            let allDayRange = OSMOpeningHoursTimeRange(startMinutes: 0, endMinutes: 24 * 60)
            let days = WeeklyHours.Weekday.allCases.map { OSMOpeningHoursDaySchedule(weekday: $0, ranges: [allDayRange]) }
            return OSMOpeningHoursWeekSchedule(days: days)
        }

        var dayRanges: [WeeklyHours.Weekday: [OSMOpeningHoursTimeRange]] = [:]
        for day in WeeklyHours.Weekday.allCases {
            dayRanges[day] = []
        }

        let rules = trimmed
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rules.isEmpty else { return nil }

        for rule in rules {
            if rule.contains("||") {
                return nil
            }

            let lowercasedRule = rule.lowercased()
            if lowercasedRule.hasSuffix(" off") || lowercasedRule.hasSuffix(" closed") {
                let suffixLength = lowercasedRule.hasSuffix(" off") ? 4 : 7
                let endIndex = rule.index(rule.endIndex, offsetBy: -suffixLength)
                let daySelector = rule[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let selectedDays = parseDaySelector(daySelector), !selectedDays.isEmpty else {
                    return nil
                }
                for day in selectedDays {
                    dayRanges[day] = []
                }
                continue
            }

            guard let firstDigitIndex = rule.firstIndex(where: { $0.isNumber }) else {
                return nil
            }

            let daySelector = rule[..<firstDigitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let timeSelector = rule[firstDigitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)

            let selectedDays: [WeeklyHours.Weekday]
            if daySelector.isEmpty {
                selectedDays = WeeklyHours.Weekday.allCases
            } else {
                guard let parsedDays = parseDaySelector(daySelector), !parsedDays.isEmpty else {
                    return nil
                }
                selectedDays = parsedDays
            }

            guard let ranges = parseTimeRanges(timeSelector), !ranges.isEmpty else {
                return nil
            }

            for day in selectedDays {
                dayRanges[day] = ranges
            }
        }

        let schedule = WeeklyHours.Weekday.allCases.map {
            OSMOpeningHoursDaySchedule(weekday: $0, ranges: dayRanges[$0] ?? [])
        }
        return OSMOpeningHoursWeekSchedule(days: schedule)
    }

    private static func parseDaySelector(_ selector: String) -> [WeeklyHours.Weekday]? {
        let tokens = selector
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var orderedDays: [WeeklyHours.Weekday] = []
        var seen: Set<WeeklyHours.Weekday> = []

        for token in tokens {
            if token.contains("-") {
                let parts = token
                    .split(separator: "-", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2,
                      let startDay = weekday(from: parts[0]),
                      let endDay = weekday(from: parts[1]),
                      let startIndex = WeeklyHours.Weekday.allCases.firstIndex(of: startDay),
                      let endIndex = WeeklyHours.Weekday.allCases.firstIndex(of: endDay) else {
                    return nil
                }

                if startIndex <= endIndex {
                    for day in WeeklyHours.Weekday.allCases[startIndex...endIndex] where !seen.contains(day) {
                        orderedDays.append(day)
                        seen.insert(day)
                    }
                } else {
                    for day in WeeklyHours.Weekday.allCases[startIndex...] where !seen.contains(day) {
                        orderedDays.append(day)
                        seen.insert(day)
                    }
                    for day in WeeklyHours.Weekday.allCases[...endIndex] where !seen.contains(day) {
                        orderedDays.append(day)
                        seen.insert(day)
                    }
                }
            } else {
                guard let day = weekday(from: token) else { return nil }
                if !seen.contains(day) {
                    orderedDays.append(day)
                    seen.insert(day)
                }
            }
        }

        return orderedDays
    }

    private static func parseTimeRanges(_ selector: String) -> [OSMOpeningHoursTimeRange]? {
        let tokens = selector
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var ranges: [OSMOpeningHoursTimeRange] = []
        for token in tokens {
            let bounds = token
                .split(separator: "-", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard bounds.count == 2,
                  let start = parseMinutes(from: bounds[0]),
                  let end = parseMinutes(from: bounds[1]) else {
                return nil
            }

            ranges.append(OSMOpeningHoursTimeRange(startMinutes: start, endMinutes: end))
        }
        return ranges
    }

    private static func parseMinutes(from value: String) -> Int? {
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              minute >= 0 && minute <= 59 else {
            return nil
        }

        if hour == 24 && minute == 0 {
            return 24 * 60
        }

        guard hour >= 0 && hour <= 23 else { return nil }
        return hour * 60 + minute
    }

    private static func weekday(from token: String) -> WeeklyHours.Weekday? {
        switch token {
        case WeeklyHours.Weekday.monday.rawValue: return .monday
        case WeeklyHours.Weekday.tuesday.rawValue: return .tuesday
        case WeeklyHours.Weekday.wednesday.rawValue: return .wednesday
        case WeeklyHours.Weekday.thursday.rawValue: return .thursday
        case WeeklyHours.Weekday.friday.rawValue: return .friday
        case WeeklyHours.Weekday.saturday.rawValue: return .saturday
        case WeeklyHours.Weekday.sunday.rawValue: return .sunday
        default: return nil
        }
    }
}
