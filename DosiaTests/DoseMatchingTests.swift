import XCTest
@testable import Dosia

/// Matching logged doses back onto planned slots. This is where a double dose
/// either gets caught or slips through, so it gets its own suite.
final class DoseMatchingTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private let medicationID = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var medication: MedicationSnapshot {
        MedicationSnapshot(
            id: medicationID,
            name: "Amoxicillin",
            doseAmount: 5,
            doseUnit: "ml",
            rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 20 * 60])]
        )
    }

    private func plan(_ logs: [DoseLogSnapshot], on day: Date? = nil) -> DayPlan {
        ScheduleEngine.dayPlan(
            medications: [medication],
            logs: logs,
            on: day ?? date(2026, 3, 10),
            calendar: calendar
        )
    }

    // MARK: - Basic matching

    func testEmptyDayHasOneOpenSlotPerPlannedTime() {
        let result = plan([])
        XCTAssertEqual(result.slots.count, 2)
        XCTAssertEqual(result.openCount, 2)
        XCTAssertTrue(result.extras.isEmpty)
        XCTAssertFalse(result.slots[0].isDone)
    }

    func testLogMatchesItsSlotAndCarriesThePersonThrough() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 10, 8),
            takenAt: date(2026, 3, 10, 8, 12),
            status: .given,
            personName: "Papa"
        )
        let result = plan([log])
        XCTAssertTrue(result.slots[0].isDone)
        XCTAssertEqual(result.slots[0].resolvedLog?.personName, "Papa")
        XCTAssertFalse(result.slots[1].isDone)
        XCTAssertEqual(result.openCount, 1)
        XCTAssertTrue(result.extras.isEmpty)
    }

    func testSubSecondDriftStillMatchesTheSameSlot() {
        // CloudKit and Core Data both round dates in transit; exact equality is
        // not something the matcher may rely on.
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 10, 8).addingTimeInterval(0.4),
            takenAt: date(2026, 3, 10, 8),
            status: .given
        )
        XCTAssertTrue(plan([log]).slots[0].isDone)
    }

    func testDriftBeyondToleranceDoesNotMatch() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 10, 8).addingTimeInterval(120),
            takenAt: date(2026, 3, 10, 8),
            status: .given
        )
        let result = plan([log])
        XCTAssertFalse(result.slots[0].isDone)
        XCTAssertEqual(result.extras.count, 1)
    }

    // MARK: - The double dose

    func testTwoPeopleTickingTheSameSlotIsFlaggedNotMerged() {
        let slot = date(2026, 3, 10, 8)
        let mama = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: slot,
            takenAt: date(2026, 3, 10, 8, 2),
            status: .given,
            personName: "Mama"
        )
        let papa = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: slot,
            takenAt: date(2026, 3, 10, 8, 9),
            status: .given,
            personName: "Papa"
        )
        let result = plan([papa, mama])

        XCTAssertEqual(result.slots.count, 2, "A duplicate must not create an extra row")
        XCTAssertTrue(result.slots[0].isDuplicate)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.slots[0].logs.count, 2)
        XCTAssertEqual(result.slots[0].logs.map(\.personName), ["Mama", "Papa"], "Logs are ordered by time given")
        XCTAssertTrue(result.extras.isEmpty)
    }

    func testASingleGivenLogIsNotADuplicate() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 10, 8),
            takenAt: date(2026, 3, 10, 8),
            status: .given
        )
        XCTAssertFalse(plan([log]).slots[0].isDuplicate)
    }

    func testSkipFollowedByAGivenIsNotADuplicateButCountsAsGiven() {
        let slot = date(2026, 3, 10, 8)
        let skipped = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: slot,
            takenAt: date(2026, 3, 10, 8, 1),
            status: .skipped,
            personName: "Mama"
        )
        let given = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: slot,
            takenAt: date(2026, 3, 10, 8, 30),
            status: .given,
            personName: "Papa"
        )
        let slotResult = plan([skipped, given]).slots[0]
        XCTAssertFalse(slotResult.isDuplicate)
        XCTAssertEqual(slotResult.status, .given)
        XCTAssertEqual(slotResult.resolvedLog?.personName, "Papa")
    }

    func testEarliestGivenLogWins() {
        let slot = date(2026, 3, 10, 8)
        let late = DoseLogSnapshot(medicationID: medicationID, scheduledAt: slot, takenAt: date(2026, 3, 10, 9), status: .given, personName: "Late")
        let early = DoseLogSnapshot(medicationID: medicationID, scheduledAt: slot, takenAt: date(2026, 3, 10, 8), status: .given, personName: "Early")
        XCTAssertEqual(plan([late, early]).slots[0].resolvedLog?.personName, "Early")
    }

    // MARK: - Extra doses

    func testUnscheduledDoseAppearsAsAnExtraOnTheDayItWasGiven() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: nil,
            takenAt: date(2026, 3, 10, 15),
            status: .given,
            personName: "Oma"
        )
        let result = plan([log])
        XCTAssertEqual(result.extras.count, 1)
        XCTAssertEqual(result.extras[0].log.personName, "Oma")
        XCTAssertEqual(result.openCount, 2, "An extra dose does not close a planned slot")
    }

    func testExtraDoseFromAnotherDayIsNotListed() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: nil,
            takenAt: date(2026, 3, 9, 15),
            status: .given
        )
        XCTAssertTrue(plan([log]).extras.isEmpty)
    }

    func testLogBelongingToAnotherDaysSlotIsNotCountedTwice() {
        // Yesterday's 20:00 dose, ticked off shortly after midnight. It belongs
        // to yesterday's plan and must not also surface as an extra today.
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 9, 20),
            takenAt: date(2026, 3, 10, 0, 20),
            status: .given
        )
        let today = plan([log])
        XCTAssertTrue(today.extras.isEmpty)
        XCTAssertEqual(today.openCount, 2)

        let yesterday = plan([log], on: date(2026, 3, 9))
        XCTAssertTrue(yesterday.slots.last?.isDone == true)
    }

    func testLogOfAnUnknownMedicationIsIgnoredRatherThanCrashing() {
        let log = DoseLogSnapshot(
            medicationID: UUID(),
            scheduledAt: nil,
            takenAt: date(2026, 3, 10, 15),
            status: .given
        )
        XCTAssertTrue(plan([log]).extras.isEmpty)
    }

    // MARK: - Overdue

    func testSlotBecomesOverdueOnlyAfterTheGracePeriod() {
        let slot = plan([]).slots[0]
        XCTAssertFalse(slot.isOverdue(now: date(2026, 3, 10, 8, 20)))
        XCTAssertTrue(slot.isOverdue(now: date(2026, 3, 10, 9)))
    }

    func testCompletedSlotIsNeverOverdue() {
        let log = DoseLogSnapshot(
            medicationID: medicationID,
            scheduledAt: date(2026, 3, 10, 8),
            takenAt: date(2026, 3, 10, 8),
            status: .given
        )
        XCTAssertFalse(plan([log]).slots[0].isOverdue(now: date(2026, 3, 10, 23)))
    }

    // MARK: - Ordering

    func testSlotsOfSeveralMedicationsAreOrderedByTimeThenName() {
        let vitamin = MedicationSnapshot(
            id: UUID(),
            name: "Vitamin D",
            rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60])]
        )
        let result = ScheduleEngine.dayPlan(
            medications: [vitamin, medication],
            logs: [],
            on: date(2026, 3, 10),
            calendar: calendar
        )
        XCTAssertEqual(result.slots.map(\.medication.name), ["Amoxicillin", "Vitamin D", "Amoxicillin"])
        XCTAssertEqual(result.slots.map(\.scheduledAt), [date(2026, 3, 10, 8), date(2026, 3, 10, 8), date(2026, 3, 10, 20)])
    }

    func testSlotIdentifiersAreStableAndDistinct() {
        let result = plan([])
        XCTAssertNotEqual(result.slots[0].id, result.slots[1].id)
        XCTAssertEqual(result.slots[0].id, plan([]).slots[0].id)
    }
}
