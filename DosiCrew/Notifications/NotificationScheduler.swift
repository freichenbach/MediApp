import CoreData
import Foundation
import UserNotifications

/// Plans the local reminders for this device.
///
/// Reminders are deliberately *not* synced: every iPhone computes them from the
/// same rules. What is synced is the fact that a dose was given — and when that
/// arrives from iCloud, `reschedule()` runs again and drops the reminder for a
/// slot somebody else has already handled.
actor NotificationScheduler {

    static let shared = NotificationScheduler()

    /// iOS keeps at most 64 pending requests per app. Each slot may schedule a
    /// due reminder plus an overdue follow-up, so the slot budget is half that,
    /// with headroom to spare.
    private static let slotBudget = 28
    private static let horizonInDays = 2
    private static let overdueDelay: TimeInterval = 30 * 60

    static let categoryIdentifier = "DOSE"
    static let markGivenAction = "MARK_GIVEN"
    static let snoozeAction = "SNOOZE"
    static let snoozeInterval: TimeInterval = 15 * 60

    private let center = UNUserNotificationCenter.current()

    // MARK: - Setup

    nonisolated func registerCategories() {
        let given = UNNotificationAction(
            identifier: Self.markGivenAction,
            title: String(localized: "Given"),
            options: [.authenticationRequired]
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeAction,
            title: String(localized: "Remind me in 15 minutes"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [given, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            PersistenceController.logger.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the whole pending set. Cheap enough to call on every change, and
    /// far safer than trying to patch individual requests.
    func reschedule() async {
        // The screenshot run must not be interrupted by the system's
        // notification permission alert.
        guard !PersistenceController.isRunningUITests else { return }

        guard AppSettings.remindersEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard await requestAuthorization() else { return }
        case .denied:
            return
        default:
            break
        }

        let plan = await Self.loadPlanData()
        guard !plan.medications.isEmpty else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let now = Date()
        let slots = ScheduleEngine.upcomingSlots(
            medications: plan.medications,
            after: now,
            withinDays: Self.horizonInDays,
            limit: Self.slotBudget
        )

        var requests: [UNNotificationRequest] = []
        for slot in slots {
            guard let medication = plan.medications.first(where: { $0.id == slot.medicationID }) else { continue }
            guard !plan.isHandled(slot) else { continue }
            requests.append(contentsOf: Self.requests(for: slot, medication: medication))
        }

        center.removeAllPendingNotificationRequests()
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                PersistenceController.logger.error("Scheduling a reminder failed: \(error.localizedDescription)")
            }
        }
    }

    /// Re-fires a single reminder a quarter of an hour later.
    func snooze(medicationID: UUID, medicationName: String, scheduledAt: Date) async {
        let content = UNMutableNotificationContent()
        content.title = medicationName
        content.body = String(localized: "Still open — please give this dose.")
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = Self.userInfo(medicationID: medicationID, scheduledAt: scheduledAt)

        let request = UNNotificationRequest(
            identifier: "snooze-\(medicationID.uuidString)-\(scheduledAt.timeIntervalSinceReferenceDate)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.snoozeInterval, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: - Request building

    private static func requests(
        for slot: PlannedSlot,
        medication: MedicationSnapshot
    ) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []

        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = body(for: medication)
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo(medicationID: medication.id, scheduledAt: slot.scheduledAt)
        content.threadIdentifier = medication.id.uuidString

        result.append(
            UNNotificationRequest(
                identifier: identifier(prefix: "dose", medicationID: medication.id, scheduledAt: slot.scheduledAt),
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: slot.scheduledAt
                    ),
                    repeats: false
                )
            )
        )

        guard AppSettings.overdueRemindersEnabled else { return result }

        let overdueDate = slot.scheduledAt.addingTimeInterval(overdueDelay)
        guard overdueDate > Date() else { return result }

        let overdueContent = UNMutableNotificationContent()
        overdueContent.title = medication.name
        overdueContent.body = String(localized: "Not ticked off yet — has anyone given this dose?")
        overdueContent.sound = .default
        overdueContent.categoryIdentifier = categoryIdentifier
        overdueContent.userInfo = userInfo(medicationID: medication.id, scheduledAt: slot.scheduledAt)
        overdueContent.threadIdentifier = medication.id.uuidString

        result.append(
            UNNotificationRequest(
                identifier: identifier(prefix: "overdue", medicationID: medication.id, scheduledAt: slot.scheduledAt),
                content: overdueContent,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: overdueDate
                    ),
                    repeats: false
                )
            )
        )
        return result
    }

    /// Names the child. With more than one child on the plan, "5 ml due" would
    /// be an invitation to dose the wrong one.
    private static func body(for medication: MedicationSnapshot) -> String {
        let name = medication.patientName.isEmpty
            ? String(localized: "your child")
            : medication.patientName
        let dose = Medication.doseDescription(amount: medication.doseAmount, unit: medication.doseUnit)
        if dose.isEmpty {
            return String(localized: "Dose due for \(name).")
        }
        return String(localized: "\(dose) due for \(name).")
    }

    static func identifier(prefix: String, medicationID: UUID, scheduledAt: Date) -> String {
        "\(prefix)-\(medicationID.uuidString)-\(Int(scheduledAt.timeIntervalSinceReferenceDate.rounded()))"
    }

    static func userInfo(medicationID: UUID, scheduledAt: Date) -> [String: Any] {
        [
            "medicationID": medicationID.uuidString,
            "scheduledAt": scheduledAt.timeIntervalSinceReferenceDate
        ]
    }

    // MARK: - Reading the plan

    struct PlanData {
        var medications: [MedicationSnapshot]
        var handledSlots: Set<String>

        func isHandled(_ slot: PlannedSlot) -> Bool {
            handledSlots.contains(PlanData.key(medicationID: slot.medicationID, scheduledAt: slot.scheduledAt))
        }

        static func key(medicationID: UUID, scheduledAt: Date) -> String {
            // Rounded to the second: Core Data and CloudKit both introduce
            // sub-second drift, and truncation would turn 7.9999 into a miss.
            "\(medicationID.uuidString)@\(Int(scheduledAt.timeIntervalSinceReferenceDate.rounded()))"
        }
    }

    /// Reads on a background context so scheduling never blocks the UI.
    private static func loadPlanData() async -> PlanData {
        let container = PersistenceController.shared.container
        return await withCheckedContinuation { continuation in
            let context = container.newBackgroundContext()
            context.perform {
                // Every child's medications, not just the first patient's.
                let medicationRequest = NSFetchRequest<Medication>(entityName: "Medication")
                medicationRequest.predicate = NSPredicate(format: "isArchived == NO")
                let medications = ((try? context.fetch(medicationRequest)) ?? []).map { $0.snapshot() }

                // Only slots inside the horizon can still be pending, so the log
                // fetch is bounded rather than reading the whole history.
                let horizonEnd = Date().addingTimeInterval(TimeInterval(horizonInDays + 1) * 86_400)
                let logRequest = NSFetchRequest<DoseLog>(entityName: "DoseLog")
                logRequest.predicate = NSPredicate(
                    format: "scheduledAt != nil AND scheduledAt >= %@ AND scheduledAt <= %@",
                    Date().addingTimeInterval(-86_400) as NSDate,
                    horizonEnd as NSDate
                )
                let logs = (try? context.fetch(logRequest)) ?? []
                let handled = Set(logs.compactMap { log -> String? in
                    guard let medicationID = log.medication?.id, let scheduledAt = log.scheduledAt else { return nil }
                    return PlanData.key(medicationID: medicationID, scheduledAt: scheduledAt)
                })

                continuation.resume(
                    returning: PlanData(medications: medications, handledSlots: handled)
                )
            }
        }
    }
}
