import CoreData
import Foundation

/// What is due, and the one guarded way to record that it was given.
///
/// Pulled out of the notification layer because Siri needs exactly these two
/// answers. A second copy of the duplicate check would be the worst possible
/// duplication: catching a dose given twice is what this app is for.
///
/// **Deliberately not the same operation as ticking off in the Today list.**
/// There a second log is *kept* and shown in red — somebody is looking at the
/// screen and has to see that it happened, so merging it away would hide the
/// very thing worth seeing. Here nobody is looking: a reminder answered on a
/// lock screen, a sentence spoken to Siri. A slot that already has a dose
/// recorded is therefore left alone, and the caller is told so.
enum DoseBook {

    // MARK: - Reading

    struct Plan {
        var medications: [MedicationSnapshot]
        var handledSlots: Set<String>

        func isHandled(_ slot: PlannedSlot) -> Bool {
            handledSlots.contains(Plan.key(medicationID: slot.medicationID, scheduledAt: slot.scheduledAt))
        }

        static func key(medicationID: UUID, scheduledAt: Date) -> String {
            // Rounded to the second: Core Data and CloudKit both introduce
            // sub-second drift, and truncation would turn 7.9999 into a miss.
            "\(medicationID.uuidString)@\(Int(scheduledAt.timeIntervalSinceReferenceDate.rounded()))"
        }
    }

    /// Reads on a background context so neither scheduling nor Siri blocks the
    /// UI.
    ///
    /// Returns an empty plan when no store is open. Answering "nothing" is
    /// right then; asking Core Data anyway is not.
    static func loadPlan(withinDays days: Int) async -> Plan {
        let plan = await PersistenceController.shared.withBackgroundContext { context -> Plan in
            // Every child's medications, not just the first patient's.
            let medicationRequest = NSFetchRequest<Medication>(entityName: "Medication")
            medicationRequest.predicate = NSPredicate(format: "isArchived == NO")
            let medications = ((try? context.fetch(medicationRequest)) ?? []).map { $0.snapshot() }

            // Only slots inside the horizon can still be open, so the log fetch
            // is bounded rather than reading the whole history.
            let horizonEnd = Date().addingTimeInterval(TimeInterval(days + 1) * 86_400)
            let logRequest = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            logRequest.predicate = NSPredicate(
                format: "scheduledAt != nil AND scheduledAt >= %@ AND scheduledAt <= %@",
                Date().addingTimeInterval(-86_400) as NSDate,
                horizonEnd as NSDate
            )
            let logs = (try? context.fetch(logRequest)) ?? []
            let handled = Set(logs.compactMap { log -> String? in
                guard let medicationID = log.medication?.id, let scheduledAt = log.scheduledAt else { return nil }
                return Plan.key(medicationID: medicationID, scheduledAt: scheduledAt)
            })

            return Plan(medications: medications, handledSlots: handled)
        }
        return plan ?? Plan(medications: [], handledSlots: [])
    }

    // MARK: - Writing

    /// What happened, so a caller who has to answer out loud can.
    enum RecordResult: Equatable {
        case recorded
        /// Somebody else — or this person on another device — was faster.
        case alreadyGiven
        case unknownMedication
        /// No store open. Nothing was written and nothing was lost.
        case unavailable
    }

    /// Records a scheduled dose as given, unless that slot already has one.
    ///
    /// Writes on a background context: the app may not even be in the
    /// foreground. Everything goes through `withBackgroundContext`, which
    /// refuses to run when no store is open — and these callers fire at exactly
    /// the moment when that is a real possibility, with the app cold.
    @discardableResult
    static func recordGiven(
        medicationID: UUID,
        scheduledAt: Date,
        personName: String = AppSettings.personName,
        author: String
    ) async -> RecordResult {
        let persistence = PersistenceController.shared

        let result = await persistence.withBackgroundContext(author: author) { context -> RecordResult in
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", medicationID as CVarArg)
            request.fetchLimit = 1
            guard let medication = (try? context.fetch(request))?.first else { return .unknownMedication }

            // Somebody may have ticked this slot off in the meantime — from
            // another device, or from the app itself.
            let existing = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            existing.predicate = NSPredicate(
                format: "medication == %@ AND scheduledAt >= %@ AND scheduledAt <= %@",
                medication,
                scheduledAt.addingTimeInterval(-ScheduleEngine.slotMatchTolerance) as NSDate,
                scheduledAt.addingTimeInterval(ScheduleEngine.slotMatchTolerance) as NSDate
            )
            existing.fetchLimit = 1
            guard ((try? context.fetch(existing))?.first) == nil else { return .alreadyGiven }

            DoseLog.make(
                in: context,
                medication: medication,
                scheduledAt: scheduledAt,
                status: .given,
                personName: personName
            )

            // Through the controller, not `try context.save()`: only the
            // controller refuses a save into a coordinator without stores, and
            // Core Data answers that case with an exception Swift cannot catch.
            return persistence.save(context) ? .recorded : .unavailable
        }

        return result ?? .unavailable
    }

    /// The medication's own name, for a spoken or written reply.
    static func medicationName(for medicationID: UUID) async -> String? {
        await PersistenceController.shared.withBackgroundContext { context -> String? in
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", medicationID as CVarArg)
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?.displayName
        } ?? nil
    }
}
