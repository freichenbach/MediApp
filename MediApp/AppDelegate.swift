import CloudKit
import CoreData
import SwiftUI
import UserNotifications

/// Handles the two things SwiftUI cannot express on its own: accepting a
/// CloudKit share invitation, and reacting to silent pushes that tell us the
/// shared plan changed on someone else's device.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationScheduler.shared.registerCategories()

        // Required for the silent pushes NSPersistentCloudKitContainer uses to
        // announce remote changes. Without it, another person's tick would only
        // show up the next time this device opened the app.
        application.registerForRemoteNotifications()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: PersistenceController.shared.container.persistentStoreCoordinator
        )

        Task { await NotificationScheduler.shared.reschedule() }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Someone else changed the plan. Recompute the local reminders so this
    /// device stops nagging about a dose that has already been given.
    @objc private func storeRemoteChange(_ notification: Notification) {
        Task { await NotificationScheduler.shared.reschedule() }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PersistenceController.logger.error("Remote notification registration failed: \(error.localizedDescription)")
    }
}

/// The share-acceptance callback only exists on the scene delegate, which is
/// why the app installs one at all.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        PersistenceController.shared.acceptShare(metadata: cloudKitShareMetadata)
    }
}
