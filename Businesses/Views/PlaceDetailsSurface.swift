import SwiftUI
import CoreLocation
import UIKit

// MARK: - Unified Details Surface (Hours, Address, Contact & Socials)

struct PlaceDetailsSurface: View {
    let element: Element
    var elementCellViewModel: ElementCellViewModel
    let openingHoursRaw: String?
    let parsedOpeningSchedule: OSMOpeningHoursWeekSchedule?
    let websiteInfo: (display: String, url: URL)?
    let phoneInfo: (display: String, url: URL)?
    let emailInfo: (display: String, url: URL)?

    @State private var isHoursExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    private struct SocialItem: Identifiable {
        let id: String
        let label: String
        let displayLabel: String
        let icon: String?
        let value: String
        let url: URL?
    }

    private var addressDisplayText: String {
        elementCellViewModel.address?.formatted(.compact) ?? ""
    }

    private var todayWeekday: WeeklyHours.Weekday {
        OpeningHoursLiveStatus.weekday(for: calendar.component(.weekday, from: .now))
    }

    private var socialItems: [SocialItem] {
        guard let metadata = element.v4Metadata else { return [] }
        let candidates: [(label: String, displayLabel: String?, icon: String?, rawValue: String?, url: URL?)] = [
            ("X", "𝕏", nil, metadata.twitter, metadata.twitter.flatMap { urlForSocialHandle($0, base: "https://x.com/") }),
            ("Instagram", nil, "camera", metadata.instagram, metadata.instagram.flatMap { urlForSocialHandle($0, base: "https://instagram.com/") }),
            ("Telegram", nil, "paperplane", metadata.telegram, metadata.telegram.flatMap { urlForSocialHandle($0, base: "https://t.me/") }),
            ("Facebook", nil, "f.cursive", metadata.facebook, metadata.facebook.flatMap { urlForSocialHandle($0, base: "https://facebook.com/") }),
            ("LINE", nil, "message", metadata.line, metadata.line.flatMap(URL.init(string:)))
        ]
        return candidates.compactMap { item in
            guard let raw = item.rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return SocialItem(
                id: item.label,
                label: item.label,
                displayLabel: item.displayLabel ?? item.label,
                icon: item.icon,
                value: raw.cleanedForDisplay(),
                url: item.url
            )
        }
    }

    private var hasHours: Bool { openingHoursRaw != nil }
    private var hasAddress: Bool { element.mapCoordinate != nil }
    private var hasWebsite: Bool { websiteInfo != nil }
    private var hasPhone: Bool { phoneInfo != nil }
    private var hasEmail: Bool { emailInfo != nil }
    private var hasAnyContactOrHours: Bool { hasHours || hasAddress || hasWebsite || hasPhone || hasEmail }
    private var hasAnyContent: Bool { hasAnyContactOrHours || !socialItems.isEmpty }

    var body: some View {
        if hasAnyContent {
            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                VStack(alignment: .leading, spacing: 0) {
                    if let openingHoursRaw {
                        hoursSection(rawOpeningHours: openingHoursRaw)
                    }

                    if let coord = element.mapCoordinate {
                        if hasHours { rowDivider }
                        contactRow(
                            icon: "mappin.and.ellipse",
                            label: NSLocalizedString("address_label", comment: "Label for address"),
                            value: addressDisplayText.isEmpty ? "Open in Apple Maps" : addressDisplayText,
                            copyValue: addressDisplayText.isEmpty ? nil : addressDisplayText,
                            copyTitle: "Copy Address",
                            valueLineLimit: 3
                        ) {
                            BitLocalHaptics.lightTap()
                            openLocationInMaps(
                                coordinate: coord,
                                name: element.displayName,
                                address: elementCellViewModel.address
                            )
                        }
                    }

                    if let website = websiteInfo {
                        if hasHours || hasAddress { rowDivider }
                        contactRow(
                            icon: "globe",
                            label: NSLocalizedString("website_label", comment: "Label for website"),
                            value: website.display,
                            copyValue: website.display,
                            copyTitle: "Copy Website",
                            valueLineLimit: 2
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(website.url)
                        }
                    }

                    if let phone = phoneInfo {
                        if hasHours || hasAddress || hasWebsite { rowDivider }
                        contactRow(
                            icon: "phone",
                            label: NSLocalizedString("phone_label", comment: "Label for phone"),
                            value: phone.display,
                            copyValue: phone.display,
                            copyTitle: "Copy Phone",
                            valueLineLimit: 1
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(phone.url)
                        }
                    }

                    if let email = emailInfo {
                        if hasHours || hasAddress || hasWebsite || hasPhone { rowDivider }
                        contactRow(
                            icon: "envelope",
                            label: "Email",
                            value: email.display,
                            copyValue: email.display,
                            copyTitle: "Copy Email",
                            valueLineLimit: 2
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(email.url)
                        }
                    }

                    if !socialItems.isEmpty {
                        if hasAnyContactOrHours { rowDivider }
                        socialsRow
                    }
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 32)
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private func hoursSection(rawOpeningHours: String) -> some View {
        if let parsedSchedule = parsedOpeningSchedule {
            let status = OpeningHoursLiveStatus.evaluate(schedule: parsedSchedule, now: .now, calendar: calendar)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    BitLocalHaptics.selection()
                    withAnimation(
                        BitLocalMotion.animation(
                            BitLocalMotion.disclosureSpring,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        isHoursExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(status.shortLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(status.isOpen ? Color.green : Color.secondary)
                            }

                            Text(todaySummaryText(for: parsedSchedule))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isHoursExpanded ? 180 : 0))
                            .padding(.trailing, 6)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactileRow(cornerRadius: 10))
                .accessibilityHint(isHoursExpanded ? "Double-tap to collapse weekly hours" : "Double-tap to view weekly hours")

                if isHoursExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(parsedSchedule.days, id: \.weekday) { day in
                            let isToday = day.weekday == todayWeekday
                            HStack(alignment: .top, spacing: 12) {
                                Text(shortWeekdayLabel(for: day.weekday))
                                    .font(.footnote)
                                    .fontWeight(isToday ? .semibold : .regular)
                                    .foregroundStyle(isToday ? .primary : .secondary)
                                    .lineLimit(1)
                                    .frame(width: 40, alignment: .leading)

                                hoursText(for: day, isToday: isToday)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rawOpeningHours)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private func contactRow(
        icon: String,
        label: String,
        value: String,
        copyValue: String?,
        copyTitle: String,
        valueLineLimit: Int,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(valueLineLimit)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactileRow(cornerRadius: 10))
            .copyValueContextMenu(copyValue, title: copyTitle)

            if let copyValue, !copyValue.isEmpty {
                TactileCopyButton(value: copyValue, accessibilityLabel: copyTitle)
            }
        }
    }

    private var socialsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "at")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Socials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                BitLocalFlowLayout(horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(socialItems) { social in
                        socialLink(social)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func socialLink(_ social: SocialItem) -> some View {
        let content = HStack(spacing: 5) {
            if let icon = social.icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            Text(social.displayLabel)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(social.url != nil ? Color.accentColor : Color.primary)
        .frame(minWidth: social.icon == nil ? 28 : nil, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(social.label)

        if let url = social.url {
            Button {
                BitLocalHaptics.lightTap()
                openURL(url)
            } label: {
                content
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .copyValueContextMenu(social.value, title: "Copy \(social.label)")
        } else {
            content
                .copyValueContextMenu(social.value, title: "Copy \(social.label)")
        }
    }

    private func todaySummaryText(for schedule: OSMOpeningHoursWeekSchedule) -> String {
        if schedule.isTwentyFourSeven {
            return "24/7"
        }
        guard let today = schedule.days.first(where: { $0.weekday == todayWeekday }) else {
            return NSLocalizedString("hours_closed", comment: "Closed label for business hours")
        }
        if today.ranges.isEmpty {
            return NSLocalizedString("hours_closed", comment: "Closed label for business hours")
        }
        if today.ranges.count == 1, today.ranges[0].isAllDay {
            return "24/7"
        }
        return today.ranges
            .map { formattedTime($0.startMinutes) + " \u{2013} " + formattedTime($0.endMinutes) }
            .formatted()
    }

    @ViewBuilder
    private func hoursText(for day: OSMOpeningHoursDaySchedule, isToday: Bool) -> some View {
        if day.ranges.isEmpty {
            Text(NSLocalizedString("hours_closed", comment: "Closed label for business hours"))
                .font(.footnote)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if day.ranges.count == 1, day.ranges[0].isAllDay {
            Text("24/7")
                .font(.footnote)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(day.ranges, id: \.self) { range in
                    Text(formattedTime(range.startMinutes) + " \u{2013} " + formattedTime(range.endMinutes))
                        .font(.footnote)
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundStyle(isToday ? .primary : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private func shortWeekdayLabel(for weekday: WeeklyHours.Weekday) -> String {
        let localizedWeekday: String
        switch weekday {
        case .monday:
            localizedWeekday = NSLocalizedString("weekday_mo", comment: "Monday abbreviation for business hours")
        case .tuesday:
            localizedWeekday = NSLocalizedString("weekday_tu", comment: "Tuesday abbreviation for business hours")
        case .wednesday:
            localizedWeekday = NSLocalizedString("weekday_we", comment: "Wednesday abbreviation for business hours")
        case .thursday:
            localizedWeekday = NSLocalizedString("weekday_th", comment: "Thursday abbreviation for business hours")
        case .friday:
            localizedWeekday = NSLocalizedString("weekday_fr", comment: "Friday abbreviation for business hours")
        case .saturday:
            localizedWeekday = NSLocalizedString("weekday_sa", comment: "Saturday abbreviation for business hours")
        case .sunday:
            localizedWeekday = NSLocalizedString("weekday_su", comment: "Sunday abbreviation for business hours")
        }

        let trimmed = localizedWeekday.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 3 {
            return trimmed
        }
        return String(trimmed.prefix(3))
    }

    private func formattedTime(_ totalMinutes: Int) -> String {
        let clampedMinutes = max(0, min(totalMinutes, 24 * 60))
        let hour = clampedMinutes / 60
        let minute = clampedMinutes % 60

        var components = DateComponents()
        components.calendar = calendar
        components.hour = hour == 24 ? 0 : hour
        components.minute = minute

        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }

        return date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        )
    }
}
