import CoreData
import SwiftUI

/// Everything worth remembering that is not a dose: a temperature, a side
/// effect, a doctor's visit. Shared like the rest of the plan, so whoever takes
/// over already knows what happened.
struct EventListView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CareEvent.timestamp, order: .reverse)],
        animation: .default
    )
    private var events: FetchedResults<CareEvent>

    @State private var choosingChild = false
    @State private var newEventChild: Patient?

    private var showsChildNames: Bool { patients.count > 1 }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No events yet", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Record a fever, a side effect or a doctor's visit so everyone stays in the picture.")
                    } actions: {
                        Button("Log an event", action: startCreating)
                            .buttonStyle(.borderedProminent)
                            .disabled(patients.isEmpty)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedEvents, id: \.day) { group in
                    Section {
                        ForEach(group.events, id: \.objectID) { event in
                            if let owner = event.patient {
                                NavigationLink {
                                    EventEditView(patient: owner, event: event, defaultDate: event.timestamp ?? Date())
                                } label: {
                                    EventRow(event: event, showsChildName: showsChildNames)
                                }
                            }
                        }
                        .onDelete { offsets in delete(offsets, in: group.events) }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startCreating) {
                        Label("Log an event", systemImage: "plus")
                    }
                    .disabled(patients.isEmpty)
                }
            }
            .confirmationDialog("For which child?", isPresented: $choosingChild, titleVisibility: .visible) {
                ForEach(patients, id: \.objectID) { child in
                    Button(child.displayName) { newEventChild = child }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $newEventChild) { child in
                EventEditView(patient: child, event: nil, defaultDate: Date())
            }
        }
    }

    private func startCreating() {
        if patients.count == 1 {
            newEventChild = patients.first
        } else if patients.count > 1 {
            choosingChild = true
        }
    }

    private var groupedEvents: [(day: Date, events: [CareEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp ?? .distantPast) }
        return grouped
            .map { (day: $0.key, events: $0.value.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }) }
            .sorted { $0.day > $1.day }
    }

    private func delete(_ offsets: IndexSet, in events: [CareEvent]) {
        for index in offsets where events.indices.contains(index) {
            context.delete(events[index])
        }
        PersistenceController.shared.save(context)
    }
}

struct EventRow: View {
    @ObservedObject var event: CareEvent
    var showsChildName: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.categoryEnum.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(event.categoryEnum.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                if showsChildName, let owner = event.patient, let id = owner.id {
                    Text(owner.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MedColor.forPatient(id))
                        .textCase(.uppercase)
                }
                HStack(spacing: 6) {
                    Text(event.displayTitle).font(.body.weight(.medium))
                    if let measurement = event.measurementDescription {
                        Text(measurement)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(event.categoryEnum.tint)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let note = event.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let time = TimeText.of(event.timestamp ?? Date())
        let name = event.personName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return time }
        return String(localized: "\(time) · logged by \(name)")
    }
}

#Preview {
    EventListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
