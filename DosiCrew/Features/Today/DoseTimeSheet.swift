import CoreData
import SwiftUI

/// Corrects when a dose was actually given.
///
/// Ticking off records the moment of the tap, which is right almost always and
/// wrong in the one case that matters: the dose goes in at eight, the phone
/// comes out at half past nine. On a shared plan that gap is not cosmetic —
/// the next person reads "given at 09:30" and works out the following dose
/// from the wrong time.
///
/// Date *and* time, not just time. An evening dose given at half past midnight
/// belongs to the evening slot and to the following day, and forcing it onto
/// the planned day would be a different kind of lie.
struct DoseTimeSheet: View {
    @ObservedObject var log: DoseLog

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt = Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Given at",
                        selection: $takenAt,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text("When the dose actually went in. Everyone sharing the plan sees this time.")
                }

                if let scheduledAt = log.scheduledAt {
                    Section {
                        LabeledContent("Planned for", value: TimeText.of(scheduledAt))
                    }
                }
            }
            .navigationTitle("Time given")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        // Not `Date()` as the fallback: a log without a time is odd enough that
        // inventing "now" would hide it. The planned time is the honest guess.
        takenAt = log.takenAt ?? log.scheduledAt ?? Date()
    }

    private func save() {
        log.takenAt = takenAt
        PersistenceController.shared.save(context)
        dismiss()
    }
}
