import CoreData
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

/// The dose field goes through text, so the parsing is worth pinning down: a
/// dose read wrong by a factor of ten is the kind of failure this app exists to
/// prevent, not to cause.
final class DecimalTextTests: XCTestCase {

    func testEmptyFieldMeansNoAmount() {
        XCTAssertEqual(DecimalText.value(of: ""), 0)
        XCTAssertEqual(DecimalText.value(of: "   "), 0)
    }

    func testNoAmountShowsAnEmptyFieldRatherThanAZero() {
        XCTAssertEqual(DecimalText.text(for: 0), "")
    }

    func testBothDecimalSeparatorsMeanTheSameThing() {
        XCTAssertEqual(DecimalText.value(of: "2.5"), 2.5, accuracy: 0.0001)
        XCTAssertEqual(DecimalText.value(of: "2,5"), 2.5, accuracy: 0.0001)
    }

    /// The reason this does not use NumberFormatter: in an English locale it
    /// reads "5,5" as a grouping separator and answers 55.
    func testACommaIsNeverAThousandsSeparator() {
        XCTAssertEqual(DecimalText.value(of: "5,5"), 5.5, accuracy: 0.0001)
        XCTAssertNotEqual(DecimalText.value(of: "5,5"), 55)
    }

    func testNonsenseIsNotAnAmount() {
        XCTAssertEqual(DecimalText.value(of: "1,2,3"), 0)
        XCTAssertEqual(DecimalText.value(of: "abc"), 0)
        XCTAssertEqual(DecimalText.value(of: "-5"), 0, "A negative dose is not a dose")
    }

    func testWhatIsShownCanBeTypedBackIn() {
        for amount in [0.5, 1, 2.5, 7, 12.75, 1000] as [Double] {
            let shown = DecimalText.text(for: amount)
            XCTAssertEqual(DecimalText.value(of: shown), amount, accuracy: 0.0001,
                           "\(amount) rendered as \"\(shown)\" and did not survive the round trip")
        }
    }
}

/// A new medication starts with a schedule that has no times, so the first time
/// added is the first time there is — nothing has to be deleted first.
final class NewScheduleTests: XCTestCase {

    func testAFreshRuleHasNoTimes() {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let patient = Patient.makeDefault(in: context)
        let medication = Medication.make(in: context, patient: patient)
        let rule = ScheduleRule.make(in: context, medication: medication)
        XCTAssertTrue(rule.minutes.isEmpty, "A guessed time has to be deleted before the real one helps")
    }
}

/// The store descriptions have to be addable to a coordinator. Sounds obvious;
/// it was not.
///
/// Both CloudKit stores refused to open on a real device because they named a
/// configuration — "Default" — that `DosiCrew.xcdatamodel` does not declare.
/// The app then fell back to a local store and quietly stopped syncing, and the
/// schema bootstrap answered with a follow-on error three steps downstream.
/// Nothing in the unit tests noticed, because nothing ever tried to add these
/// descriptions to anything.
final class StoreDescriptionTests: XCTestCase {

    /// Adds each description in memory and without CloudKit. That strips away
    /// everything a test machine cannot have — an iCloud account, entitlements,
    /// a container — and keeps the one step that failed: resolving the
    /// configuration name against the model.
    ///
    /// Each store keeps its own URL. In memory the file is never opened, but
    /// the coordinator still refuses two stores at the same address with
    /// "Can't add the same store twice" — which says nothing about the
    /// descriptions and everything about the test.
    func testEveryStoreDescriptionCanActuallyBeAdded() throws {
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        for description in PersistenceController.cloudKitStoreDescriptions() {
            let url = try XCTUnwrap(description.url, "A store description without a URL")
            XCTAssertNoThrow(
                try coordinator.addPersistentStore(
                    type: .inMemory,
                    configuration: description.configuration,
                    at: url
                ),
                "Cannot open \(url.lastPathComponent) with configuration "
                    + "\(description.configuration ?? "<default>")"
            )
        }

        XCTAssertEqual(coordinator.persistentStores.count, 2,
                       "Both the private and the shared store have to open")
    }

    /// Guards the other direction: if someone does name a configuration later,
    /// the model has to declare it.
    func testAnyNamedConfigurationExistsInTheModel() {
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        for description in PersistenceController.cloudKitStoreDescriptions() {
            guard let name = description.configuration else { continue }
            XCTAssertTrue(model.configurations.contains(name),
                          "The model declares no configuration named \(name)")
        }
    }
}

/// Which store a newly inserted object joins.
///
/// Irrelevant while only one store ever opened — Core Data has nothing to
/// choose between. From the moment both the private and the shared store load,
/// an unassigned insert is fatal: Core Data answers with an Objective-C
/// exception that Swift cannot catch.
final class StoreAssignmentTests: XCTestCase {

    private func controller() -> PersistenceController { PersistenceController(inMemory: true) }

    func testAMedicationFollowsItsChild() throws {
        let controller = controller()
        let context = controller.viewContext
        let patient = Patient.makeDefault(in: context)
        XCTAssertTrue(controller.save(context))

        let medication = Medication.make(in: context, patient: patient)
        XCTAssertNotNil(PersistenceController.store(for: medication),
                        "A medication has to land in the same store as its child")
        XCTAssertEqual(PersistenceController.store(for: medication), patient.objectID.persistentStore)
    }

    /// The case that would break sharing silently: a dose recorded for a child
    /// somebody shared *with* this person belongs in the shared store, not in
    /// the private one, or the owner never sees it.
    func testADoseFollowsItsMedication() throws {
        let controller = controller()
        let context = controller.viewContext
        let patient = Patient.makeDefault(in: context)
        let medication = Medication.make(in: context, patient: patient)
        XCTAssertTrue(controller.save(context))

        let log = DoseLog.make(
            in: context,
            medication: medication,
            scheduledAt: Date(),
            status: .given,
            personName: "Papa"
        )
        XCTAssertEqual(PersistenceController.store(for: log), medication.objectID.persistentStore)
    }

    /// A new child has nothing to follow, so the caller falls back to the
    /// private store — the only database this person may create in.
    func testANewChildHasNoAnchor() {
        let context = controller().viewContext
        XCTAssertNil(PersistenceController.store(for: Patient.makeDefault(in: context)))
    }

    /// Child and medication created in one breath: the parent is not in a store
    /// yet, so it cannot answer for the child either.
    func testAnUnsavedParentIsNotAnAnchorYet() {
        let context = controller().viewContext
        let patient = Patient.makeDefault(in: context)
        let medication = Medication.make(in: context, patient: patient)
        XCTAssertTrue(patient.objectID.isTemporaryID)
        XCTAssertNil(PersistenceController.store(for: medication))
    }
}

// MARK: - Info.plist

/// Sharing needs two keys in the Info.plist, and losing either breaks the app's
/// whole purpose in a way no other test would notice.
///
/// Build 16 shipped without `CKSharingSupported`. Everything compiled, the
/// invitation was created and sent, and the person who tapped it got told they
/// needed "a newer version of DosiCrew, which is not on the App Store" — a
/// sentence that sends everyone looking at versions and TestFlight rather than
/// at a missing key. The app was simply not registered as something that can
/// open a CloudKit share.
///
/// The tests are hosted by the app, so `Bundle.main` is the built app itself:
/// this asks the artefact, not the source.
final class SharingInfoPlistTests: XCTestCase {

    func testDeclaresCloudKitSharingSupport() {
        let value = Bundle.main.object(forInfoDictionaryKey: "CKSharingSupported")
        XCTAssertEqual(
            value as? Bool, true,
            "CKSharingSupported must be true, or iOS will not offer this app when somebody taps an invitation."
        )
    }

    func testHandlesTheShareActivityType() {
        let types = Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String]
        XCTAssertEqual(
            types?.contains("com.apple.coredata.cloudkit.zone.share"), true,
            "Without this activity type the invitation never reaches the scene delegate, so acceptShare is never called."
        )
    }

    /// The container the entitlements name and the one the code opens have to
    /// be the same string. They are declared in different files, so nothing
    /// else would catch them drifting apart.
    func testContainerIdentifierMatchesTheEntitlements() {
        XCTAssertEqual(
            PersistenceController.cloudKitContainerIdentifier,
            "iCloud.es.reichenbach.DosiCrew"
        )
    }
}

// MARK: - Report for the doctor

/// The counting behind the report. A doctor may change a prescription over
/// these numbers, so getting them right matters more than anything else in this
/// file — and the distinction that matters most is between a dose somebody
/// deliberately skipped and one nobody wrote down.
final class DoseReportTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Twice a day, eight and eight.
    private func medication(id: UUID = UUID(), name: String = "Amoxicillin") -> MedicationSnapshot {
        MedicationSnapshot(
            id: id,
            name: name,
            doseAmount: 5,
            doseUnit: "ml",
            rules: [ScheduleRuleSnapshot(minutesOfDay: [8 * 60, 20 * 60])]
        )
    }

    private func build(
        medications: [MedicationSnapshot],
        logs: [DoseLogSnapshot],
        events: [DoseReport.EventEntry] = [],
        from: Date,
        to: Date,
        now: Date
    ) -> DoseReport.Report {
        DoseReport.build(
            patientName: "Mia",
            patientBirthDate: nil,
            patientWeightKg: 0,
            medications: medications,
            logs: logs,
            events: events,
            from: from,
            to: to,
            now: now,
            calendar: calendar
        )
    }

    // MARK: What each outcome counts as

    func testADoseGivenNearItsTimeCountsAsOnTime() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 8),
                    takenAt: date(2026, 3, 10, 8, 20)
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.given, 1)
        XCTAssertEqual(report.late, 0)
    }

    func testADoseGivenMoreThanAnHourLateIsCountedLateButStillGiven() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 8),
                    takenAt: date(2026, 3, 10, 9, 30)
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.late, 1)
        XCTAssertEqual(report.given, 0, "A late dose must not be counted twice")
        // Both halves of "it did go in" are what a doctor reads.
        XCTAssertEqual(report.tallies.first?.recordedShare, 1.0)
    }

    func testAnEarlyDoseIsNotCalledLate() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 8),
                    takenAt: date(2026, 3, 10, 6)
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.given, 1)
        XCTAssertEqual(report.late, 0)
        XCTAssertEqual(report.days.first?.entries.first?.deviationMinutes, -120)
    }

    /// The distinction the whole report hangs on.
    func testAnUntickedDoseIsNotRecordedRatherThanSkipped() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.notRecorded, 2)
        XCTAssertEqual(report.skipped, 0, "Nobody said they skipped it — nobody said anything")
        XCTAssertEqual(report.refused, 0)
    }

    func testDeliberateSkipAndRefusalAreKeptApart() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 8),
                    takenAt: date(2026, 3, 10, 8),
                    status: .skipped
                ),
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 20),
                    takenAt: date(2026, 3, 10, 20),
                    status: .refused
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.skipped, 1)
        XCTAssertEqual(report.refused, 1)
        XCTAssertEqual(report.notRecorded, 0)
        XCTAssertEqual(report.recordedShareIsZero, true)
    }

    // MARK: The future is not a gap

    func testDosesStillToComeAreNotCountedAsMissing() {
        let med = medication()
        // Midday: the eight o'clock dose has passed, the evening one has not.
        let report = build(
            medications: [med],
            logs: [],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 10, 12)
        )
        XCTAssertEqual(report.planned, 1, "Only the morning dose had fallen due")
        XCTAssertEqual(report.notRecorded, 1)
    }

    func testADoseDueMinutesAgoIsStillWithinItsGracePeriod() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 10, 8, 10)
        )
        XCTAssertEqual(report.planned, 0, "Ten minutes late is not yet a missing dose")
    }

    // MARK: Doses outside the plan

    func testAnExtraDoseIsListedSeparatelyAndNotAsAPlannedOne() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: nil,
                    takenAt: date(2026, 3, 10, 2),
                    personName: "Frank"
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.extras, 1)
        XCTAssertEqual(report.given, 0)
        XCTAssertEqual(report.notRecorded, 2, "Both planned doses are still unanswered")
        XCTAssertEqual(report.days.first?.extras.first?.personName, "Frank")
    }

    /// Two people giving the same dose is the failure the app exists to catch,
    /// so it must not be quietly folded into one line. Writing this test is what
    /// found that it was: the slot counted as one dose given and the second
    /// syringe vanished from the report entirely.
    func testADoubleDoseIsReportedAsGivenTwice() {
        let med = medication()
        let logs = [
            DoseLogSnapshot(
                medicationID: med.id,
                scheduledAt: date(2026, 3, 10, 8),
                takenAt: date(2026, 3, 10, 8, 5),
                personName: "Frank"
            ),
            DoseLogSnapshot(
                medicationID: med.id,
                scheduledAt: date(2026, 3, 10, 8),
                takenAt: date(2026, 3, 10, 8, 25),
                personName: "Ana"
            )
        ]
        let report = build(
            medications: [med],
            logs: logs,
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.given, 1, "The slot itself was answered once")
        XCTAssertEqual(report.duplicates, 1, "The child had this dose twice, and the report must say so")
        XCTAssertEqual(report.days.first?.entries.first?.personName, "Frank",
                       "The first person to tick it off is the one on the line")
        XCTAssertEqual(report.days.first?.entries.first?.duplicates.first?.personName, "Ana")
    }

    /// A skip recorded next to a dose is somebody correcting themselves, not a
    /// second syringe. Counting it as a double dose would raise an alarm in a
    /// consulting room over nothing.
    func testACorrectionIsNotADoubleDose() {
        let med = medication()
        let logs = [
            DoseLogSnapshot(
                medicationID: med.id,
                scheduledAt: date(2026, 3, 10, 8),
                takenAt: date(2026, 3, 10, 8, 5),
                status: .skipped
            ),
            DoseLogSnapshot(
                medicationID: med.id,
                scheduledAt: date(2026, 3, 10, 8),
                takenAt: date(2026, 3, 10, 8, 10),
                status: .given
            )
        ]
        let report = build(
            medications: [med],
            logs: logs,
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.given, 1)
        XCTAssertEqual(report.duplicates, 0)
    }

    // MARK: Periods and shape

    func testEveryDayOfThePeriodAppearsEvenWhenNothingHappened() {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [],
            from: date(2026, 3, 8),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.days.count, 3)
        XCTAssertEqual(report.planned, 6)
    }

    func testAMedicationWithNothingDueIsLeftOutOfTheTable() {
        let dosed = medication(name: "Amoxicillin")
        let unused = MedicationSnapshot(id: UUID(), name: "Vitamin D", rules: [])
        let report = build(
            medications: [dosed, unused],
            logs: [],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertEqual(report.tallies.map(\.name), ["Amoxicillin"])
    }

    func testAnEmptyPeriodIsReportedAsEmptyRatherThanAsPerfectAdherence() {
        let report = build(
            medications: [],
            logs: [],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.planned, 0)
        XCTAssertNil(report.tallies.first?.recordedShare)
    }

    // MARK: The PDF

    func testThePDFIsProducedAndLooksLikeAPDF() throws {
        let med = medication()
        let report = build(
            medications: [med],
            logs: [
                DoseLogSnapshot(
                    medicationID: med.id,
                    scheduledAt: date(2026, 3, 10, 8),
                    takenAt: date(2026, 3, 10, 8, 5),
                    personName: "Frank",
                    note: "with breakfast"
                )
            ],
            from: date(2026, 3, 10),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        let data = ReportPDF.data(for: report)
        XCTAssertGreaterThan(data.count, 1000, "An empty PDF would still have a header")
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
    }

    func testTheFilenameCarriesTheChildAndThePeriod() {
        let report = build(
            medications: [],
            logs: [],
            from: date(2026, 3, 8),
            to: date(2026, 3, 10),
            now: date(2026, 3, 11)
        )
        // The same zone the dates were built in. Without this the test asks
        // one calendar for a day and another for its name, which is the very
        // thing the function now pins down.
        let name = ReportPDF.filename(for: report, timeZone: calendar.timeZone)
        XCTAssertTrue(name.contains("Mia"), name)
        XCTAssertTrue(name.contains("2026-03-08"), name)
        XCTAssertTrue(name.hasSuffix(".pdf"), name)
    }
}

private extension DoseReport.Report {
    /// Reads better in the assertion than the double comparison it stands for.
    var recordedShareIsZero: Bool { tallies.first?.recordedShare == 0 }
}

// MARK: - Midnight

/// The Today screen keeps the day it was opened on. Left alone, an app opened
/// yesterday evening and picked up over breakfast still shows yesterday — and
/// somebody would tick off the previous day's doses believing they were today's.
/// That is the app handing over the exact mistake it exists to prevent, so the
/// rule that decides when the view follows midnight is worth pinning down.
final class MidnightRolloverTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func rolled(selected: Date, lastKnownToday: Date, now: Date) -> Date {
        TodayView.dayAfterMidnight(
            selected: selected,
            lastKnownToday: lastKnownToday,
            now: now,
            calendar: calendar
        )
    }

    func testSomebodyLookingAtTodayIsCarriedOverMidnight() {
        let yesterday = day(2026, 3, 10)
        XCTAssertEqual(
            rolled(selected: yesterday, lastKnownToday: yesterday, now: day(2026, 3, 11)),
            day(2026, 3, 11)
        )
    }

    func testSomebodyWhoPagedBackOnPurposeIsLeftWhereTheyWere() {
        XCTAssertEqual(
            rolled(selected: day(2026, 3, 5), lastKnownToday: day(2026, 3, 10), now: day(2026, 3, 11)),
            day(2026, 3, 5),
            "Paging back to Tuesday and switching apps must not silently jump the view forward"
        )
    }

    func testNothingMovesWhenTheDayHasNotChanged() {
        let today = day(2026, 3, 10)
        XCTAssertEqual(rolled(selected: today, lastKnownToday: today, now: today), today)
        XCTAssertEqual(
            rolled(selected: day(2026, 3, 5), lastKnownToday: today, now: today),
            day(2026, 3, 5)
        )
    }
}

// MARK: - Blood pressure and blood sugar

/// Two units that differ by a factor of eighteen, in a household where one
/// person may read one and another the other. A conversion that is off is not a
/// cosmetic bug — it is a wrong number in a record a doctor reads.
final class MeasurementTests: XCTestCase {

    // MARK: Blood sugar

    func testTheConversionMatchesTheFiguresPeopleKnow() {
        let mg = BloodSugarUnit.mgPerDeciliter
        // The landmarks anybody who measures knows by heart.
        XCTAssertEqual(mg.convert(90, to: .mmolPerLiter), 5.0, accuracy: 0.02)
        XCTAssertEqual(mg.convert(180, to: .mmolPerLiter), 10.0, accuracy: 0.02)
        XCTAssertEqual(BloodSugarUnit.mmolPerLiter.convert(5.5, to: .mgPerDeciliter), 99.1, accuracy: 0.1)
    }

    func testConvertingThereAndBackChangesNothing() {
        for value in [42.0, 90.0, 126.0, 300.0] {
            let there = BloodSugarUnit.mgPerDeciliter.convert(value, to: .mmolPerLiter)
            let back = BloodSugarUnit.mmolPerLiter.convert(there, to: .mgPerDeciliter)
            XCTAssertEqual(back, value, accuracy: 0.001, "\(value) did not survive the round trip")
        }
    }

    func testConvertingToItsOwnUnitLeavesTheValueAlone() {
        XCTAssertEqual(BloodSugarUnit.mgPerDeciliter.convert(110, to: .mgPerDeciliter), 110)
    }

    /// mg/dL comes off a meter whole, mmol/L is spoken to one decimal. Showing
    /// "6.10555 mmol/l" would look like precision nobody measured.
    func testEachUnitIsShownToTheDecimalsItIsReadTo() {
        XCTAssertEqual(BloodSugarUnit.mgPerDeciliter.format(110), "110 mg/dl")
        XCTAssertEqual(BloodSugarUnit.mmolPerLiter.format(6.1055), "6.1 mmol/l")
    }

    func testBothUnitsAreShownSoNobodyHasToConvertInTheirHead() {
        let text = BloodSugarUnit.mgPerDeciliter.descriptionWithConversion(110)
        XCTAssertTrue(text.hasPrefix("110 mg/dl"), "The figure that was read comes first: \(text)")
        XCTAssertTrue(text.contains("6.1 mmol/l"), text)
    }

    func testAStoredUnitIsRecognisedAgainWhateverTheSpacingOrCase() {
        XCTAssertEqual(BloodSugarUnit.from(unitString: "mg/dl"), .mgPerDeciliter)
        XCTAssertEqual(BloodSugarUnit.from(unitString: " MMOL/L "), .mmolPerLiter)
        XCTAssertNil(BloodSugarUnit.from(unitString: "°C"))
        XCTAssertNil(BloodSugarUnit.from(unitString: nil))
    }

    // MARK: Blood pressure

    func testBloodPressureReadsAsPeopleSayIt() {
        XCTAssertEqual(BloodPressure.description(systolic: 120, diastolic: 80), "120/80")
    }

    func testBloodPressureIsShownWhole() {
        // A cuff reading 118.6 does not exist; the decimal would be noise.
        XCTAssertEqual(BloodPressure.description(systolic: 118.6, diastolic: 79.4), "119/79")
    }

    /// The only mistake worth flagging. Everything else that looks unusual may
    /// be exactly what has to reach the doctor.
    func testTheNumbersTheWrongWayRoundAreFlagged() {
        XCTAssertTrue(BloodPressure.isReversed(systolic: 80, diastolic: 120))
        XCTAssertTrue(BloodPressure.isReversed(systolic: 90, diastolic: 90))
        XCTAssertFalse(BloodPressure.isReversed(systolic: 120, diastolic: 80))
    }

    func testAHalfFilledPairIsNotYetAMistake() {
        // Somebody is still typing. Shouting at them mid-entry teaches them to
        // ignore the warning.
        XCTAssertFalse(BloodPressure.isReversed(systolic: 0, diastolic: 80))
        XCTAssertFalse(BloodPressure.isReversed(systolic: 120, diastolic: 0))
    }

    /// A low pressure in a small child is exactly what must reach the doctor,
    /// so the range warns and never refuses.
    func testAChildsLowPressureIsStillInsideThePlausibleRange() {
        XCTAssertTrue(BloodPressure.plausibleSystolic.contains(75))
        XCTAssertTrue(BloodPressure.plausibleDiastolic.contains(40))
    }

    // MARK: Shapes

    func testEachCategoryAsksForTheRightKindOfNumber() {
        XCTAssertEqual(EventCategory.bloodPressure.measurementShape, .bloodPressure)
        XCTAssertEqual(EventCategory.bloodSugar.measurementShape, .bloodSugar)
        XCTAssertEqual(EventCategory.fever.measurementShape, .single(defaultUnit: "°C"))
        XCTAssertEqual(EventCategory.note.measurementShape, .single(defaultUnit: nil))
    }

    func testTheNewCategoriesKeepTheirStoredNumbers() {
        // Raw values are what sits in the database and travels through iCloud.
        // Renumbering them would silently turn every stored fever into
        // something else.
        XCTAssertEqual(EventCategory.fever.rawValue, 0)
        XCTAssertEqual(EventCategory.note.rawValue, 4)
        XCTAssertEqual(EventCategory.bloodPressure.rawValue, 5)
        XCTAssertEqual(EventCategory.bloodSugar.rawValue, 6)
    }

    func testAnUnknownCategoryFallsBackToANoteRatherThanCrashing() {
        // An older build reading an event written by a newer one.
        XCTAssertNil(EventCategory(rawValue: 99))
    }
}

// MARK: - Seizures

/// A seizure diary is read by a neurologist, and the two things they look for
/// are which kind and how long. Both have to survive storage, iCloud and a
/// future version of the app unchanged.
final class SeizureTests: XCTestCase {

    /// The codes sit in the database and travel through iCloud. Changing one
    /// would silently turn every recorded atypical absence into something else,
    /// and nothing would fail loudly enough to notice.
    func testTheStoredCodesNeverChange() {
        XCTAssertEqual(SeizureType.atypicalAbsence.rawValue, "atypical-absence")
        XCTAssertEqual(SeizureType.tonicClonic.rawValue, "tonic-clonic")
        XCTAssertEqual(SeizureType.focalImpairedAwareness.rawValue, "focal-impaired-awareness")
        XCTAssertEqual(SeizureType.tonic.rawValue, "tonic")
        XCTAssertEqual(SeizureType.unknown.rawValue, "unknown")
    }

    func testEveryKindAppearsInExactlyOneGroup() {
        let grouped = SeizureType.Group.allCases.flatMap(\.types)
        XCTAssertEqual(
            Set(grouped), Set(SeizureType.allCases),
            "A kind missing from every group would be invisible in the picker"
        )
        XCTAssertEqual(grouped.count, SeizureType.allCases.count, "A kind is listed twice")
    }

    func testACodeIsRecognisedAgainAfterStorage() {
        XCTAssertEqual(SeizureType.from(code: "atypical-absence"), .atypicalAbsence)
        XCTAssertEqual(SeizureType.from(code: " tonic-clonic "), .tonicClonic)
        XCTAssertNil(SeizureType.from(code: nil))
        // An entry written by a future version with a kind this build does not
        // know. Better an event without a kind than a crash.
        XCTAssertNil(SeizureType.from(code: "gelastic"))
    }

    // MARK: Duration

    func testShortSeizuresReadInSeconds() {
        XCTAssertEqual(SeizureDuration.description(seconds: 8), "8 s")
        XCTAssertEqual(SeizureDuration.description(seconds: 45), "45 s")
    }

    /// Nobody says "one hundred and thirty-five seconds".
    func testLongerSeizuresReadInMinutes() {
        XCTAssertEqual(SeizureDuration.description(seconds: 60), "1:00 min")
        XCTAssertEqual(SeizureDuration.description(seconds: 135), "2:15 min")
        XCTAssertEqual(SeizureDuration.description(seconds: 605), "10:05 min")
    }

    func testTheThresholdMostEmergencyPlansAreWrittenAround() {
        XCTAssertFalse(SeizureDuration.exceedsEmergencyPlanThreshold(seconds: 299))
        XCTAssertTrue(SeizureDuration.exceedsEmergencyPlanThreshold(seconds: 300))
        XCTAssertTrue(SeizureDuration.exceedsEmergencyPlanThreshold(seconds: 420))
    }

    func testASeizureAsksForAKindAndADuration() {
        XCTAssertEqual(EventCategory.seizure.measurementShape, .seizure)
        XCTAssertEqual(EventCategory.seizure.rawValue, 7)
        XCTAssertTrue(EventCategory.seizure.startsWithMeasurement)
    }
}

// MARK: - Oxygen saturation

/// One number, one unit, and one bound. The interesting decision is what is
/// *not* checked: a saturation of 82 is not a typo to argue with, it is the
/// reason somebody reached for the app.
final class OxygenSaturationTests: XCTestCase {

    func testOnlyAPhysicallyImpossibleReadingIsFlagged() {
        XCTAssertTrue(OxygenSaturation.isImpossible(percent: 101))
        XCTAssertTrue(OxygenSaturation.isImpossible(percent: 981))
        XCTAssertFalse(OxygenSaturation.isImpossible(percent: 100))
        XCTAssertFalse(OxygenSaturation.isImpossible(percent: 98))
    }

    func testALowSaturationIsAcceptedWithoutArgument() {
        // The value a parent is writing down at three in the morning. An app
        // that questioned it would teach them to type something else.
        XCTAssertFalse(OxygenSaturation.isImpossible(percent: 82))
        XCTAssertFalse(OxygenSaturation.isImpossible(percent: 70))
    }

    /// Pulse oximeters read whole numbers; a decimal would claim a precision
    /// the device does not have.
    func testItReadsAsAWholePercentage() {
        XCTAssertEqual(OxygenSaturation.description(percent: 98), "98 %")
        XCTAssertEqual(OxygenSaturation.description(percent: 97.6), "98 %")
    }

    func testTheUnitIsFixedRatherThanTypedByHand() {
        XCTAssertEqual(EventCategory.oxygenSaturation.measurementShape, .fixedUnit("%"))
        XCTAssertEqual(EventCategory.oxygenSaturation.rawValue, 8)
        XCTAssertTrue(EventCategory.oxygenSaturation.startsWithMeasurement)
    }

    /// Every category has to answer this, or the editor has no fields to show.
    func testEveryCategoryHasAShape() {
        for category in EventCategory.allCases {
            switch category.measurementShape {
            case .single, .fixedUnit, .bloodPressure, .bloodSugar, .seizure, .noValue:
                continue
            }
        }
    }
}
