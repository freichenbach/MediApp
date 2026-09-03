import CoreData
import SwiftUI

struct MedicationListView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @State private var editing: Medication?
    @State private var choosingChild = false

    private var allMedications: [Medication] { patients.flatMap(\.sortedMedications) }
    private var archived: [Medication] { allMedications.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            List {
                if patients.isEmpty {
                    ContentUnavailableView {
                        Label("No children yet", systemImage: "person.2")
                    } description: {
                        Text("Add a child first, then their medications.")
                    }
                    .listRowBackground(Color.clear)
                } else if allMedications.allSatisfy(\.isArchived) {
                    ContentUnavailableView {
                        Label("No medications yet", systemImage: "pills")
                    } description: {
                        Text("Add a medication with its dose and schedule, and it will show up on the Today screen.")
                    } actions: {
                        Button("Add medication", action: startAdding)
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(patients, id: \.objectID) { child in
                    let medications = child.activeMedications
                    if !medications.isEmpty {
                        Section {
                            ForEach(medications, id: \.objectID) { medication in
                                Button { editing = medication } label: {
                                    MedicationRow(medication: medication)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button { archive(medication) } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(.orange)
                                }
                            }
                        } header: {
                            Text(child.displayName)
                        }
                    }
                }

                if !archived.isEmpty {
                    Section {
                        ForEach(archived, id: \.objectID) { medication in
                            Button { editing = medication } label: {
                                MedicationRow(medication: medication)
                                    .opacity(0.55)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(medication) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { unarchive(medication) } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        Text("Archived")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startAdding) {
                        Label("Add medication", systemImage: "plus")
                    }
                    .disabled(patients.isEmpty)
                }
            }
            .sheet(item: $editing, onDismiss: discardUnsavedChanges) { medication in
                MedicationEditView(medication: medication)
            }
            .confirmationDialog("For which child?", isPresented: $choosingChild, titleVisibility: .visible) {
                ForEach(patients, id: \.objectID) { child in
                    Button(child.displayName) { addMedication(to: child) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Actions

    /// With a single child there is nothing to ask; with several, guessing
    /// would be the wrong kind of convenience.
    private func startAdding() {
        if patients.count == 1, let only = patients.first {
            addMedication(to: only)
        } else if patients.count > 1 {
            choosingChild = true
        }
    }

    private func addMedication(to child: Patient) {
        let medication = Medication.make(in: context, patient: child)
        ScheduleRule.make(in: context, medication: medication)
        editing = medication
    }

    /// Archiving keeps the history intact — deleting a medication would take
    /// every logged dose with it.
    private func archive(_ medication: Medication) {
        medication.isArchived = true
        commit()
    }

    private func unarchive(_ medication: Medication) {
        medication.isArchived = false
        commit()
    }

    private func delete(_ medication: Medication) {
        context.delete(medication)
        commit()
    }

    /// Runs once the editor sheet is gone.
    ///
    /// "Add medication" inserts the object before the editor opens, so
    /// cancelling has to undo that. Doing it inside the editor crashed the app:
    /// the rollback invalidated the object while the sheet — and its `item`
    /// binding — were still reading from it. After a save there is nothing
    /// pending, so this is a no-op then.
    private func discardUnsavedChanges() {
        guard context.hasChanges else { return }
        context.rollback()
    }

    private func commit() {
        PersistenceController.shared.save(context)
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

struct MedicationRow: View {
    @ObservedObject var medication: Medication

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(medication.color.opacity(0.18))
                Image(systemName: medication.formEnum.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(medication.color)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(medication.displayName).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        let dose = medication.doseDescription
        if !dose.isEmpty { parts.append(dose) }
        let times = medication.sortedRules.flatMap(\.minutes)
        if times.isEmpty {
            parts.append(String(localized: "No schedule"))
        } else {
            parts.append(ScheduleSummary.times(times))
        }
        return parts.joined(separator: " · ")
    }
}

/// Formatting helpers shared by the list row and the schedule editor.
enum ScheduleSummary {
    static func times(_ minutes: [Int]) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatted = ScheduleEngine.normalizedMinutes(minutes).compactMap { minute -> String? in
            guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: today)
            else { return nil }
            return TimeText.of(date)
        }
        return formatted.joined(separator: ", ")
    }

    static func weekdayNames(_ weekdays: Set<Int>) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted()
            .compactMap { index in symbols.indices.contains(index - 1) ? symbols[index - 1] : nil }
            .joined(separator: ", ")
    }
}

#Preview {
    MedicationListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
