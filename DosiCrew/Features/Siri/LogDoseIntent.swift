import AppIntents
import Foundation

/// "Amoxicillin gegeben."
///
/// The case this is really for: one hand holds the child, the other the
/// syringe, and neither is free to unlock a phone. Ticking off late, or not at
/// all, is how a dose ends up given twice.
struct LogDoseIntent: AppIntent {

    static var title: LocalizedStringResource = "Record a dose"
    static var description = IntentDescription("Records a scheduled dose as given.")

    static var openAppWhenRun = false

    @Parameter(title: "Medication", requestValueDialog: "Which medication?")
    var medication: MedicationEntity

    /// How far a spoken dose may sit from its planned time and still be that
    /// dose.
    ///
    /// Six hours is generous on purpose: a morning dose confirmed at lunchtime
    /// is still the morning dose, and refusing it would push the person back to
    /// the screen — the thing this exists to avoid. Beyond that the guess stops
    /// being safe, and saying so is better than attaching the dose to the wrong
    /// slot.
    private static let matchWindow: TimeInterval = 6 * 60 * 60

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let plan = await DoseBook.loadPlan(withinDays: 1)

        guard let snapshot = plan.medications.first(where: { $0.id == medication.id }) else {
            return .result(dialog: "\(medication.name) is not in the plan any more.")
        }

        let now = Date()
        // Today's slots for this one medication, logs left out: what has
        // already been answered is decided from `plan` a moment later, and it
        // knows about the other iPhones too.
        let today = ScheduleEngine.dayPlan(medications: [snapshot], logs: [], on: now)
        let open = today.slots.filter {
            !plan.isHandled(PlannedSlot(medicationID: snapshot.id, scheduledAt: $0.scheduledAt))
        }

        guard let slot = open.min(by: {
            abs($0.scheduledAt.timeIntervalSince(now)) < abs($1.scheduledAt.timeIntervalSince(now))
        }), abs(slot.scheduledAt.timeIntervalSince(now)) <= Self.matchWindow else {
            return .result(dialog: Self.nothingOpen(for: snapshot, hadSlots: !today.slots.isEmpty))
        }

        let result = await DoseBook.recordGiven(
            medicationID: snapshot.id,
            scheduledAt: slot.scheduledAt,
            author: "siri"
        )

        // The pending reminder for this slot has to go, exactly as when the
        // dose is ticked off in the notification.
        if result == .recorded {
            Task.detached { await NotificationScheduler.shared.reschedule() }
        }

        return .result(dialog: Self.reply(for: result, medication: snapshot, at: slot.scheduledAt))
    }

    private static func nothingOpen(
        for medication: MedicationSnapshot,
        hadSlots: Bool
    ) -> IntentDialog {
        hadSlots
            ? IntentDialog("Every \(medication.name) dose for today is already ticked off.")
            : IntentDialog("\(medication.name) is not scheduled for today.")
    }

    /// Says what happened rather than a bare "done".
    ///
    /// `alreadyGiven` is the answer worth hearing: somebody else was faster,
    /// and knowing that is the difference between one dose and two.
    private static func reply(
        for result: DoseBook.RecordResult,
        medication: MedicationSnapshot,
        at scheduledAt: Date
    ) -> IntentDialog {
        let time = TimeText.of(scheduledAt)
        let name = medication.patientName.isEmpty
            ? String(localized: "your child")
            : medication.patientName

        switch result {
        case .recorded:
            return IntentDialog("Recorded: \(medication.name) for \(name) at \(time).")
        case .alreadyGiven:
            return IntentDialog("Somebody has already ticked off the \(time) dose of \(medication.name). Do not give it again.")
        case .unknownMedication:
            return IntentDialog("\(medication.name) is not in the plan any more.")
        case .unavailable:
            return IntentDialog("The plan could not be opened, so nothing was recorded. Please tick it off in DosiCrew.")
        }
    }
}
