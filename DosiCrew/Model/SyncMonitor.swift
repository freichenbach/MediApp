import CoreData
import Foundation

/// Watches what CloudKit mirroring is actually doing.
///
/// Without this the app has no honest answer to the only question that matters
/// on a shared plan: *do the others see what I ticked off?* Core Data reports
/// sync failures only to the console, so a broken container, a signed-out
/// iCloud account or a schema that was never deployed all look exactly like
/// "nothing has changed yet".
final class SyncMonitor: ObservableObject {

    /// False when nothing is mirrored at all — unit tests, or the local-only
    /// fallback store. The UI then explains that instead of showing a
    /// permanently empty sync status.
    @Published private(set) var isEnabled: Bool

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastFailure: Date?
    @Published private(set) var lastErrorDescription: String?

    /// True once mirroring has been running for a while without a single
    /// successful exchange — the state that must not pass for "fine".
    var hasNeverSucceeded: Bool { isEnabled && lastSuccess == nil }

    private var observer: NSObjectProtocol?

    /// Created before the stores are loaded — whether mirroring runs is only
    /// known afterwards, so observation starts in `start(enabled:)`.
    init() {
        isEnabled = false
    }

    /// Begins observing, or stays quiet when nothing is mirrored. Calling it
    /// twice is a no-op.
    func start(enabled: Bool) {
        guard observer == nil else { return }
        isEnabled = enabled
        guard enabled else { return }

        // Delivered on the main queue, so the @Published writes below are safe.
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }
            self?.apply(event)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func apply(_ event: NSPersistentCloudKitContainer.Event) {
        // An event without an end date is one that just started.
        guard let endDate = event.endDate else {
            isSyncing = true
            return
        }
        isSyncing = false

        if event.succeeded {
            lastSuccess = endDate
            lastFailure = nil
            lastErrorDescription = nil
        } else {
            lastFailure = endDate
            lastErrorDescription = event.error?.localizedDescription
        }
    }
}
