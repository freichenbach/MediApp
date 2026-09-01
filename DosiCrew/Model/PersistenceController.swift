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
    static let cloudKitContainerIdentifier = "iCloud.es.reichenbach.DosiCrew"

    static let logger = Logger(subsystem: "es.reichenbach.DosiCrew", category: "persistence")

    let container: NSPersistentCloudKitContainer

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    /// Set when the stores fail to load, so the UI can explain itself instead of
    /// showing an empty plan that looks like "no medications".
    private(set) var loadError: Error?

    /// True when the CloudKit stores could not be opened and the app fell back
    /// to a local-only store. Nothing syncs in that state, which the people
    /// sharing a plan must be told about.
    private(set) var usesLocalFallback = false

    /// The unit tests are hosted by the app, so `@main` runs before them. They
    /// must not touch the real, iCloud-backed store.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set by the screenshot UI tests. The app then runs on an in-memory store
    /// filled with the demo plan, so the pictures show something to look at and
    /// never touch anybody's real data.
    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-DosiCrewUITestSeed")
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Reports whether mirroring is actually exchanging anything, so the UI can
    /// say so rather than let a silent outage pass for a quiet day.
    let syncMonitor = SyncMonitor()

    // MARK: - Init

    init(inMemory: Bool = false) {
        let useInMemoryStore = inMemory || Self.isRunningUnitTests || Self.isRunningUITests
        container = NSPersistentCloudKitContainer(name: "DosiCrew")

        if useInMemoryStore {
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

        if !useInMemoryStore && container.persistentStoreCoordinator.persistentStores.isEmpty {
            loadLocalFallbackStore()
        }

        // Only meaningful once it is clear whether mirroring is running at all.
        syncMonitor.start(enabled: !useInMemoryStore && !usesLocalFallback)

        #if DEBUG
        if !useInMemoryStore { initializeCloudKitSchemaIfRequested() }
        #endif

        // Records arriving from CloudKit must not clobber a local edit that has
        // not been pushed yet, and vice versa: merge property by property.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.transactionAuthor = "app"
        container.viewContext.name = "viewContext"

        if Self.isRunningUITests && !inMemory {
            Self.seedDemoData(into: container.viewContext)
            save(container.viewContext)
        }

        if !useInMemoryStore {
            do {
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                Self.logger.error("Query generation pinning failed: \(error.localizedDescription)")
            }
        }
    }

    /// Opens `private.sqlite` again, this time without CloudKit mirroring.
    ///
    /// Deliberately the *same* file the mirrored store uses: pointing at a
    /// separate one would split the history in two, and a dose recorded during
    /// the outage would look lost once syncing recovered. Losing sync is
    /// survivable, losing a logged dose is not.
    private func loadLocalFallbackStore() {
        Self.logger.warning("CloudKit stores did not open — retrying without mirroring")

        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("private.sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                self.loadError = error
                Self.logger.error("Local fallback store failed too: \(error.localizedDescription)")
                return
            }
            self.usesLocalFallback = true
            self.loadError = nil
            if let url = description.url {
                self.privateStore = self.container.persistentStoreCoordinator.persistentStore(for: url)
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

    // MARK: - CloudKit schema

    #if DEBUG
    /// Creates the CloudKit **development** schema from the Core Data model.
    ///
    /// This exists because of a chicken-and-egg problem: TestFlight and App
    /// Store builds always talk to the *production* environment, and the schema
    /// has to be there before the first such build — but the schema itself is
    /// only ever generated from a run in the development environment. So it has
    /// to happen once, from a development build on a Mac or a device signed
    /// into iCloud, and is then deployed to production in the CloudKit Console.
    ///
    /// Guarded twice over: `#if DEBUG` keeps it out of any release binary, and
    /// the launch argument keeps it out of ordinary debug runs. Run it with:
    ///
    ///     Product → Scheme → Edit Scheme → Run → Arguments
    ///     add `-DosiCrewInitializeCloudKitSchema`
    ///
    /// See the "CloudKit-Schema anlegen" runbook in README.md.
    private func initializeCloudKitSchemaIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-DosiCrewInitializeCloudKitSchema") else { return }
        do {
            try container.initializeCloudKitSchema(options: [])
            Self.logger.notice("CloudKit development schema initialized — deploy it to production in the CloudKit Console")
        } catch {
            Self.logger.error("Initializing the CloudKit schema failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Saving

    /// Saves and reports failure rather than trapping: a dropped save on a
    /// medication log is worth surfacing, not crashing on.
    @discardableResult
    func save(_ context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? viewContext
        guard context.hasChanges else { return true }

        // Saving into a coordinator with no stores raises an Objective-C
        // exception, which Swift cannot catch — the app would be terminated
        // rather than returning an error. Refuse the save instead.
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            Self.logger.error("Save skipped: no persistent store is loaded")
            context.rollback()
            return false
        }

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

    /// A small, deterministic plan: one child, two medications, one dose
    /// already given — and one dose given twice, so the duplicate warning is
    /// visible wherever this data is shown.
    ///
    /// Shared by the SwiftUI previews and by the screenshot UI tests, so the
    /// pictures and the previews cannot drift apart.
    static func seedDemoData(into context: NSManagedObjectContext) {
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
        antibiotic.instructions = String(localized: "With a meal")
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

        // The morning dose, given once by one parent …
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

        // … and the midday dose given by both, minutes apart. This is the
        // failure the app exists to catch, so it belongs in every preview and
        // on every screenshot.
        if let midday = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) {
            DoseLog.make(
                in: context,
                medication: antibiotic,
                scheduledAt: midday,
                status: .given,
                personName: "Mama",
                takenAt: midday.addingTimeInterval(2 * 60)
            )
            DoseLog.make(
                in: context,
                medication: antibiotic,
                scheduledAt: midday,
                status: .given,
                personName: "Oma",
                takenAt: midday.addingTimeInterval(9 * 60)
            )
        }

        let fever = CareEvent.make(in: context, patient: patient)
        fever.categoryEnum = .fever
        fever.title = String(localized: "Fever in the morning")
        fever.hasMeasurement = true
        fever.measurementValue = 38.9
        fever.measurementUnit = "°C"
        fever.personName = "Mama"
    }

    /// In-memory stack with the demo plan — used by SwiftUI previews so they
    /// never touch iCloud.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        seedDemoData(into: controller.viewContext)
        controller.save(controller.viewContext)
        return controller
    }()
}
