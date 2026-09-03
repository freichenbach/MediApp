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

    private static let baseOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

    /// Asks for critical alerts as well.
    ///
    /// Until Apple grants the entitlement the system simply never grants that
    /// option, so asking costs nothing — and once it is granted, the app makes
    /// use of it without a new build. Should the request fail *because* of the
    /// extra option, it is repeated without it: a missed reminder is a worse
    /// outcome than a quiet one.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: Self.baseOptions.union(.criticalAlert))
        } catch {
            PersistenceController.logger.error("Notification authorization failed: \(error.localizedDescription)")
        }
        do {
            return try await center.requestAuthorization(options: Self.baseOptions)
        } catch {
            PersistenceController.logger.error("Notification authorization failed without critical alerts too: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - How loud a reminder may be

    /// What iOS currently lets a reminder do to a quiet iPhone.
    ///
    /// A missed dose is the failure this app exists to prevent, so the reminder
    /// takes the loudest level it is allowed:
    ///
    /// - `.timeSensitive` breaks through Focus and Do Not Disturb. It does
    ///   **not** ring against the mute switch — no entitlement changes that.
    /// - `.critical` does ring against the mute switch. Apple grants it case by
    ///   case, so this case stays unreachable until the entitlement is in the
    ///   build and the person has allowed it.
    enum Urgency {
        case timeSensitive
        case critical

        func apply(to content: UNMutableNotificationContent) {
            switch self {
            case .timeSensitive:
                content.interruptionLevel = .timeSensitive
                content.sound = .default
            case .critical:
                content.interruptionLevel = .critical
                // Not full volume: this has to wake someone in the next room,
                // not startle the child it is about.
                content.sound = .defaultCriticalSound(withAudioVolume: 0.8)
            }
        }
    }

    private static func urgency(for settings: UNNotificationSettings) -> Urgency {
        settings.criticalAlertSetting == .enabled ? .critical : .timeSensitive
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

        var settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard await requestAuthorization() else { return }
            // Re-read: what was just granted decides how loud the reminders
            // below may be, and the settings fetched before the prompt cannot
            // know that yet.
            settings = await center.notificationSettings()
        case .denied:
            return
        default:
            break
        }

        let urgency = Self.urgency(for: settings)

        let plan = await DoseBook.loadPlan(withinDays: Self.horizonInDays)
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
            requests.append(contentsOf: Self.requests(for: slot, medication: medication, urgency: urgency))
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
        let settings = await center.notificationSettings()
        let urgency = Self.urgency(for: settings)

        let content = UNMutableNotificationContent()
        content.title = medicationName
        content.body = String(localized: "Still open — please give this dose.")
        content.categoryIdentifier = Self.categoryIdentifier
        urgency.apply(to: content)
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
        medication: MedicationSnapshot,
        urgency: Urgency
    ) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []

        let content = UNMutableNotificationContent()
        content.title = medication.name
        content.body = body(for: medication)
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo(medicationID: medication.id, scheduledAt: slot.scheduledAt)
        content.threadIdentifier = medication.id.uuidString
        urgency.apply(to: content)

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
        overdueContent.categoryIdentifier = categoryIdentifier
        overdueContent.userInfo = userInfo(medicationID: medication.id, scheduledAt: slot.scheduledAt)
        overdueContent.threadIdentifier = medication.id.uuidString
        urgency.apply(to: overdueContent)

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

}
