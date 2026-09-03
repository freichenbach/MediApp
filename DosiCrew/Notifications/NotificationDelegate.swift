import Foundation
import UserNotifications

/// Lets a dose be ticked off straight from the notification, which is the
/// difference between the plan staying accurate and everyone guessing later.
///
/// `@MainActor` is not decoration — without it the app crashed on launch. Both
/// delegate methods are `async`, and Swift bridges each one to an Objective-C
/// completion handler that runs on whatever executor the method happened to
/// finish on. UIKit then does its snapshot and state-restoration work on that
/// thread, and asserts:
///
///     -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
///     -[NSAssertionHandler handleFailureInMethod:…]  →  SIGABRT
///
/// The report showed it on Thread 1, 107 ms after a launch from the lock
/// screen. Isolating the class to the main actor makes both methods return
/// there, so the bridged completion is invoked on the main thread.
@MainActor
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
            await DoseBook.recordGiven(
                medicationID: medicationID,
                scheduledAt: scheduledAt,
                author: "notification"
            )
            Task.detached { await NotificationScheduler.shared.reschedule() }

        case NotificationScheduler.snoozeAction:
            let name = await DoseBook.medicationName(for: medicationID)
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

}
