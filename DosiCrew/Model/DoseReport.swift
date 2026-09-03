import Foundation

/// Turns the plan and what was ticked off into something a doctor can read in
/// a minute.
///
/// The whole point of the app — several people, one plan — is also what makes
/// this worth printing: nobody involved has the full picture in their head, and
/// "how did the last two weeks actually go" is the first question in the
/// consulting room.
///
/// Deliberately a pure function over snapshots, with no Core Data and no UI, so
/// the counting can be tested. The counting is the part that must not be wrong.
enum DoseReport {

    // MARK: - What a dose did

    /// What became of one planned dose.
    ///
    /// `notRecorded` is the one that needs care. It does not mean the dose was
    /// missed — it means nobody ticked it off, and the two are not the same.
    /// Somebody may have given it with wet hands and never picked the phone
    /// back up. Reporting that as "missed" to a doctor would invent a fact, and
    /// the doctor might change a prescription over it, so it is named for what
    /// it is and counted separately everywhere.
    enum Outcome: String {
        case given
        case late
        case skipped
        case refused
        case notRecorded
    }

    /// How long after the planned time a dose still counts as on time.
    ///
    /// An hour is generous, and generous is right here: the alternative is a
    /// report full of "late" for doses that were entirely fine, which trains
    /// the reader to ignore the column. What matters clinically is the dose
    /// that slipped by hours, not by ten minutes.
    static let lateThreshold: TimeInterval = 60 * 60

    /// A dose is only counted at all once its planned time has passed, plus
    /// this. Without the grace period the dose due in twenty minutes shows up
    /// as "not recorded" the moment the report is made.
    static let dueGracePeriod: TimeInterval = 30 * 60

    // MARK: - Rows

    /// A second person giving the same dose, unaware of the first.
    ///
    /// This is the failure the app was built to prevent, so it is the last
    /// thing the report may quietly tidy away: the child had twice the dose,
    /// and a doctor reading "given: 1" would never know.
    struct Duplicate: Equatable {
        let takenAt: Date?
        let personName: String?
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let medicationName: String
        let doseDescription: String
        let scheduledAt: Date
        let takenAt: Date?
        let amountGiven: Double
        let outcome: Outcome
        let personName: String?
        let note: String?
        /// Everything given against this slot beyond the first dose.
        let duplicates: [Duplicate]

        /// Minutes between plan and reality, negative when early. Nil unless
        /// the dose was actually recorded as given.
        var deviationMinutes: Int? {
            guard let takenAt, outcome == .given || outcome == .late else { return nil }
            return Int(takenAt.timeIntervalSince(scheduledAt) / 60)
        }
    }

    /// A dose given without a slot to hang it on — the extra paracetamol at two
    /// in the morning. Often the most interesting line on the page.
    struct ExtraEntry: Identifiable, Equatable {
        let id: String
        let medicationName: String
        let doseDescription: String
        let takenAt: Date
        let amountGiven: Double
        let personName: String?
        let note: String?
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        let entries: [Entry]
        let extras: [ExtraEntry]

        var id: Date { date }
        var isEmpty: Bool { entries.isEmpty && extras.isEmpty }
    }

    struct EventEntry: Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let category: EventCategory
        let title: String
        let measurement: String?
        let note: String?
        let personName: String?
    }

    // MARK: - Counting

    /// Per medication, because that is the unit a prescription is written in.
    struct MedicationTally: Identifiable, Equatable {
        let id: UUID
        let name: String
        let doseDescription: String
        let instructions: String?
        var planned = 0
        var given = 0
        var late = 0
        var skipped = 0
        var refused = 0
        var notRecorded = 0
        var extras = 0
        var duplicates = 0

        /// Of the doses somebody actually answered for, how many went in.
        ///
        /// The ones nobody recorded are left out of both halves on purpose.
        /// Counting them as missed would overstate the problem; counting them
        /// as given would hide it. They get their own number, next to this one.
        var recordedShare: Double? {
            let answered = given + late + skipped + refused
            guard answered > 0 else { return nil }
            return Double(given + late) / Double(answered)
        }
    }

    struct Report: Equatable {
        let patientName: String
        let patientBirthDate: Date?
        let patientWeightKg: Double
        let from: Date
        let to: Date
        let generatedAt: Date
        let tallies: [MedicationTally]
        let days: [Day]
        let events: [EventEntry]

        var planned: Int { tallies.reduce(0) { $0 + $1.planned } }
        var given: Int { tallies.reduce(0) { $0 + $1.given } }
        var late: Int { tallies.reduce(0) { $0 + $1.late } }
        var skipped: Int { tallies.reduce(0) { $0 + $1.skipped } }
        var refused: Int { tallies.reduce(0) { $0 + $1.refused } }
        var notRecorded: Int { tallies.reduce(0) { $0 + $1.notRecorded } }
        var extras: Int { tallies.reduce(0) { $0 + $1.extras } }
        var duplicates: Int { tallies.reduce(0) { $0 + $1.duplicates } }

        var isEmpty: Bool { days.allSatisfy(\.isEmpty) && events.isEmpty }
    }

    // MARK: - Building

    /// Walks the period day by day, asking the same engine the Today screen
    /// asks. Reusing it is the point: a report that counted slots its own way
    /// would drift from what people saw when they ticked them off, and the
    /// difference would only ever show up in a doctor's office.
    static func build(
        patientName: String,
        patientBirthDate: Date?,
        patientWeightKg: Double,
        medications: [MedicationSnapshot],
        logs: [DoseLogSnapshot],
        events: [EventEntry],
        from: Date,
        to: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Report {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)

        var tallies: [UUID: MedicationTally] = [:]
        for medication in medications {
            tallies[medication.id] = MedicationTally(
                id: medication.id,
                name: medication.name,
                doseDescription: Medication.doseDescription(
                    amount: medication.doseAmount,
                    unit: medication.doseUnit
                ),
                instructions: medication.instructions
            )
        }

        var days: [Day] = []
        var day = start
        while day <= end {
            let plan = ScheduleEngine.dayPlan(
                medications: medications,
                logs: logs,
                on: day,
                calendar: calendar
            )

            var entries: [Entry] = []
            for slot in plan.slots {
                // A slot whose time has not come yet is not a gap in the
                // record, it is the future. Leaving it out keeps "not recorded"
                // meaning something.
                guard slot.scheduledAt.addingTimeInterval(dueGracePeriod) <= now else { continue }

                let entry = self.entry(for: slot)
                entries.append(entry)
                tallies[slot.medication.id]?.planned += 1
                switch entry.outcome {
                case .given: tallies[slot.medication.id]?.given += 1
                case .late: tallies[slot.medication.id]?.late += 1
                case .skipped: tallies[slot.medication.id]?.skipped += 1
                case .refused: tallies[slot.medication.id]?.refused += 1
                case .notRecorded: tallies[slot.medication.id]?.notRecorded += 1
                }
                tallies[slot.medication.id]?.duplicates += entry.duplicates.count
            }

            var extras: [ExtraEntry] = []
            for extra in plan.extras {
                guard let takenAt = extra.log.takenAt else { continue }
                extras.append(
                    ExtraEntry(
                        id: extra.log.id.uuidString,
                        medicationName: extra.medication.name,
                        doseDescription: Medication.doseDescription(
                            amount: extra.medication.doseAmount,
                            unit: extra.medication.doseUnit
                        ),
                        takenAt: takenAt,
                        amountGiven: extra.log.amountGiven,
                        personName: extra.log.personName,
                        note: extra.log.note
                    )
                )
                tallies[extra.medication.id]?.extras += 1
            }

            days.append(Day(date: day, entries: entries, extras: extras))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let ordered = medications.compactMap { tallies[$0.id] }
            .filter { $0.planned > 0 || $0.extras > 0 }

        return Report(
            patientName: patientName,
            patientBirthDate: patientBirthDate,
            patientWeightKg: patientWeightKg,
            from: start,
            to: end,
            generatedAt: now,
            tallies: ordered,
            days: days,
            events: events.filter { $0.timestamp >= start }.sorted { $0.timestamp < $1.timestamp }
        )
    }

    /// Decides what one slot amounts to.
    ///
    /// Several logs on one slot is not a data error, it is the duplicate the
    /// Today screen shows in red — two people gave the same dose. The report
    /// keeps the first one that says "given", because that is the dose that
    /// went in; the second shows up as an extra elsewhere and is counted there.
    private static func entry(for slot: DaySlot) -> Entry {
        let sorted = slot.logs.sorted { ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast) }
        let decisive = sorted.first { $0.status == .given } ?? sorted.first
        // Only doses that actually went in count as duplicates: a skip
        // recorded next to a dose is somebody correcting themselves, not a
        // second syringe.
        let duplicates = sorted
            .filter { $0.status == .given && $0.id != decisive?.id }
            .map { Duplicate(takenAt: $0.takenAt, personName: $0.personName) }

        guard let log = decisive else {
            return Entry(
                id: slot.id,
                medicationName: slot.medication.name,
                doseDescription: Medication.doseDescription(
                    amount: slot.medication.doseAmount,
                    unit: slot.medication.doseUnit
                ),
                scheduledAt: slot.scheduledAt,
                takenAt: nil,
                amountGiven: 0,
                outcome: .notRecorded,
                personName: nil,
                note: nil,
                duplicates: []
            )
        }

        let outcome: Outcome
        switch log.status {
        case .skipped:
            outcome = .skipped
        case .refused:
            outcome = .refused
        case .given:
            if let takenAt = log.takenAt,
               takenAt.timeIntervalSince(slot.scheduledAt) > lateThreshold {
                outcome = .late
            } else {
                outcome = .given
            }
        }

        return Entry(
            id: slot.id,
            medicationName: slot.medication.name,
            doseDescription: Medication.doseDescription(
                amount: slot.medication.doseAmount,
                unit: slot.medication.doseUnit
            ),
            scheduledAt: slot.scheduledAt,
            takenAt: log.takenAt,
            amountGiven: log.amountGiven,
            outcome: outcome,
            personName: log.personName,
            note: log.note,
            duplicates: duplicates
        )
    }
}
