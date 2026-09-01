import CoreData
import SwiftUI

/// Everything worth remembering that is not a dose: a temperature, a side
/// effect, a doctor's visit. Shared like the rest of the plan, so whoever takes
/// over already knows what happened.
struct EventListView: View {
    @ObservedObject var patient: Patient

    @Environment(\.managedObjectContext) private var context

    @FetchRequest private var events: FetchedResults<CareEvent>
    @State private var creating = false

    init(patient: Patient) {
        self.patient = patient
        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\CareEvent.timestamp, order: .reverse)],
            predicate: NSPredicate(format: "patient == %@", patient),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No events yet", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Record a fever, a side effect or a doctor's visit so everyone stays in the picture.")
                    } actions: {
                        Button("Log an event") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedEvents, id: \.day) { group in
                    Section {
                        ForEach(group.events, id: \.objectID) { event in
                            NavigationLink {
                                EventEditView(patient: patient, event: event, defaultDate: event.timestamp ?? Date())
                            } label: {
                                EventRow(event: event)
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
                    Button { creating = true } label: {
                        Label("Log an event", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                EventEditView(patient: patient, event: nil, defaultDate: Date())
            }
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.categoryEnum.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(event.categoryEnum.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
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
    let controller = PersistenceController.preview
    return EventListView(patient: Patient.fetchOrCreate(in: controller.viewContext))
        .environment(\.managedObjectContext, controller.viewContext)
}
