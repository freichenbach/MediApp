import CoreData
import Foundation
import UserNotifications

/// Lets a dose be ticked off straight from the notification, which is the
/// difference between the plan staying accurate and everyone guessing later.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard
            let rawID = userInfo["medicationID"] as? String,
            let medicationID = UUID(uuidString: rawID),
            let rawDate = userInfo["scheduledAt"] as? Double
        else { return }

        let scheduledAt = Date(timeIntervalSinceReferenceDate: rawDate)

        switch response.actionIdentifier {
        case NotificationScheduler.markGivenAction:
            // Only the write is awaited — it is what the person expects to have
            // happened when the banner disappears. Rebuilding the whole pending
            // set afterwards can take seconds, and iOS terminates an app that
            // keeps it waiting on a notification response. So that part runs
            // detached.
            await markGiven(medicationID: medicationID, scheduledAt: scheduledAt)
            Task.detached { await NotificationScheduler.shared.reschedule() }

        case NotificationScheduler.snoozeAction:
            let name = await medicationName(for: medicationID)
                ?? response.notification.request.content.title
            await NotificationScheduler.shared.snooze(
                medicationID: medicationID,
                medicationName: name,
                scheduledAt: scheduledAt
            )

        default:
            // Tapping the banner itself just opens the app; the Today screen
            // already shows what is due.
            break
        }
    }

    // MARK: - Writing the log

    /// Writes on a background context: the app may not even be in the
    /// foreground when the action is tapped.
    ///
    /// Everything goes through `withBackgroundContext`, which refuses to run at
    /// all when no store is open — this path fires at the one moment when that
    /// is a real possibility, a reminder answered while the app is cold.
    private func markGiven(medicationID: UUID, scheduledAt: Date) async {
        let personName = AppSettings.personName
        let persistence = PersistenceController.shared

        await persistence.withBackgroundContext(author: "notification") { context in
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", medicationID as CVarArg)
            request.fetchLimit = 1
            guard let medication = (try? context.fetch(request))?.first else { return }

            // Somebody may have ticked this slot off in the meantime — from
            // another device, or from the app itself. Do not log it twice.
            let existing = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            existing.predicate = NSPredicate(
                format: "medication == %@ AND scheduledAt >= %@ AND scheduledAt <= %@",
                medication,
                scheduledAt.addingTimeInterval(-ScheduleEngine.slotMatchTolerance) as NSDate,
                scheduledAt.addingTimeInterval(ScheduleEngine.slotMatchTolerance) as NSDate
            )
            existing.fetchLimit = 1
            guard ((try? context.fetch(existing))?.first) == nil else { return }

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
            persistence.save(context)
        }
    }

    private func medicationName(for medicationID: UUID) async -> String? {
        await PersistenceController.shared.withBackgroundContext { context -> String? in
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", medicationID as CVarArg)
            request.fetchLimit = 1
            return (try? context.fetch(request))?.first?.displayName
        } ?? nil
    }
}
