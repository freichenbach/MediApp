import CoreData
import SwiftUI

struct EventEditView: View {
    @ObservedObject var patient: Patient
    /// `nil` creates a new event; an existing object edits it in place.
    var event: CareEvent?
    var defaultDate: Date

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: EventCategory = .fever
    @State private var timestamp = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var hasMeasurement = false
    @State private var measurementText: String = ""
    @State private var measurementUnit: String = "°C"
    @State private var loaded = false

    private var isNew: Bool { event == nil }

    var body: some View {
        Group {
            if isNew {
                NavigationStack { form }
            } else {
                form
            }
        }
        .onAppear(perform: load)
    }

    private var form: some View {
        Form {
            Section("What happened?") {
                Picker("Category", selection: $category) {
                    ForEach(EventCategory.allCases) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                .onChange(of: category) { _, newValue in
                    if let suggested = newValue.suggestedUnit {
                        hasMeasurement = true
                        measurementUnit = suggested
                    }
                }

                TextField("Title", text: $title)
                DatePicker("When", selection: $timestamp)
            }

            Section {
                Toggle("Record a value", isOn: $hasMeasurement.animation())
                if hasMeasurement {
                    HStack {
                        TextField("0", text: $measurementText)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $measurementUnit)
                            .frame(maxWidth: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("For example a temperature of 38.9 °C.")
            }

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if isNew {
                Section {
                    Text("Logged as \(AppSettings.personName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dismissibleKeyboard()
        .navigationTitle(isNew ? Text("New event") : Text("Event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    // No rollback needed: a new event is only inserted in
                    // commit(), so there is nothing pending to undo — and
                    // rolling back here would discard unrelated edits.
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndDismiss)
                }
            }
        }
        // An existing event is edited live; leaving the screen commits it.
        .onDisappear { if !isNew { commit() } }
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let event {
            category = event.categoryEnum
            timestamp = event.timestamp ?? defaultDate
            title = event.title ?? ""
            note = event.note ?? ""
            hasMeasurement = event.hasMeasurement
            measurementText = DecimalText.text(for: event.measurementValue)
            measurementUnit = event.measurementUnit ?? category.suggestedUnit ?? ""
        } else {
            category = .fever
            measurementUnit = EventCategory.fever.suggestedUnit ?? ""
            hasMeasurement = true
            timestamp = alignedTimestamp
        }
    }

    /// A new event logged while browsing another day belongs to that day, at
    /// the current time of day.
    private var alignedTimestamp: Date {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(defaultDate) else { return Date() }
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: 0,
            of: calendar.startOfDay(for: defaultDate)
        ) ?? defaultDate
    }

    private func saveAndDismiss() {
        commit()
        dismiss()
    }

    private func commit() {
        let target = event ?? CareEvent.make(in: context, patient: patient)
        target.categoryEnum = category
        target.timestamp = timestamp
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        target.hasMeasurement = hasMeasurement
        target.measurementValue = hasMeasurement ? DecimalText.value(of: measurementText) : 0
        target.measurementUnit = hasMeasurement ? measurementUnit.trimmingCharacters(in: .whitespaces).nilIfEmpty : nil
        if target.personName == nil { target.personName = AppSettings.personName }

        PersistenceController.shared.save(context)
    }
}

#Preview {
    let controller = PersistenceController.preview
    return EventEditView(
        patient: Patient.fetchOrCreate(in: controller.viewContext),
        event: nil,
        defaultDate: Date()
    )
    .environment(\.managedObjectContext, controller.viewContext)
}
