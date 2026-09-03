import CoreData
import SwiftUI

/// The screen the app exists for: what is due today, what has already been
/// given, and by whom.
struct TodayView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// Which day was "today" the last time the app came to the front, so a day
    /// rolling over while the app slept can be noticed.
    @State private var lastKnownToday: Date = Calendar.current.startOfDay(for: Date())

    @Environment(\.scenePhase) private var scenePhase
    @State private var extraDoseMedication: Medication?
    @State private var showingEventEditor = false
    /// The log whose time is being corrected. The managed object, not the
    /// snapshot: the snapshot is a copy and editing it would change nothing.
    @State private var editingTimeOf: DoseLog?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            DayPlanList(
                date: selectedDate,
                onLogExtraDose: { extraDoseMedication = $0 },
                onEditDoseTime: { editingTimeOf = $0 }
            )
            .navigationTitle(navigationTitle)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { followMidnightIfNeeded() }
            }
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
                        .disabled(patients.isEmpty)
                        Menu {
                            ForEach(patients, id: \.objectID) { child in
                                if !child.activeMedications.isEmpty {
                                    Section(child.displayName) {
                                        ForEach(child.activeMedications, id: \.objectID) { medication in
                                            Button(medication.displayName) { extraDoseMedication = medication }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Log an extra dose", systemImage: "plus.circle")
                        }
                        .disabled(patients.allSatisfy { $0.activeMedications.isEmpty })
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $extraDoseMedication) { medication in
                ExtraDoseSheet(medication: medication, day: selectedDate)
            }
            .sheet(item: $editingTimeOf) { log in
                DoseTimeSheet(log: log)
            }
            .sheet(isPresented: $showingEventEditor) {
                if let first = patients.first {
                    EventEditView(patient: first, event: nil, defaultDate: selectedDate)
                }
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
                jumpToToday()
            } label: {
                VStack(spacing: 1) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    // Only while it would do something. The date has always
                    // been tappable, but it reads as a caption, so nobody
                    // found it — and a button that is invisible until it is
                    // useful beats one that is invisible always.
                    if !isShowingToday {
                        Label("Back to today", systemImage: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isShowingToday)
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

    private var isShowingToday: Bool { calendar.isDateInToday(selectedDate) }

    private func jumpToToday() {
        withAnimation { selectedDate = calendar.startOfDay(for: Date()) }
    }

    private func followMidnightIfNeeded() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = Self.dayAfterMidnight(
            selected: selectedDate,
            lastKnownToday: lastKnownToday,
            now: Date(),
            calendar: calendar
        )
        lastKnownToday = today
    }

    /// Which day to show once the app comes back and midnight has passed.
    ///
    /// Without this the app opens on yesterday: `selectedDate` is set when the
    /// view first appears and nothing moves it. Somebody checking the plan over
    /// breakfast would be ticking off the previous day's doses — the exact
    /// mistake the app exists to prevent, handed to them by the app itself.
    ///
    /// Only for somebody who *was* on today. Anyone who deliberately paged back
    /// to Tuesday and briefly switched apps means to still be on Tuesday.
    ///
    /// Free of view state so the rule can be tested rather than restated in a
    /// test, where the two would drift apart at the first change.
    static func dayAfterMidnight(
        selected: Date,
        lastKnownToday: Date,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        guard today != lastKnownToday else { return selected }
        return selected == lastKnownToday ? today : selected
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
    let date: Date
    var onLogExtraDose: (Medication) -> Void
    /// Handed up: the sheet belongs to the screen, not to the day's list.
    var onEditDoseTime: (DoseLog) -> Void

    @Environment(\.managedObjectContext) private var context
    @AppStorage(AppSettings.personNameKey) private var personName: String = ""

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @FetchRequest private var logs: FetchedResults<DoseLog>
    @FetchRequest private var events: FetchedResults<CareEvent>

    init(
        date: Date,
        onLogExtraDose: @escaping (Medication) -> Void,
        onEditDoseTime: @escaping (DoseLog) -> Void
    ) {
        self.date = date
        self.onLogExtraDose = onLogExtraDose
        self.onEditDoseTime = onEditDoseTime

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        // Across all children: the day is read as one list, so the fetch is not
        // scoped to a single patient.
        //
        // A log belongs to this day either through the slot it answers or,
        // for an unplanned dose, through when it was given.
        let logPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "scheduledAt >= %@ AND scheduledAt < %@", start as NSDate, end as NSDate),
            NSPredicate(format: "scheduledAt == nil AND takenAt >= %@ AND takenAt < %@", start as NSDate, end as NSDate)
        ])
        _logs = FetchRequest(
            sortDescriptors: [SortDescriptor(\DoseLog.takenAt, order: .forward)],
            predicate: logPredicate,
            animation: .default
        )

        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\CareEvent.timestamp, order: .forward)],
            predicate: NSPredicate(
                format: "timestamp >= %@ AND timestamp < %@",
                start as NSDate, end as NSDate
            ),
            animation: .default
        )
    }

    /// With one child on the plan, naming them in every row is noise. With
    /// several it is the difference between the right and the wrong child.
    private var showsChildNames: Bool { patients.count > 1 }

    private var plan: DayPlan {
        ScheduleEngine.dayPlan(
            medications: patients.flatMap(\.activeMedications).map { $0.snapshot() },
            logs: logs.compactMap { $0.snapshot() },
            on: date
        )
    }

    private var medicationsByID: [UUID: Medication] {
        Dictionary(
            patients.flatMap(\.sortedMedications).compactMap { medication in medication.id.map { ($0, medication) } },
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
                                showsChildName: showsChildNames,
                                onSetStatus: { status in apply(status, to: slot, medication: lookup[slot.medication.id]) },
                                onClear: { clearLogs(of: slot) },
                                onEditTime: { if let entry = resolvedLog(of: slot) { onEditDoseTime(entry) } }
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
                        ExtraDoseRow(
                            extra: extra,
                            showsChildName: showsChildNames,
                            onDelete: { deleteLog(id: extra.log.id) },
                            onEditTime: { if let entry = managedLog(id: extra.log.id) { onEditDoseTime(entry) } }
                        )
                    }
                } header: {
                    Label("Extra doses", systemImage: "plus.circle")
                }
            }

            if !events.isEmpty {
                Section {
                    ForEach(events, id: \.objectID) { event in
                        if let owner = event.patient {
                            NavigationLink {
                                EventEditView(patient: owner, event: event, defaultDate: date)
                            } label: {
                                EventRow(event: event, showsChildName: showsChildNames)
                            }
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
            if patients.allSatisfy({ $0.activeMedications.isEmpty }) {
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

    /// The managed object behind a slot's decisive log — the `.given` entry
    /// when there is one, since that is the time the row shows.
    private func resolvedLog(of slot: DaySlot) -> DoseLog? {
        guard let id = slot.resolvedLog?.id else { return nil }
        return managedLog(id: id)
    }

    private func managedLog(id: UUID) -> DoseLog? {
        logs.first { $0.id == id }
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
    TodayView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
