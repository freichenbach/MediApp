import SwiftUI

@main
struct DosiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let persistence = PersistenceController.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Coming back to the foreground is the cheapest moment to notice that
            // someone else already gave a dose while the app was closed.
            Task { await NotificationScheduler.shared.reschedule() }
        }
    }
}

/// Central place for the app-wide preferences that are deliberately *not*
/// synced: who is using this particular device.
enum AppSettings {
    static let personNameKey = "personName"
    static let remindersEnabledKey = "remindersEnabled"
    static let overdueRemindersKey = "overdueRemindersEnabled"

    static var personName: String {
        let stored = UserDefaults.standard.string(forKey: personNameKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Someone") : trimmed
    }

    static var hasPersonName: Bool {
        !(UserDefaults.standard.string(forKey: personNameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var remindersEnabled: Bool {
        UserDefaults.standard.object(forKey: remindersEnabledKey) as? Bool ?? true
    }

    static var overdueRemindersEnabled: Bool {
        UserDefaults.standard.object(forKey: overdueRemindersKey) as? Bool ?? true
    }
}
