import CoreData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @AppStorage(AppSettings.personNameKey) private var personName: String = ""
    @ObservedObject private var sync = PersistenceController.shared.syncMonitor
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled: Bool = true
    @AppStorage(AppSettings.overdueRemindersKey) private var overdueReminders: Bool = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var timeSensitiveSetting: UNNotificationSetting = .notSupported
    @State private var criticalAlertSetting: UNNotificationSetting = .notSupported

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(patients, id: \.objectID) { child in
                        NavigationLink {
                            PatientEditView(patient: child)
                        } label: {
                            ChildRow(patient: child)
                        }
                    }

                    Button(action: addChild) {
                        Label("Add child", systemImage: "plus")
                    }
                } header: {
                    Text("Children")
                } footer: {
                    Text("Each child is shared separately.")
                }

                Section {
                    TextField("Your name", text: $personName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("You on this iPhone")
                } footer: {
                    Text("Shown next to every dose you tick off. Stays on this device and is not shared as a setting.")
                }

                Section {
                    syncStatus
                }

                Section {
                    Toggle("Remind me when a dose is due", isOn: $remindersEnabled)
                    Toggle("Remind me again if it stays open", isOn: $overdueReminders)
                        .disabled(!remindersEnabled)

                    if authorizationStatus == .denied {
                        Label("Notifications are switched off for DosiCrew in iOS Settings.", systemImage: "bell.slash")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        loudnessStatus
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Each iPhone reminds on its own. When somebody else ticks a dose off, the pending reminder disappears here too.")
                }


                Section {
                    Text("DosiCrew helps you organise who gives what and when. It does not check doses, interactions or contraindications — that stays with your doctor or pharmacist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Please note")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: load)
            .onChange(of: remindersEnabled) { _, _ in rescheduleReminders() }
            .onChange(of: overdueReminders) { _, _ in rescheduleReminders() }
        }
    }

    /// People rely on this plan being shared. A sync that silently does nothing
    /// is more dangerous than a visible error, so every state says what it is.
    @ViewBuilder
    private var syncStatus: some View {
        if PersistenceController.shared.usesLocalFallback {
            warning("iCloud is not available right now. Everything is saved on this iPhone, but nothing is being shared — the others cannot see what you tick off.")
        } else if !sync.isEnabled {
            EmptyView()
        } else if let error = sync.lastErrorDescription {
            warning("Syncing is failing, so the others may not be seeing your ticks. \(error)")
        } else if let lastSuccess = sync.lastSuccess {
            Label {
                Text("Last synced \(TimeText.of(lastSuccess))")
            } icon: {
                Image(systemName: "checkmark.icloud")
            }
            .foregroundStyle(.secondary)
        } else if sync.isSyncing {
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else {
            warning("Nothing has synced since the app started. Until it does, the others cannot see what you tick off.")
        }
    }

    /// Says what a reminder can actually do to a quiet iPhone.
    ///
    /// Worth a line of its own because the honest answer is not the one people
    /// assume: a reminder gets past Focus and Do Not Disturb, but the mute
    /// switch silences it until Apple grants the critical-alert entitlement.
    /// Better to say so here than to let somebody rely on a ring that never
    /// comes.
    @ViewBuilder
    private var loudnessStatus: some View {
        if criticalAlertSetting == .enabled {
            Label("Rings even when the iPhone is silenced.", systemImage: "bell.badge.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if timeSensitiveSetting == .enabled {
            Label("Gets past Focus and Do Not Disturb. A silenced iPhone still stays silent.", systemImage: "bell.and.waves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if timeSensitiveSetting == .disabled {
            VStack(alignment: .leading, spacing: 4) {
                Label("Time sensitive notifications are switched off for DosiCrew, so Focus will hold reminders back.", systemImage: "bell.slash")
                    .foregroundStyle(.orange)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iOS Settings", destination: url)
                }
            }
            .font(.footnote)
        }
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }

    private func load() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
                timeSensitiveSetting = settings.timeSensitiveSetting
                criticalAlertSetting = settings.criticalAlertSetting
            }
        }
    }

    private func addChild() {
        Patient.makeDefault(in: context)
        PersistenceController.shared.save(context)
    }

    private func rescheduleReminders() {
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

/// Name, colour dot and a one-line summary, so the list of children reads at a
/// glance rather than as a row of identical names.
private struct ChildRow: View {
    @ObservedObject var patient: Patient

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(patient.id.map(MedColor.forPatient) ?? MedColor.fallback.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        let count = patient.activeMedications.count
        return count == 1
            ? String(localized: "1 medication")
            : String(localized: "\(count) medications")
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
