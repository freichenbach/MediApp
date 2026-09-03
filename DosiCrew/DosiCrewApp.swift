import SwiftUI

@main
struct DosiCrewApp: App {
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

    static let lastSeizureTypeKey = "lastSeizureType"

    /// The kind of seizure last recorded, offered again next time.
    ///
    /// A child with atypical absences has atypical absences; after the first
    /// entry the picker is already right, and recording a seizure becomes two
    /// taps at a moment when nobody has attention to spare. Per device rather
    /// than synced: it is a convenience, and syncing it would mean one person's
    /// entry silently changing what the other sees preselected.
    static var lastSeizureType: SeizureType? {
        get { SeizureType.from(code: UserDefaults.standard.string(forKey: lastSeizureTypeKey)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: lastSeizureTypeKey) }
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
