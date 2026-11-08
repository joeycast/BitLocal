import Foundation

/// A parsed OSM `opening_hours` value for the common weekly forms
/// (`Mo-Fr 09:00-17:00; Sa 10:00-14:00; Su off`, `24/7`, split and overnight
/// ranges). Anything richer (dates, holidays other than `PH off`, comments,
/// open-ended `+` times, fallback rules) returns nil and the raw string is shown.
public struct OpeningHours: Hashable, Sendable {
    /// Monday-first, matching OSM.
    public enum Weekday: Int, CaseIterable, Hashable, Sendable, Comparable {
        case monday, tuesday, wednesday, thursday, friday, saturday, sunday

        public var osmToken: String {
            ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"][rawValue]
        }

        init?(osmToken: String) {
            guard let index = ["mo", "tu", "we", "th", "fr", "sa", "su"].firstIndex(of: osmToken.lowercased()) else { return nil }
            self.init(rawValue: index)
        }

        /// From `Calendar.component(.weekday)` (1 = Sunday … 7 = Saturday).
        public init(calendarWeekday: Int) {
            self.init(rawValue: (calendarWeekday + 5) % 7)!
        }

        /// The value `DateComponents.weekday` uses.
        public var calendarWeekday: Int { (rawValue + 1) % 7 + 1 }

        public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

        func advanced(by days: Int) -> Weekday {
            Weekday(rawValue: ((rawValue + days) % 7 + 7) % 7)!
        }
    }

    /// Minutes after midnight. `end` is greater than `start`; overnight ranges
    /// run past 1440 (`18:00-02:00` is 1080...1560).
    public struct TimeRange: Hashable, Sendable {
        public let start: Int
        public let end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }

        public var isAllDay: Bool { start == 0 && end >= 24 * 60 }
    }

    /// Consecutive days with identical hours, for the merged week summary ("Mon–Fri 9 AM–5 PM").
    public struct DayGroup: Hashable, Sendable {
        public let first: Weekday
        public let last: Weekday
        public let ranges: [TimeRange]

        public var isClosed: Bool { ranges.isEmpty }
    }

    public enum Status: Hashable, Sendable {
        /// Open now. `closesAt` is minutes after midnight on the day it closes (nil: open around the clock).
        case open(closesAt: Int?)
        /// Closed now. `opensAt` is the next opening, `daysAhead` 0 for later today (nil: never opens).
        case closed(opensAt: Int?, daysAhead: Int?)

        public var isOpen: Bool {
            if case .open = self { return true }
            return false
        }
    }

    /// Ranges per weekday, Monday first (always 7 entries).
    public let days: [[TimeRange]]

    public init(days: [[TimeRange]]) {
        precondition(days.count == 7)
        self.days = days
    }

    public subscript(day: Weekday) -> [TimeRange] { days[day.rawValue] }

    public var isAlwaysOpen: Bool {
        days.allSatisfy { $0.count == 1 && $0[0].isAllDay }
    }

    // MARK: Parsing

    public static func parse(_ raw: String?) -> OpeningHours? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\""), !trimmed.contains("||"), !trimmed.contains("+") else { return nil }
        if trimmed.lowercased() == "24/7" {
            return OpeningHours(days: Array(repeating: [TimeRange(start: 0, end: 1440)], count: 7))
        }

        var days: [[TimeRange]] = Array(repeating: [], count: 7)
        let rules = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !rules.isEmpty else { return nil }

        for rule in rules {
            let lower = rule.lowercased()
            // Holiday rules don't change the weekly view.
            if lower.hasPrefix("ph") || lower.hasPrefix("sh") { continue }

            if lower.hasSuffix(" off") || lower.hasSuffix(" closed") {
                let selector = String(rule[..<rule.lastIndex(of: " ")!])
                guard let selected = parseDays(selector) else { return nil }
                for day in selected { days[day.rawValue] = [] }
                continue
            }

            let selected: [Weekday]
            let timePart: String
            if let firstDigit = rule.firstIndex(where: \.isNumber) {
                let selector = rule[..<firstDigit].trimmingCharacters(in: .whitespaces)
                timePart = String(rule[firstDigit...])
                if selector.isEmpty {
                    selected = Weekday.allCases
                } else {
                    guard let parsed = parseDays(selector) else { return nil }
                    selected = parsed
                }
            } else {
                return nil
            }
            guard let ranges = parseRanges(timePart) else { return nil }
            for day in selected { days[day.rawValue] = ranges }
        }
        return OpeningHours(days: days)
    }

    private static func parseDays(_ selector: String) -> [Weekday]? {
        var result: [Weekday] = []
        for token in selector.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            let bounds = token.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            if bounds.count == 1 {
                guard let day = Weekday(osmToken: bounds[0]) else { return nil }
                if !result.contains(day) { result.append(day) }
            } else if bounds.count == 2, let from = Weekday(osmToken: bounds[0]), let to = Weekday(osmToken: bounds[1]) {
                var day = from
                while true {
                    if !result.contains(day) { result.append(day) }
                    if day == to { break }
                    day = day.advanced(by: 1)
                }
            } else {
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func parseRanges(_ text: String) -> [TimeRange]? {
        var ranges: [TimeRange] = []
        for token in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            let bounds = token.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bounds.count == 2, let start = minutes(bounds[0]), var end = minutes(bounds[1]) else { return nil }
            guard start < 24 * 60 else { return nil }
            if end <= start { end += 24 * 60 }
            ranges.append(TimeRange(start: start, end: end))
        }
        return ranges.isEmpty ? nil : ranges.sorted { $0.start < $1.start }
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...59).contains(minute), (0...48).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    // MARK: Status

    public func status(at date: Date, calendar: Calendar = .current) -> Status {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let today = Weekday(calendarWeekday: components.weekday ?? 2)
        let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return status(weekday: today, minute: now)
    }

    public func status(weekday today: Weekday, minute now: Int) -> Status {
        if isAlwaysOpen { return .open(closesAt: nil) }

        // Still inside yesterday's overnight range?
        for range in self[today.advanced(by: -1)] where range.end > 1440 && now < range.end - 1440 {
            return .open(closesAt: range.end - 1440)
        }
        for range in self[today] where range.start <= now && now < range.end {
            return .open(closesAt: range.end % 1440)
        }
        for range in self[today] where range.start > now {
            return .closed(opensAt: range.start, daysAhead: 0)
        }
        for offset in 1...7 {
            if let first = self[today.advanced(by: offset)].first {
                return .closed(opensAt: first.start, daysAhead: offset)
            }
        }
        return .closed(opensAt: nil, daysAhead: nil)
    }

    // MARK: Summary

    /// The week as runs of consecutive days with identical hours, Monday first.
    public var weekSummary: [DayGroup] {
        var groups: [DayGroup] = []
        for day in Weekday.allCases {
            let ranges = self[day]
            if let last = groups.last, last.ranges == ranges, last.last.rawValue == day.rawValue - 1 {
                groups[groups.count - 1] = DayGroup(first: last.first, last: day, ranges: ranges)
            } else {
                groups.append(DayGroup(first: day, last: day, ranges: ranges))
            }
        }
        return groups
    }
}
