import CloudKit
import CoreData
import os

/// Owns the Core Data stack. Two stores share one model: `private.sqlite`
/// mirrors this user's own iCloud database, `shared.sqlite` mirrors everything
/// other people have shared with them. That split is what makes several people
/// see the same medication plan — SwiftData currently mirrors the private
/// database only and has no CKShare API.
final class PersistenceController {

    static let shared = PersistenceController()

    /// Must match the container configured under Signing & Capabilities.
    static let cloudKitContainerIdentifier = "iCloud.es.reichenbach.MediApp"

    static let logger = Logger(subsystem: "es.reichenbach.MediApp", category: "persistence")

    let container: NSPersistentCloudKitContainer

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    /// Set when the stores fail to load, so the UI can explain itself instead of
    /// showing an empty plan that looks like "no medications".
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MediApp")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            container.persistentStoreDescriptions = Self.cloudKitStoreDescriptions()
        }

        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                self.loadError = error
                Self.logger.error("Failed to load store \(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
                return
            }
            guard let url = description.url,
                  let store = self.container.persistentStoreCoordinator.persistentStore(for: url)
            else { return }

            switch description.cloudKitContainerOptions?.databaseScope {
            case .private: self.privateStore = store
            case .shared: self.sharedStore = store
            default: self.privateStore = self.privateStore ?? store
            }
        }

        // Records arriving from CloudKit must not clobber a local edit that has
        // not been pushed yet, and vice versa: merge property by property.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "app"
        container.viewContext.name = "viewContext"

        if !inMemory {
            do {
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                Self.logger.error("Query generation pinning failed: \(error.localizedDescription)")
            }
        }
    }

    private static func cloudKitStoreDescriptions() -> [NSPersistentStoreDescription] {
        let baseURL = NSPersistentContainer.defaultDirectoryURL()

        let privateDescription = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("private.sqlite"))
        privateDescription.configuration = "Default"
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        let sharedDescription = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("shared.sqlite"))
        sharedDescription.configuration = "Default"
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        for description in [privateDescription, sharedDescription] {
            // Both are required for CloudKit mirroring and for the remote-change
            // notification the reminder scheduler listens to.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        return [privateDescription, sharedDescription]
    }

    // MARK: - Saving

    /// Saves and reports failure rather than trapping: a dropped save on a
    /// medication log is worth surfacing, not crashing on.
    @discardableResult
    func save(_ context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? viewContext
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            Self.logger.error("Save failed: \(error.localizedDescription)")
            context.rollback()
            return false
        }
    }

    // MARK: - Sharing

    func isShared(_ object: NSManagedObject) -> Bool {
        existingShare(for: object) != nil
    }

    func existingShare(for object: NSManagedObject) -> CKShare? {
        try? container.fetchShares(matching: [object.objectID])[object.objectID]
    }

    /// Whether the current user may write to `object`. Participants invited as
    /// read-only must not be able to tick off a dose.
    func canEdit(_ object: NSManagedObject) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func participants(for object: NSManagedObject) -> [CKShare.Participant] {
        existingShare(for: object)?.participants ?? []
    }

    /// Creates (or returns) the CKShare rooted at `patient`. Sharing the patient
    /// shares the whole graph hanging off it — medications, schedules, logs and
    /// events.
    func share(_ patient: Patient) async throws -> (CKShare, CKContainer) {
        if let existing = existingShare(for: patient) {
            return (existing, CKContainer(identifier: Self.cloudKitContainerIdentifier))
        }
        // The share's title is supplied by the sharing controller rather than
        // written here: mutating the CKShare locally would not be persisted.
        let (_, share, ckContainer) = try await container.share([patient], to: nil)
        return (share, ckContainer)
    }

    func acceptShare(metadata: CKShare.Metadata) {
        guard let sharedStore else {
            Self.logger.error("Share accepted before the shared store finished loading")
            return
        }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                Self.logger.error("Accepting share failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the current user from a shared plan, or deletes the share when
    /// the current user owns it.
    func stopSharing(_ patient: Patient) async throws {
        guard let share = existingShare(for: patient) else { return }
        let ckContainer = CKContainer(identifier: Self.cloudKitContainerIdentifier)
        let database = share.currentUserParticipant?.userIdentity.userRecordID == share.owner.userIdentity.userRecordID
            ? ckContainer.privateCloudDatabase
            : ckContainer.sharedCloudDatabase
        try await database.deleteRecord(withID: share.recordID)
    }
}

// MARK: - Previews and tests

extension PersistenceController {

    /// In-memory stack with a small, deterministic plan — used by SwiftUI
    /// previews so they never touch iCloud.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let patient = Patient.makeDefault(in: context)
        patient.name = "Mia"
        patient.birthDate = calendar.date(byAdding: .year, value: -6, to: today)

        let antibiotic = Medication.make(in: context, patient: patient)
        antibiotic.name = "Amoxicillin"
        antibiotic.formEnum = .liquid
        antibiotic.doseAmount = 5
        antibiotic.doseUnit = "ml"
        antibiotic.strengthText = "250 mg / 5 ml"
        antibiotic.instructions = "With a meal"
        antibiotic.colorHex = MedColor.teal.rawValue
        antibiotic.startDate = today
        antibiotic.endDate = calendar.date(byAdding: .day, value: 6, to: today)
        let antibioticRule = ScheduleRule.make(in: context, medication: antibiotic)
        antibioticRule.minutes = [8 * 60, 14 * 60, 20 * 60]

        let vitamin = Medication.make(in: context, patient: patient)
        vitamin.name = "Vitamin D"
        vitamin.formEnum = .drops
        vitamin.doseAmount = 1
        vitamin.doseUnit = "drops"
        vitamin.colorHex = MedColor.yellow.rawValue
        let vitaminRule = ScheduleRule.make(in: context, medication: vitamin)
        vitaminRule.minutes = [9 * 60]

        if let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: today) {
            DoseLog.make(
                in: context,
                medication: antibiotic,
                scheduledAt: morning,
                status: .given,
                personName: "Papa",
                takenAt: morning.addingTimeInterval(7 * 60)
            )
        }

        let fever = CareEvent.make(in: context, patient: patient)
        fever.categoryEnum = .fever
        fever.title = "Fever in the morning"
        fever.hasMeasurement = true
        fever.measurementValue = 38.9
        fever.measurementUnit = "°C"
        fever.personName = "Mama"

        controller.save(context)
        return controller
    }()
}
