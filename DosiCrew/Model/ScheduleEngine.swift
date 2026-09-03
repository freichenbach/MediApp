import Foundation

// MARK: - Value snapshots
//
// The engine deliberately knows nothing about Core Data. Everything it needs is
// copied into these plain structs first, which keeps the scheduling rules unit
// testable without a managed object context, a store, or an iCloud account.

struct ScheduleRuleSnapshot: Equatable, Hashable {
    var minutesOfDay: [Int]
    var recurrence: Recurrence
    var intervalDays: Int
    var weekdayMask: Int
    var startDate: Date?
    var endDate: Date?

    init(
        minutesOfDay: [Int],
        recurrence: Recurrence = .daily,
        intervalDays: Int = 1,
        weekdayMask: Int = ScheduleEngine.allWeekdaysMask,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.minutesOfDay = ScheduleEngine.normalizedMinutes(minutesOfDay)
        self.recurrence = recurrence
        self.intervalDays = max(1, intervalDays)
        self.weekdayMask = weekdayMask
        self.startDate = startDate
        self.endDate = endDate
    }
}

struct MedicationSnapshot: Equatable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// Which child this belongs to. Carried through the engine so a slot can
    /// always say whose dose it is — on screen and in a notification.
    var patientID: UUID
    var patientName: String
    var doseAmount: Double
    var doseUnit: String
    var form: MedicationForm
    var colorHex: String
    var instructions: String?
    var startDate: Date?
    var endDate: Date?
    var isArchived: Bool
    var rules: [ScheduleRuleSnapshot]

    init(
        id: UUID,
        name: String,
        patientID: UUID = UUID(),
        patientName: String = "",
        doseAmount: Double = 0,
        doseUnit: String = "",
        form: MedicationForm = .tablet,
        colorHex: String = MedColor.fallback.rawValue,
        instructions: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isArchived: Bool = false,
        rules: [ScheduleRuleSnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.patientID = patientID
        self.patientName = patientName
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.form = form
        self.colorHex = colorHex
        self.instructions = instructions
        self.startDate = startDate
        self.endDate = endDate
        self.isArchived = isArchived
        self.rules = rules
    }
}

struct DoseLogSnapshot: Equatable, Hashable, Identifiable {
    var id: UUID
    var medicationID: UUID
    /// The planned slot this log answers. `nil` marks an extra dose given
    /// outside the schedule.
    var scheduledAt: Date?
    var takenAt: Date?
    var status: DoseStatus
    var amountGiven: Double
    var personName: String?
    var note: String?

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduledAt: Date? = nil,
        takenAt: Date? = nil,
        status: DoseStatus = .given,
        amountGiven: Double = 0,
        personName: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduledAt = scheduledAt
        self.takenAt = takenAt
        self.status = status
        self.amountGiven = amountGiven
        self.personName = personName
        self.note = note
    }
}

// MARK: - Engine output

struct PlannedSlot: Hashable {
    var medicationID: UUID
    var scheduledAt: Date
}

/// One planned dose on a given day, together with everything that was logged
/// against it.
struct DaySlot: Identifiable {
    var medication: MedicationSnapshot
    var scheduledAt: Date
    var logs: [DoseLogSnapshot]

    var id: String { "\(medication.id.uuidString)@\(scheduledAt.timeIntervalSinceReferenceDate)" }

    var givenLogs: [DoseLogSnapshot] { logs.filter { $0.status == .given } }

    var isDone: Bool { !logs.isEmpty }

    /// The whole point of the app: two people giving the same dose, each
    /// unaware of the other. Surfaced loudly instead of being merged away.
    var isDuplicate: Bool { givenLogs.count > 1 }

    /// The log that decides how the row renders. A `.given` entry always wins
    /// over a skip or refusal recorded for the same slot.
    var resolvedLog: DoseLogSnapshot? {
        givenLogs.min { ($0.takenAt ?? .distantFuture) < ($1.takenAt ?? .distantFuture) }
            ?? logs.first
    }

    var status: DoseStatus? { resolvedLog?.status }

    func isOverdue(now: Date, grace: TimeInterval = 30 * 60) -> Bool {
        !isDone && now.timeIntervalSince(scheduledAt) > grace
    }
}

/// A dose that was logged without matching any planned slot of that day.
struct ExtraDose: Identifiable {
    var medication: MedicationSnapshot
    var log: DoseLogSnapshot
    var id: UUID { log.id }
}

struct DayPlan {
    var slots: [DaySlot]
    var extras: [ExtraDose]

    static let empty = DayPlan(slots: [], extras: [])

    var openCount: Int { slots.filter { !$0.isDone }.count }
    var duplicateCount: Int { slots.filter(\.isDuplicate).count }

    /// The children appearing in this plan, in the order their first dose is
    /// due. Used to decide whether a row needs to name its child at all: with a
    /// single child the name is noise, with several it is the whole point.
    var patients: [(id: UUID, name: String)] {
        var seen = Set<UUID>()
        var result: [(id: UUID, name: String)] = []
        for slot in slots where seen.insert(slot.medication.patientID).inserted {
            result.append((slot.medication.patientID, slot.medication.patientName))
        }
        for extra in extras where seen.insert(extra.medication.patientID).inserted {
            result.append((extra.medication.patientID, extra.medication.patientName))
        }
        return result
    }
}

// MARK: - Engine

enum ScheduleEngine {

    /// Bit *n* stands for `Calendar` weekday `n + 1`, i.e. bit 0 is Sunday in a
    /// Gregorian calendar. Storing the raw weekday keeps the mask independent of
    /// the user's first-day-of-week setting.
    static let allWeekdaysMask = 0b1111111

    /// Two dates are the same slot if they land within this tolerance. Core Data
    /// and CloudKit both round `Date` on the way through, so exact equality is
    /// not reliable across devices.
    static let slotMatchTolerance: TimeInterval = 1.0

    // MARK: Minutes helpers

    static func normalizedMinutes(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.map { min(max($0, 0), 24 * 60 - 1) })).sorted()
    }

    /// Parses the comma separated storage format (`"480,1200"`). Unparseable
    /// pieces are dropped rather than defaulting to midnight, which would
    /// silently invent a dose at 00:00.
    static func parseMinutes(_ raw: String?) -> [Int] {
        guard let raw, !raw.isEmpty else { return [] }
        return normalizedMinutes(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func encodeMinutes(_ minutes: [Int]) -> String {
        normalizedMinutes(minutes).map(String.init).joined(separator: ",")
    }

    static func weekdayMask(for weekdays: Set<Int>) -> Int {
        weekdays.reduce(0) { $0 | (1 << (($1 - 1) % 7)) }
    }

    static func weekdays(in mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    // MARK: Occurrence

    /// Whether `rule` produces doses on `day`, ignoring the time of day.
    static func rule(_ rule: ScheduleRuleSnapshot, occursOn day: Date, calendar: Calendar) -> Bool {
        guard !rule.minutesOfDay.isEmpty else { return false }
        let target = calendar.startOfDay(for: day)

        if let start = rule.startDate, target < calendar.startOfDay(for: start) { return false }
        if let end = rule.endDate, target > calendar.startOfDay(for: end) { return false }

        switch rule.recurrence {
        case .daily:
            return true

        case .everyNDays:
            let interval = max(1, rule.intervalDays)
            guard interval > 1 else { return true }
            // Without an anchor "every N days" has no meaning; fall back to daily
            // rather than dropping the medication off the plan entirely.
            guard let anchor = rule.startDate else { return true }
            let from = calendar.startOfDay(for: anchor)
            guard let days = calendar.dateComponents([.day], from: from, to: target).day else { return false }
            return days >= 0 && days % interval == 0

        case .weekdays:
            let weekday = calendar.component(.weekday, from: target)
            return rule.weekdayMask & (1 << (weekday - 1)) != 0
        }
    }

    /// The concrete times `rule` fires on `day`.
    static func slotTimes(for rule: ScheduleRuleSnapshot, on day: Date, calendar: Calendar) -> [Date] {
        guard self.rule(rule, occursOn: day, calendar: calendar) else { return [] }
        let start = calendar.startOfDay(for: day)
        return rule.minutesOfDay.compactMap { minute in
            // `bySettingHour` skips forward over a DST gap instead of returning
            // a time that does not exist on that day.
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)
        }
    }

    /// All planned times for one medication on `day`, de-duplicated across
    /// overlapping rules and sorted.
    static func slotTimes(for medication: MedicationSnapshot, on day: Date, calendar: Calendar) -> [Date] {
        guard !medication.isArchived else { return [] }
        let target = calendar.startOfDay(for: day)
        if let start = medication.startDate, target < calendar.startOfDay(for: start) { return [] }
        if let end = medication.endDate, target > calendar.startOfDay(for: end) { return [] }

        var seen = Set<Date>()
        var result: [Date] = []
        for rule in medication.rules {
            for date in slotTimes(for: rule, on: day, calendar: calendar) where seen.insert(date).inserted {
                result.append(date)
            }
        }
        return result.sorted()
    }

    // MARK: Day plan

    /// Combines the planned slots of `day` with the doses actually logged, so
    /// the UI can render one row per slot and flag duplicates and extras.
    static func dayPlan(
        medications: [MedicationSnapshot],
        logs: [DoseLogSnapshot],
        on day: Date,
        calendar: Calendar = .current
    ) -> DayPlan {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return .empty }

        let logsByMedication = Dictionary(grouping: logs, by: \.medicationID)
        var slots: [DaySlot] = []
        var consumed = Set<UUID>()

        for medication in medications {
            let candidates = logsByMedication[medication.id] ?? []
            for time in slotTimes(for: medication, on: day, calendar: calendar) {
                let matching = candidates.filter { log in
                    guard let scheduled = log.scheduledAt else { return false }
                    return abs(scheduled.timeIntervalSince(time)) <= slotMatchTolerance
                }
                consumed.formUnion(matching.map(\.id))
                slots.append(
                    DaySlot(
                        medication: medication,
                        scheduledAt: time,
                        logs: matching.sorted { ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast) }
                    )
                )
            }
        }

        // Anything logged on this day that no slot claimed: an unscheduled extra
        // dose, or a dose whose schedule was edited after the fact.
        let medicationsByID = Dictionary(medications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let extras: [ExtraDose] = logs
            .filter { !consumed.contains($0.id) }
            .filter { log in
                if let scheduled = log.scheduledAt {
                    // Belongs to another day's plan and is already shown there;
                    // listing it again here would double-count the dose.
                    return scheduled >= dayStart && scheduled < dayEnd
                }
                guard let taken = log.takenAt else { return false }
                return taken >= dayStart && taken < dayEnd
            }
            .compactMap { log in
                guard let medication = medicationsByID[log.medicationID] else { return nil }
                return ExtraDose(medication: medication, log: log)
            }
            .sorted { ($0.log.takenAt ?? .distantPast) < ($1.log.takenAt ?? .distantPast) }

        return DayPlan(slots: slots.sorted(by: slotOrder), extras: extras)
    }

    private static func slotOrder(_ lhs: DaySlot, _ rhs: DaySlot) -> Bool {
        if lhs.scheduledAt != rhs.scheduledAt { return lhs.scheduledAt < rhs.scheduledAt }
        return lhs.medication.name.localizedStandardCompare(rhs.medication.name) == .orderedAscending
    }

    // MARK: Upcoming slots (used for reminders)

    /// Planned slots strictly after `date`, walking forward day by day. `limit`
    /// keeps the caller inside the 64 pending-notification budget iOS grants.
    static func upcomingSlots(
        medications: [MedicationSnapshot],
        after date: Date,
        withinDays days: Int = 2,
        limit: Int = 32,
        calendar: Calendar = .current
    ) -> [PlannedSlot] {
        guard limit > 0, days > 0 else { return [] }
        var result: [PlannedSlot] = []
        let firstDay = calendar.startOfDay(for: date)

        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { break }
            var ofDay: [PlannedSlot] = []
            for medication in medications {
                for time in slotTimes(for: medication, on: day, calendar: calendar) where time > date {
                    ofDay.append(PlannedSlot(medicationID: medication.id, scheduledAt: time))
                }
            }
            result.append(contentsOf: ofDay.sorted { $0.scheduledAt < $1.scheduledAt })
            if result.count >= limit { break }
        }
        return Array(result.prefix(limit))
    }
}
