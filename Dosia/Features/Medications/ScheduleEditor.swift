import CoreData
import SwiftUI

/// Section of `MedicationEditView` that manages the recurrence rules. Most
/// medications need a single rule with two or three times a day; a second rule
/// exists for the rarer "twice daily on weekdays, once at weekends" case.
struct ScheduleEditor: View {
    @ObservedObject var medication: Medication

    @Environment(\.managedObjectContext) private var context

    var body: some View {
        Section {
            ForEach(medication.sortedRules, id: \.objectID) { rule in
                NavigationLink {
                    ScheduleRuleEditor(rule: rule)
                } label: {
                    ScheduleRuleSummary(rule: rule)
                }
            }
            .onDelete(perform: deleteRules)

            Button {
                ScheduleRule.make(in: context, medication: medication)
            } label: {
                Label("Add schedule", systemImage: "plus")
            }
        } header: {
            Text("Schedule")
        } footer: {
            if medication.sortedRules.isEmpty {
                Text("Without a schedule this medication never appears on the Today screen.")
            } else {
                Text("Doses are worked out from these rules; nothing is stored in advance.")
            }
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        let rules = medication.sortedRules
        for index in offsets where rules.indices.contains(index) {
            context.delete(rules[index])
        }
    }
}

struct ScheduleRuleSummary: View {
    @ObservedObject var rule: ScheduleRule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.minutes.isEmpty ? String(localized: "No times set") : ScheduleSummary.times(rule.minutes))
                .font(.body)
                .foregroundStyle(rule.minutes.isEmpty ? Color.secondary : Color.primary)
            Text(recurrenceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recurrenceDescription: String {
        switch rule.recurrenceEnum {
        case .daily:
            return String(localized: "Every day")
        case .everyNDays:
            return String(localized: "Every \(Int(rule.intervalDays)) days")
        case .weekdays:
            let names = ScheduleSummary.weekdayNames(rule.weekdaySet)
            return names.isEmpty ? String(localized: "No weekdays selected") : names
        }
    }
}

struct ScheduleRuleEditor: View {
    @ObservedObject var rule: ScheduleRule

    @Environment(\.managedObjectContext) private var context
    @State private var newTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()

    private let calendar = Calendar.current

    var body: some View {
        Form {
            Section {
                ForEach(rule.minutes, id: \.self) { minute in
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text(timeLabel(for: minute))
                        Spacer()
                        Button {
                            remove(minute)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove time"))
                    }
                }

                HStack {
                    DatePicker("Add a time", selection: $newTime, displayedComponents: .hourAndMinute)
                    Button("Add", action: addTime)
                        .buttonStyle(.bordered)
                }
            } header: {
                Text("Times of day")
            } footer: {
                Text("Each time becomes one line to tick off on the Today screen.")
            }

            Section("Repeat") {
                Picker("Repeat", selection: Binding(
                    get: { rule.recurrenceEnum },
                    set: { rule.recurrenceEnum = $0 }
                )) {
                    ForEach(Recurrence.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if rule.recurrenceEnum == .everyNDays {
                Section {
                    Stepper(
                        value: Binding(
                            get: { Int(rule.intervalDays) },
                            set: { rule.intervalDays = Int16(clamping: max(1, $0)) }
                        ),
                        in: 1...30
                    ) {
                        Text("Every \(Int(rule.intervalDays)) days")
                    }
                    DatePicker(
                        "Counting from",
                        selection: Binding(
                            get: { rule.startDate ?? Date() },
                            set: { rule.startDate = calendar.startOfDay(for: $0) }
                        ),
                        displayedComponents: .date
                    )
                } footer: {
                    Text("The interval is counted from this day.")
                }
            }

            if rule.recurrenceEnum == .weekdays {
                Section("Weekdays") {
                    weekdayPicker
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weekdayPicker: some View {
        let symbols = calendar.shortWeekdaySymbols
        // Respect the user's first day of week rather than always starting on Sunday.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let selected = rule.weekdaySet.contains(weekday)
                Button {
                    toggle(weekday)
                } label: {
                    Text(symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func timeLabel(for minute: Int) -> String {
        let base = calendar.startOfDay(for: Date())
        guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: base)
        else { return "\(minute / 60):\(minute % 60)" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func addTime() {
        let components = calendar.dateComponents([.hour, .minute], from: newTime)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        var minutes = rule.minutes
        guard !minutes.contains(minute) else { return }
        minutes.append(minute)
        rule.minutes = minutes
    }

    private func remove(_ minute: Int) {
        rule.minutes = rule.minutes.filter { $0 != minute }
    }

    private func toggle(_ weekday: Int) {
        var weekdays = rule.weekdaySet
        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
        rule.weekdaySet = weekdays
    }
}
