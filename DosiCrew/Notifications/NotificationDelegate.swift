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
            await markGiven(medicationID: medicationID, scheduledAt: scheduledAt)
            await NotificationScheduler.shared.reschedule()

        case NotificationScheduler.snoozeAction:
            let name = await medicationName(for: medicationID)
                ?? response.notification.request.content.title
            await NotificationScheduler.shared.snooze(
                medicationID: medicationID,
                medicationName: name,
                scheduledAt: scheduledAt
            )

        default:
            break
        }
    }

    // MARK: - Writing the log

    /// Writes on a background context: the app may not even be in the
    /// foreground when the action is tapped.
    private func markGiven(medicationID: UUID, scheduledAt: Date) async {
        let container = PersistenceController.shared.container
        let personName = AppSettings.personName

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let context = container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            context.transactionAuthor = "notification"
            context.perform {
                defer { continuation.resume() }

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

                do {
                    try context.save()
                } catch {
                    PersistenceController.logger.error("Logging from a notification failed: \(error.localizedDescription)")
                    context.rollback()
                }
            }
        }
    }

    private func medicationName(for medicationID: UUID) async -> String? {
        let container = PersistenceController.shared.container
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let context = container.newBackgroundContext()
            context.perform {
                let request = NSFetchRequest<Medication>(entityName: "Medication")
                request.predicate = NSPredicate(format: "id == %@", medicationID as CVarArg)
                request.fetchLimit = 1
                let medication = (try? context.fetch(request))?.first
                continuation.resume(returning: medication?.displayName)
            }
        }
    }
}
