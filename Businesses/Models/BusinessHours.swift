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
