import CoreData
import SwiftUI

/// The screen the app exists for: what is due today, what has already been
/// given, and by whom.
struct TodayView: View {
    @ObservedObject var patient: Patient

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var extraDoseMedication: Medication?
    @State private var showingEventEditor = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            DayPlanList(
                patient: patient,
                date: selectedDate,
                onLogExtraDose: { extraDoseMedication = $0 }
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { dateBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEventEditor = true
                        } label: {
                            Label("Log an event", systemImage: "exclamationmark.bubble")
                        }
                        Menu {
                            ForEach(patient.activeMedications, id: \.objectID) { medication in
                                Button(medication.displayName) { extraDoseMedication = medication }
                            }
                        } label: {
                            Label("Log an extra dose", systemImage: "plus.circle")
                        }
                        .disabled(patient.activeMedications.isEmpty)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $extraDoseMedication) { medication in
                ExtraDoseSheet(medication: medication, day: selectedDate)
            }
            .sheet(isPresented: $showingEventEditor) {
                EventEditView(patient: patient, event: nil, defaultDate: selectedDate)
            }
        }
    }

    // MARK: - Date bar

    private var dateBar: some View {
        HStack(spacing: 12) {
            Button {
                shiftDay(by: -1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 32)
            }
            .accessibilityLabel("Previous day")

            Button {
                withAnimation { selectedDate = calendar.startOfDay(for: Date()) }
            } label: {
                Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Jump back to today")

            Button {
                shiftDay(by: 1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 32)
            }
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var navigationTitle: String {
        if calendar.isDateInToday(selectedDate) { return String(localized: "Today") }
        if calendar.isDateInYesterday(selectedDate) { return String(localized: "Yesterday") }
        if calendar.isDateInTomorrow(selectedDate) { return String(localized: "Tomorrow") }
        return selectedDate.formatted(.dateTime.day().month(.abbreviated))
    }

    private func shiftDay(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        withAnimation { selectedDate = calendar.startOfDay(for: next) }
    }
}

// MARK: - Day plan list

/// Split out so the fetch requests can be built from `date` in `init` — a
/// `@FetchRequest` predicate cannot depend on a `@State` of the same view.
private struct DayPlanList: View {
    @ObservedObject var patient: Patient
    let date: Date
    var onLogExtraDose: (Medication) -> Void

    @Environment(\.managedObjectContext) private var context
    @AppStorage(AppSettings.personNameKey) private var personName: String = ""

    @FetchRequest private var logs: FetchedResults<DoseLog>
    @FetchRequest private var events: FetchedResults<CareEvent>

    init(patient: Patient, date: Date, onLogExtraDose: @escaping (Medication) -> Void) {
        self.patient = patient
        self.date = date
        self.onLogExtraDose = onLogExtraDose

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        // A log belongs to this day either through the slot it answers or,
        // for an unplanned dose, through when it was given.
        let logPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "medication.patient == %@", patient),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "scheduledAt >= %@ AND scheduledAt < %@", start as NSDate, end as NSDate),
                NSPredicate(format: "scheduledAt == nil AND takenAt >= %@ AND takenAt < %@", start as NSDate, end as NSDate)
            ])
        ])
        _logs = FetchRequest(
            sortDescriptors: [SortDescriptor(\DoseLog.takenAt, order: .forward)],
            predicate: logPredicate,
            animation: .default
        )

        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\CareEvent.timestamp, order: .forward)],
            predicate: NSPredicate(
                format: "patient == %@ AND timestamp >= %@ AND timestamp < %@",
                patient, start as NSDate, end as NSDate
            ),
            animation: .default
        )
    }

    private var plan: DayPlan {
        ScheduleEngine.dayPlan(
            medications: patient.activeMedications.map { $0.snapshot() },
            logs: logs.compactMap { $0.snapshot() },
            on: date
        )
    }

    private var medicationsByID: [UUID: Medication] {
        Dictionary(
            patient.sortedMedications.compactMap { medication in medication.id.map { ($0, medication) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        let plan = self.plan
        let lookup = medicationsByID

        List {
            if plan.slots.isEmpty && plan.extras.isEmpty && events.isEmpty {
                emptyState
            }

            if plan.duplicateCount > 0 {
                Section {
                    duplicateBanner
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(DayPart.allCases) { part in
                let slots = plan.slots.filter { dayPart(of: $0.scheduledAt) == part }
                if !slots.isEmpty {
                    Section {
                        ForEach(slots) { slot in
                            DoseSlotRow(
                                slot: slot,
                                medication: lookup[slot.medication.id],
                                onSetStatus: { status in apply(status, to: slot, medication: lookup[slot.medication.id]) },
                                onClear: { clearLogs(of: slot) }
                            )
                        }
                    } header: {
                        Label(part.label, systemImage: part.symbolName)
                    }
                }
            }

            if !plan.extras.isEmpty {
                Section {
                    ForEach(plan.extras) { extra in
                        ExtraDoseRow(extra: extra) { deleteLog(id: extra.log.id) }
                    }
                } header: {
                    Label("Extra doses", systemImage: "plus.circle")
                }
            }

            if !events.isEmpty {
                Section {
                    ForEach(events, id: \.objectID) { event in
                        NavigationLink {
                            EventEditView(patient: patient, event: event, defaultDate: date)
                        } label: {
                            EventRow(event: event)
                        }
                    }
                } header: {
                    Label("Events", systemImage: "exclamationmark.bubble")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing planned", systemImage: "checkmark.circle")
        } description: {
            Text("No doses are scheduled for this day.")
        } actions: {
            if patient.activeMedications.isEmpty {
                Text("Add a medication under the Medications tab to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.clear)
    }

    /// Deliberately loud: a dose given twice is the failure mode this app is
    /// built to prevent, so it gets its own banner rather than a subtle tint.
    private var duplicateBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Given twice").font(.subheadline.weight(.semibold))
                Text("A dose below was ticked off by more than one person. Check with the others before giving anything else.")
                    .font(.footnote)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayPart(of date: Date) -> DayPart {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return DayPart.containing(minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    // MARK: Actions

    private func apply(_ status: DoseStatus, to slot: DaySlot, medication: Medication?) {
        guard let medication else { return }
        DoseLog.make(
            in: context,
            medication: medication,
            scheduledAt: slot.scheduledAt,
            status: status,
            personName: AppSettings.personName
        )
        commit()
    }

    private func clearLogs(of slot: DaySlot) {
        let ids = Set(slot.logs.map(\.id))
        for log in logs {
            guard let id = log.id, ids.contains(id) else { continue }
            context.delete(log)
        }
        commit()
    }

    private func deleteLog(id: UUID) {
        for log in logs where log.id == id {
            context.delete(log)
        }
        commit()
    }

    private func commit() {
        PersistenceController.shared.save(context)
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

#Preview {
    let controller = PersistenceController.preview
    return TodayView(patient: Patient.fetchOrCreate(in: controller.viewContext))
        .environment(\.managedObjectContext, controller.viewContext)
}
