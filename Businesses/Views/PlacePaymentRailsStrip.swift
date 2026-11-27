import SwiftUI
import Foundation

// MARK: - Bitcoin Payment Rails Strip (Signature Unboxed Strip)

struct PlacePaymentRailsStrip: View {
    let element: Element
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private struct PaymentRail: Identifiable {
        let id: String
        let icon: String
        let shortLabel: String
        let accessibilityLabel: String
        let tint: Color
    }

    private var rails: [PaymentRail] {
        var items: [PaymentRail] = []
        if acceptsLightning(element: element) {
            items.append(
                PaymentRail(
                    id: "lightning",
                    icon: "bolt.fill",
                    shortLabel: "Lightning",
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin_lightning", comment: "Label for accepting Bitcoin over Lightning"),
                    tint: .orange
                )
            )
        }
        if acceptsContactlessLightning(element: element) {
            items.append(
                PaymentRail(
                    id: "nfc",
                    icon: "wave.3.right",
                    shortLabel: "NFC",
                    accessibilityLabel: NSLocalizedString("accepts_contactless_lightning", comment: "Label for accepting Contactless Lightning"),
                    tint: .accentColor
                )
            )
        }
        if acceptsBitcoinOnChain(element: element) {
            items.append(
                PaymentRail(
                    id: "onchain",
                    icon: "bitcoinsign",
                    shortLabel: "On-Chain",
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin_onchain", comment: "Label for accepting Bitcoin on Chain"),
                    tint: .orange
                )
            )
        }
        if acceptsBitcoin(element: element) {
            items.append(
                PaymentRail(
                    id: "bitcoin",
                    icon: "bitcoinsign",
                    shortLabel: NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"),
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"),
                    tint: .orange
                )
            )
        }
        return items
    }

    private var requiredApp: (raw: String, url: URL)? {
        guard let raw = element.v4Metadata?.requiredAppURL,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return (raw, url)
    }

    var body: some View {
        if !rails.isEmpty || requiredApp != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !rails.isEmpty {
                    BitLocalFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(rails) { rail in
                            HStack(spacing: 5) {
                                Image(systemName: rail.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(rail.tint)
                                Text(rail.shortLabel)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                BitLocalSheetSurface.fillColor(
                                    for: .control,
                                    colorScheme: colorScheme,
                                    contrast: colorSchemeContrast
                                ),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        BitLocalSheetSurface.borderColor(
                                            for: .control,
                                            colorScheme: colorScheme,
                                            contrast: colorSchemeContrast
                                        ),
                                        lineWidth: 0.5
                                    )
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(rail.accessibilityLabel)
                        }
                    }
                }

                if let requiredApp {
                    PlaceGroupedSurface(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                        Button {
                            BitLocalHaptics.lightTap()
                            openURL(requiredApp.url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "app.badge.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .frame(width: 20, alignment: .center)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Required App")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(requiredApp.raw.cleanedForDisplay())
                                        .font(.subheadline)
                                        .foregroundStyle(.accent)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tactileRow(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

// MARK: - Live Opening Hours Evaluator

struct OpeningHoursLiveStatus {
    let isOpen: Bool
    let shortLabel: LocalizedStringKey

    static func isOpenNow(
        rawOpeningHours: String?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let trimmed = rawOpeningHours?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let schedule = OSMOpeningHoursParser.parseWeekSchedule(trimmed) else {
            return false
        }
        return evaluate(schedule: schedule, now: now, calendar: calendar).isOpen
    }

    static func evaluate(
        schedule: OSMOpeningHoursWeekSchedule,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> OpeningHoursLiveStatus {
        if schedule.isTwentyFourSeven {
            return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open 24/7")
        }

        let today = weekday(for: calendar.component(.weekday, from: now))
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if let todaySchedule = schedule.days.first(where: { $0.weekday == today }) {
            for range in todaySchedule.ranges {
                if range.isAllDay {
                    return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                }
                if range.endMinutes >= range.startMinutes {
                    if nowMinutes >= range.startMinutes && nowMinutes < range.endMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                } else {
                    if nowMinutes >= range.startMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                }
            }
        }

        if let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) {
            let yesterday = weekday(for: calendar.component(.weekday, from: yesterdayDate))
            if let yesterdaySchedule = schedule.days.first(where: { $0.weekday == yesterday }) {
                for range in yesterdaySchedule.ranges {
                    if range.endMinutes > 24 * 60 {
                        let spilloverEnd = range.endMinutes - 24 * 60
                        if nowMinutes < spilloverEnd {
                            return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                        }
                    } else if range.endMinutes < range.startMinutes && nowMinutes < range.endMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                }
            }
        }

        return OpeningHoursLiveStatus(isOpen: false, shortLabel: "Closed")
    }

    static func weekday(for calendarWeekday: Int) -> WeeklyHours.Weekday {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}
