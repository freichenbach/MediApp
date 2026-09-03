import XCTest
@testable import DosiCrew

/// The scheduling rules are the part of the app that must not be wrong, and the
/// part that needs neither iCloud nor a device to verify.
final class ScheduleEngineTests: XCTestCase {

    /// Fixed calendar so results do not depend on where the test runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Minute encoding

    func testMinutesRoundTripSortedAndDeduplicated() {
        let encoded = ScheduleEngine.encodeMinutes([1200, 480, 480])
        XCTAssertEqual(encoded, "480,1200")
        XCTAssertEqual(ScheduleEngine.parseMinutes(encoded), [480, 1200])
    }

    func testMinuteParsingIgnoresGarbageInsteadOfInventingMidnight() {
        XCTAssertEqual(ScheduleEngine.parseMinutes("480,oops,1200"), [480, 1200])
        XCTAssertEqual(ScheduleEngine.parseMinutes(""), [])
        XCTAssertEqual(ScheduleEngine.parseMinutes(nil), [])
    }

    func testMinutesAreClampedToADay() {
        XCTAssertEqual(ScheduleEngine.normalizedMinutes([-30, 5000]), [0, 1439])
    }

    // MARK: - Daily

    func testDailyRuleFiresAtEveryConfiguredTime() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 20 * 60])])
        let times = ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar)
        XCTAssertEqual(times, [date(2026, 3, 10, 8), date(2026, 3, 10, 20)])
    }

    func testRuleWithoutTimesProducesNoSlots() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [])])
        XCTAssertTrue(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar).isEmpty)
    }

    // MARK: - Windows

    func testMedicationWindowExcludesDaysBeforeStartAndAfterEnd() {
        let medication = makeMedication(
            startDate: date(2026, 3, 10),
            endDate: date(2026, 3, 12),
            rules: [ScheduleRuleSnapshot(minutesOfDay: [9 * 60])]
        )
        XCTAssertTrue(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 9), calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar).count, 1)
        XCTAssertEqual(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 12), calendar: calendar).count, 1)
        XCTAssertTrue(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 13), calendar: calendar).isEmpty)
    }

    func testStartAndEndDatesAreInclusiveRegardlessOfTimeOfDay() {
        let medication = makeMedication(
            startDate: date(2026, 3, 10, 23, 45),
            endDate: date(2026, 3, 10, 0, 5),
            rules: [ScheduleRuleSnapshot(minutesOfDay: [9 * 60])]
        )
        XCTAssertEqual(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar).count, 1)
    }

    func testArchivedMedicationNeverProducesSlots() {
        let medication = makeMedication(isArchived: true, rules: [ScheduleRuleSnapshot(minutesOfDay: [9 * 60])])
        XCTAssertTrue(ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar).isEmpty)
    }

    // MARK: - Every N days

    func testEveryThreeDaysFiresOnlyOnMultiplesOfTheAnchor() {
        let rule = ScheduleRuleSnapshot(
            minutesOfDay: [9 * 60],
            recurrence: .everyNDays,
            intervalDays: 3,
            startDate: date(2026, 3, 10)
        )
        let medication = makeMedication(rules: [rule])
        let firing = (10...16).filter {
            !ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, $0), calendar: calendar).isEmpty
        }
        XCTAssertEqual(firing, [10, 13, 16])
    }

    func testEveryNDaysDoesNotFireBeforeItsAnchor() {
        let rule = ScheduleRuleSnapshot(
            minutesOfDay: [9 * 60],
            recurrence: .everyNDays,
            intervalDays: 2,
            startDate: date(2026, 3, 10)
        )
        XCTAssertFalse(ScheduleEngine.rule(rule, occursOn: date(2026, 3, 8), calendar: calendar))
    }

    func testEveryNDaysWithoutAnchorFallsBackToDailyRatherThanDisappearing() {
        let rule = ScheduleRuleSnapshot(minutesOfDay: [9 * 60], recurrence: .everyNDays, intervalDays: 3)
        XCTAssertTrue(ScheduleEngine.rule(rule, occursOn: date(2026, 3, 11), calendar: calendar))
    }

    // MARK: - Weekdays

    func testWeekdayMaskRoundTrip() {
        let weekdays: Set<Int> = [2, 4, 6] // Monday, Wednesday, Friday
        let mask = ScheduleEngine.weekdayMask(for: weekdays)
        XCTAssertEqual(ScheduleEngine.weekdays(in: mask), weekdays)
    }

    func testWeekdayRuleFiresOnlyOnSelectedDays() {
        // 2026-03-09 is a Monday.
        let rule = ScheduleRuleSnapshot(
            minutesOfDay: [9 * 60],
            recurrence: .weekdays,
            weekdayMask: ScheduleEngine.weekdayMask(for: [2, 5]) // Monday + Thursday
        )
        let medication = makeMedication(rules: [rule])
        let firing = (9...15).filter {
            !ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, $0), calendar: calendar).isEmpty
        }
        XCTAssertEqual(firing, [9, 12])
    }

    // MARK: - Multiple rules

    func testOverlappingRulesDoNotProduceDuplicateSlots() {
        let medication = makeMedication(rules: [
            ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 20 * 60]),
            ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 12 * 60])
        ])
        let times = ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 10), calendar: calendar)
        XCTAssertEqual(times, [date(2026, 3, 10, 8), date(2026, 3, 10, 12), date(2026, 3, 10, 20)])
    }

    // MARK: - Daylight saving

    func testSlotSurvivesTheSpringForwardGap() {
        // Europe/Berlin skips 02:00–03:00 on 2026-03-29. A 02:30 dose must still
        // yield exactly one slot on that day rather than vanishing.
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [2 * 60 + 30])])
        let times = ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 29), calendar: calendar)
        XCTAssertEqual(times.count, 1)
        let components = calendar.dateComponents([.year, .month, .day], from: times[0])
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.month, 3)
    }

    func testEveningSlotIsUnaffectedByTheDaylightSavingChange() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [20 * 60])])
        let times = ScheduleEngine.slotTimes(for: medication, on: date(2026, 3, 29), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.hour], from: times[0]).hour, 20)
    }

    // MARK: - Upcoming slots

    func testUpcomingSlotsAreOrderedAndStartAfterTheGivenMoment() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 20 * 60])])
        let slots = ScheduleEngine.upcomingSlots(
            medications: [medication],
            after: date(2026, 3, 10, 9),
            withinDays: 2,
            limit: 10,
            calendar: calendar
        )
        XCTAssertEqual(
            slots.map(\.scheduledAt),
            [
                date(2026, 3, 10, 20),
                date(2026, 3, 11, 8), date(2026, 3, 11, 20),
                date(2026, 3, 12, 8), date(2026, 3, 12, 20)
            ]
        )
    }

    func testUpcomingSlotsRespectTheLimit() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [6 * 60, 12 * 60, 18 * 60])])
        let slots = ScheduleEngine.upcomingSlots(
            medications: [medication],
            after: date(2026, 3, 10),
            withinDays: 5,
            limit: 4,
            calendar: calendar
        )
        XCTAssertEqual(slots.count, 4)
    }

    func testUpcomingSlotsExcludeTheExactCurrentMoment() {
        let medication = makeMedication(rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60])])
        let slots = ScheduleEngine.upcomingSlots(
            medications: [medication],
            after: date(2026, 3, 10, 8),
            withinDays: 0,
            limit: 10,
            calendar: calendar
        )
        XCTAssertTrue(slots.isEmpty)
    }

    // MARK: - Helpers

    private func makeMedication(
        id: UUID = UUID(),
        name: String = "Test",
        startDate: Date? = nil,
        endDate: Date? = nil,
        isArchived: Bool = false,
        rules: [ScheduleRuleSnapshot]
    ) -> MedicationSnapshot {
        MedicationSnapshot(
            id: id,
            name: name,
            startDate: startDate,
            endDate: endDate,
            isArchived: isArchived,
            rules: rules
        )
    }
}

/// The child's colour has to be the same on every device and every launch —
/// otherwise the one visual cue that separates two children stops being a cue.
final class ChildColorTests: XCTestCase {

    func testSiblingsNeverShareAColour() {
        var taken: [String?] = []
        for _ in 0..<ChildColor.allCases.count {
            taken.append(ChildColor.unused(among: taken).rawValue)
        }
        XCTAssertEqual(Set(taken.compactMap { $0 }).count, ChildColor.allCases.count,
                       "Two children were given the same colour")
    }

    func testAColourAlreadyTakenIsSkippedRegardlessOfCase() {
        let first = ChildColor.allCases[0]
        let picked = ChildColor.unused(among: [first.rawValue.lowercased()])
        XCTAssertNotEqual(picked, first, "A lowercase hex must still count as taken")
    }

    func testAChildWithNoColourYetIsToleratedAndStillSkipped() {
        let first = ChildColor.allCases[0]
        let picked = ChildColor.unused(among: [nil, first.rawValue, nil])
        XCTAssertNotEqual(picked, first)
    }

    /// Beyond the palette the colours repeat rather than the call failing —
    /// by then the names are doing the work anyway.
    func testMoreChildrenThanColoursStillGetOne() {
        let taken = ChildColor.allCases.map { Optional($0.rawValue) }
        XCTAssertTrue(ChildColor.allCases.contains(ChildColor.unused(among: taken)))
    }

    /// The fallback for records saved before colours were assigned.
    func testDerivedColourIsStableAcrossCalls() {
        let id = UUID(uuidString: "6E9F1B2A-0C4D-4E5F-8A9B-0C1D2E3F4A5B")!
        let first = ChildColor.index(derivedFrom: id)
        for _ in 0..<100 {
            XCTAssertEqual(ChildColor.index(derivedFrom: id), first, "The colour must not vary between calls")
        }
        XCTAssertTrue((0..<ChildColor.allCases.count).contains(first))
    }

    /// The whole point of the palette: none of the three status colours, so a
    /// child's name can never be mistaken for a warning.
    func testPaletteAvoidsTheStatusColours() {
        let statusColours = Set([MedColor.green, MedColor.orange, MedColor.red].map(\.rawValue))
        for option in ChildColor.allCases {
            XCTAssertFalse(statusColours.contains(option.rawValue), "\(option) collides with a dose status colour")
        }
    }
}
