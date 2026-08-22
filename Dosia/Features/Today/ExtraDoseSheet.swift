import CoreData
import SwiftUI

/// Records a dose that was not on the plan. Kept separate from the slot rows so
/// an unplanned dose never silently closes a planned one.
struct ExtraDoseSheet: View {
    @ObservedObject var medication: Medication
    let day: Date

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt: Date = Date()
    @State private var status: DoseStatus = .given
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Medication", value: medication.displayName)
                    if !medication.doseDescription.isEmpty {
                        LabeledContent("Dose", value: medication.doseDescription)
                    }
                }

                Section {
                    DatePicker("Given at", selection: $takenAt)
                    Picker("Status", selection: $status) {
                        ForEach(DoseStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Text("Logged as \(AppSettings.personName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Extra dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: alignTimeWithSelectedDay)
        }
    }

    /// When the user is looking at another day, default the time to that day
    /// rather than to "now", which would file the dose under today.
    private func alignTimeWithSelectedDay() {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(day) else { return }
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        takenAt = calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }

    private func save() {
        let log = DoseLog.make(
            in: context,
            medication: medication,
            scheduledAt: nil,
            status: status,
            personName: AppSettings.personName,
            takenAt: takenAt
        )
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        log.note = trimmed.isEmpty ? nil : trimmed
        PersistenceController.shared.save(context)
        Task { await NotificationScheduler.shared.reschedule() }
        dismiss()
    }
}
