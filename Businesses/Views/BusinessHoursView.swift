import SwiftUI

struct BusinessHoursView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var submission: BusinessSubmission

    @State private var hoursPreset: HoursPreset = .none
    @State private var presetOpenTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date.now
    @State private var presetCloseTime: Date = Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date.now

    enum HoursPreset: String, CaseIterable {
        case none = "None"
        case allWeek = "Same hours every day"
        case weekdaysOnly = "Weekdays only"
        case custom = "Custom hours"

        var localizedKey: String {
            switch self {
            case .none: return "hours_preset_unknown"
            case .allWeek: return "hours_preset_all_week"
            case .weekdaysOnly: return "hours_preset_weekdays"
            case .custom: return "hours_preset_custom"
            }
        }
    }

    var body: some View {
        Form {
                Section {
                    Picker(selection: $hoursPreset) {
                        ForEach(HoursPreset.allCases, id: \.self) { preset in
                            Text(LocalizedStringKey(preset.localizedKey))
                                .tag(preset)
                        }
                    } label: {
                        Text("hours_preset_label")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: hoursPreset) { oldValue, newValue in
                        applyPreset(newValue)
                    }

                    if hoursPreset == .allWeek || hoursPreset == .weekdaysOnly {
                        HStack {

                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_open")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                DatePicker(selection: $presetOpenTime, displayedComponents: .hourAndMinute) {
                                    Text("hours_open")
                                }
                                .labelsHidden()
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                            
                            Spacer()
                            
                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_close")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                DatePicker(selection: $presetCloseTime, displayedComponents: .hourAndMinute) {
                                    Text("hours_close")
                                }
                                .labelsHidden()
                            }

                        }
                        .padding(.vertical, 4)
                        .onChange(of: presetOpenTime) { _, _ in applyPreset(hoursPreset) }
                        .onChange(of: presetCloseTime) { _, _ in applyPreset(hoursPreset) }
                    }
                } header: {
                    Text("step_hours_header")
                } footer: {
                    Text("step_hours_footer")
                }

                if hoursPreset == .custom {
                    customHoursSection
                }
            }
    }

    private var customHoursSection: some View {
        Section {
            ForEach(WeeklyHours.Weekday.allCases, id: \.self) { day in
                let dayHours = dayHoursBinding(for: day)

                VStack(spacing: 0) {
                    HStack {
                        Text(LocalizedStringKey(day.localizedKey))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .foregroundStyle(dayHours.isOpen.wrappedValue ? .primary : .secondary)

                        Spacer()

                        Picker(selection: dayHours.isOpen) {
                            Text("hours_closed").tag(false)
                            Text("hours_open").tag(true)
                        } label: {
                            Text(LocalizedStringKey(day.localizedKey))
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .padding(.vertical, 4)

                    if dayHours.isOpen.wrappedValue {
                        HStack {

                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_open")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                DatePicker(selection: dayHours.openTime, displayedComponents: .hourAndMinute) {
                                    Text("hours_open")
                                }
                                .labelsHidden()
                            }

                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)

                            VStack(alignment: .center, spacing: 2) {
                                Text("hours_close")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                                DatePicker(selection: dayHours.closeTime, displayedComponents: .hourAndMinute) {
                                    Text("hours_close")
                                }
                                .labelsHidden()
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(BitLocalMotion.animation(.snappy, reduceMotion: reduceMotion), value: dayHours.isOpen.wrappedValue)
            }
        } header: {
            Text("hours_custom_days_header")
        }
    }

    private func dayHoursBinding(for day: WeeklyHours.Weekday) -> Binding<DayHours> {
        switch day {
        case .monday: $submission.weeklyHours.monday
        case .tuesday: $submission.weeklyHours.tuesday
        case .wednesday: $submission.weeklyHours.wednesday
        case .thursday: $submission.weeklyHours.thursday
        case .friday: $submission.weeklyHours.friday
        case .saturday: $submission.weeklyHours.saturday
        case .sunday: $submission.weeklyHours.sunday
        }
    }

    private func applyPreset(_ preset: HoursPreset) {
        switch preset {
        case .none:
            // Clear all hours
            for day in WeeklyHours.Weekday.allCases {
                submission.weeklyHours[day].isOpen = false
            }
        case .allWeek:
            // Apply same hours to all days
            for day in WeeklyHours.Weekday.allCases {
                submission.weeklyHours[day].isOpen = true
                submission.weeklyHours[day].openTime = presetOpenTime
                submission.weeklyHours[day].closeTime = presetCloseTime
            }
        case .weekdaysOnly:
            // Apply to Mon-Fri only
            for day in WeeklyHours.Weekday.allCases {
                let isWeekday = day != .saturday && day != .sunday
                submission.weeklyHours[day].isOpen = isWeekday
                if isWeekday {
                    submission.weeklyHours[day].openTime = presetOpenTime
                    submission.weeklyHours[day].closeTime = presetCloseTime
                }
            }
        case .custom:
            // Don't modify - let user set individually
            break
        }
    }
}
