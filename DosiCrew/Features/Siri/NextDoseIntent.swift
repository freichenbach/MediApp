import AppIntents
import Foundation

/// "Wann ist die nächste Gabe?"
///
/// The question people actually ask each other, answered without unlocking
/// anything. Everything it needs already exists: `DoseBook.loadPlan` reads the
/// medications and what has been ticked off, `ScheduleEngine.upcomingSlots`
/// works out what comes next. This only puts a sentence around it.
struct NextDoseIntent: AppIntent {

    static var title: LocalizedStringResource = "Next dose"
    static var description = IntentDescription("Asks when the next medication is due.")

    /// Answered in place. Opening the app would defeat the point: the whole
    /// value is getting the answer with one hand full.
    static var openAppWhenRun = false

    @Parameter(title: "Child")
    var child: String?

    /// How far ahead to look. Beyond a couple of days "next" stops being a
    /// useful answer, and the plan is only loaded that far anyway.
    private static let horizonInDays = 2

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let plan = await DoseBook.loadPlan(withinDays: Self.horizonInDays)

        let wanted = child?.trimmingCharacters(in: .whitespacesAndNewlines)
        let medications = plan.medications.filter { medication in
            guard let wanted, !wanted.isEmpty else { return true }
            return medication.patientName.localizedCaseInsensitiveContains(wanted)
        }

        guard !medications.isEmpty else {
            if let wanted, !wanted.isEmpty {
                return .result(dialog: "I have no medications for \(wanted).")
            }
            return .result(dialog: "There are no medications in the plan yet.")
        }

        let upcoming = ScheduleEngine.upcomingSlots(
            medications: medications,
            after: Date(),
            withinDays: Self.horizonInDays,
            limit: 20
        )

        guard let next = upcoming.first(where: { !plan.isHandled($0) }),
              let medication = medications.first(where: { $0.id == next.medicationID })
        else {
            return .result(dialog: "Nothing else is due in the next two days.")
        }

        return .result(dialog: IntentDialog(Self.sentence(for: next, medication: medication)))
    }

    /// Names the child whenever there is one, not only when several are on the
    /// plan. Spoken aloud there is no coloured label to fall back on, and "5 ml
    /// Amoxicillin at eight" is the kind of answer that gets given to the wrong
    /// child.
    ///
    /// Two sentence templates, not four: the dose and the medication are joined
    /// first, so a translator sees "%@ for %@ at %@." once instead of the same
    /// sentence with and without a dose.
    private static func sentence(
        for slot: PlannedSlot,
        medication: MedicationSnapshot
    ) -> LocalizedStringResource {
        let time = TimeText.of(slot.scheduledAt)
        let dose = Medication.doseDescription(amount: medication.doseAmount, unit: medication.doseUnit)
        let what = dose.isEmpty ? medication.name : "\(dose) \(medication.name)"
        let name = medication.patientName.isEmpty
            ? String(localized: "your child")
            : medication.patientName

        guard !Calendar.current.isDateInToday(slot.scheduledAt) else {
            return "\(what) for \(name) at \(time)."
        }
        let day = slot.scheduledAt.formatted(.dateTime.weekday(.wide))
        return "\(what) for \(name) on \(day) at \(time)."
    }
}
