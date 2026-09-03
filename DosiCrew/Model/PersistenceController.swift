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

    /// The one-off run that creates the CloudKit development schema.
    ///
    /// `init` has to know about it too, not just the schema step: this run must
    /// not be rescued by the local fallback store. See `loadLocalFallbackStore`.
    static var isBootstrappingCloudKitSchema: Bool {
        // Always false in a release binary, so every behaviour that hangs off
        // this flag is guaranteed to stay out of TestFlight and the App Store
        // without an #if at each call site.
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-DosiCrewInitializeCloudKitSchema")
        #else
        return false
        #endif
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
                // The whole error, not `localizedDescription`: Core Data
                // answers that with "Ein Core Data-Fehler ist aufgetreten.",
                // which is true and says nothing. The reason is in `userInfo`.
                Self.logger.error("Failed to load store \(description.url?.lastPathComponent ?? "?"): \(String(describing: error))")
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
            // Everything except the schema bootstrap: keep the plan usable
            // without syncing. That run is the exception — rescuing it would
            // replace the CloudKit stores with a plain one and turn a clear
            // "the container is not available, because …" into a baffling
            // "no stores are configured to use CloudKit".
            #if DEBUG
            reportCloudKitStoreFailure()
            #endif
            if !Self.isBootstrappingCloudKitSchema { loadLocalFallbackStore() }
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

    /// Internal rather than private so a test can add these to a coordinator and
    /// prove they are actually addable. See `StoreDescriptionTests`.
    ///
    /// Deliberately **no** `configuration` on either description. Setting it to
    /// "Default" — as several CloudKit examples do — makes Core Data look for a
    /// configuration by that literal name, and `DosiCrew.xcdatamodel` declares
    /// none. Both stores then refuse to open with "Unable to find a
    /// configuration named 'Default' in the specified managed object model",
    /// the app falls back to a local store, and nothing syncs. Left unset, the
    /// default configuration applies, which holds every entity — which is what
    /// both stores need anyway: the same entities in two files, one per
    /// CloudKit scope.
    static func cloudKitStoreDescriptions() -> [NSPersistentStoreDescription] {
        let baseURL = NSPersistentContainer.defaultDirectoryURL()

        let privateDescription = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("private.sqlite"))
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        let sharedDescription = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("shared.sqlite"))
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
        guard Self.isBootstrappingCloudKitSchema else { return }

        // Ask first. Without this check Core Data answers a coordinator that
        // holds no mirrored store with "no stores in the coordinator are
        // configured to use CloudKit" — true, unhelpful, and three steps
        // downstream of whatever actually went wrong.
        guard hasCloudKitStore else {
            print(Self.frame("""
                Schema NOT initialized: no CloudKit-backed store is open.
                The reason was printed above.
                """))
            return
        }

        // Printed as well as logged: this runs once, by hand, and the person
        // doing it needs an unambiguous answer in the Xcode console rather
        // than having to go hunting in the unified log.
        do {
            try container.initializeCloudKitSchema(options: [])
            print(Self.frame("""
                CloudKit development schema initialized.
                Container: \(Self.cloudKitContainerIdentifier)

                Next: icloud.developer.apple.com → CloudKit Console → this
                container → Schema → Deploy Schema Changes → Production.
                Then remove the -DosiCrewInitializeCloudKitSchema argument.
                """))
            Self.logger.notice("CloudKit development schema initialized for \(Self.cloudKitContainerIdentifier)")
        } catch {
            print(Self.frame("""
                Initializing the CloudKit schema FAILED.
                Container: \(Self.cloudKitContainerIdentifier)

                \(error)
                """))
            Self.logger.error("Initializing the CloudKit schema failed: \(error.localizedDescription)")
        }
    }
    #endif

    /// Whether any loaded store actually mirrors to CloudKit.
    ///
    /// Matched by URL against the descriptions, because a loaded
    /// `NSPersistentStore` does not carry its CloudKit options. False both when
    /// nothing loaded and when the local fallback replaced the descriptions.
    var hasCloudKitStore: Bool {
        container.persistentStoreCoordinator.persistentStores.contains { store in
            guard let url = store.url else { return false }
            return container.persistentStoreDescriptions.contains {
                $0.url == url && $0.cloudKitContainerOptions != nil
            }
        }
    }

    /// Says why the mirrored stores did not open.
    ///
    /// The shipping app swallows this on purpose — it falls back to a local
    /// store so a dose can still be recorded, and a person holding a sick child
    /// is not helped by an `NSError`. A debug build is the opposite case: it is
    /// a developer's build, and whoever is looking at the console can act on
    /// the answer. So the error is printed in full there, with the handful of
    /// causes that actually produce it — and without needing to remember the
    /// bootstrap launch argument first.
    private func reportCloudKitStoreFailure() {
        let detail = loadError.map { String(describing: $0) } ?? "The stores did not load, and Core Data reported no error."
        print(Self.frame("""
            The CloudKit stores did not open — schema NOT initialized.
            Container: \(Self.cloudKitContainerIdentifier)

            \(detail)

            Read the NSLocalizedFailureReason above first — it usually names
            the cause outright. The list below is only for when it does not:

            1. A configuration named in cloudKitStoreDescriptions() that the
               model does not declare. This one already happened: "Default"
               looks harmless and is not.
            2. Signing & Capabilities → Team. A *Personal Team* cannot use
               CloudKit at all; the entitlement is dropped when signing and the
               store then fails to load. It must be the real team.
            3. Signing & Capabilities → iCloud → Containers. The iCloud
               checkbox on the App ID is not the same thing as an existing
               container. \(Self.cloudKitContainerIdentifier) has to be listed
               there and ticked.
            4. The device or simulator has to be signed into iCloud for the
               schema to be written — though on its own that does not stop the
               stores from loading.
            """))
        Self.logger.error("CloudKit stores unavailable during schema bootstrap: \(detail)")
    }

    /// One shape for both outcomes, so neither scrolls past unnoticed in a
    /// console full of Core Data chatter.
    private static func frame(_ body: String) -> String {
        let rule = String(repeating: "─", count: 60)
        return "\n\(rule)\n\(body)\n\(rule)\n"
    }

    // MARK: - Background work

    /// True when at least one store is actually open.
    ///
    /// Core Data answers a context whose coordinator has no stores with an
    /// Objective-C exception, not a Swift error — so it cannot be caught, and
    /// the app is killed instead of returning a failure. Every path that may
    /// run before the stack is up, or after it failed to come up, has to ask
    /// first.
    var isStoreLoaded: Bool {
        !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    /// Runs `work` on a background context, or returns `nil` when no store is
    /// open.
    ///
    /// The reason this exists rather than each caller building its own context:
    /// the paths that need one are exactly the paths that can run at the worst
    /// moment — a reminder tapped on the lock screen, a silent push waking the
    /// app — where "the stack is up" is an assumption and not a fact.
    @discardableResult
    func withBackgroundContext<T>(
        author: String? = nil,
        _ work: @escaping (NSManagedObjectContext) -> T
    ) async -> T? {
        guard isStoreLoaded else {
            Self.logger.error("Background work skipped: no persistent store is loaded")
            return nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let context = container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            if let author { context.transactionAuthor = author }
            context.perform {
                continuation.resume(returning: work(context))
            }
        }
    }

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
        guard isStoreLoaded else {
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

        // A second child, so previews and screenshots show what the app looks
        // like when two plans run side by side — the case where naming the
        // child in every row stops being decoration.
        let sibling = Patient.makeDefault(in: context)
        sibling.name = "Ben"
        sibling.birthDate = calendar.date(byAdding: .year, value: -3, to: today)

        let drops = Medication.make(in: context, patient: sibling)
        drops.name = "Nasentropfen"
        drops.formEnum = .drops
        drops.doseAmount = 2
        drops.doseUnit = "drops"
        drops.colorHex = MedColor.orange.rawValue
        let dropsRule = ScheduleRule.make(in: context, medication: drops)
        dropsRule.minutes = [8 * 60, 20 * 60]
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
