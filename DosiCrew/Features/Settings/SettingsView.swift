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
    /// Nothing about loudness is said before the real values arrive: the
    /// defaults above would briefly claim the worst case and then correct
    /// themselves, which reads as a glitch and teaches people to ignore the
    /// line.
    @State private var notificationSettingsLoaded = false
    @State private var askedForCriticalAlerts = false

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
                    } else if notificationSettingsLoaded {
                        loudnessStatus
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Each iPhone reminds on its own. When somebody else ticks a dose off, the pending reminder disappears here too.")
                }


                Section {
                    NavigationLink {
                        ReportView()
                    } label: {
                        Label("Report for the doctor", systemImage: "doc.text")
                    }
                } header: {
                    Text("Appointments")
                } footer: {
                    Text("A PDF of what was given and when, over the last days or weeks — the answer to the first question in the consulting room.")
                }

                Section {
                    Text("DosiCrew helps you organise who gives what and when. It does not check doses, interactions or contraindications — that stays with your doctor or pharmacist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Please note")
                }
            }
            .dismissibleKeyboard()
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
        // Ahead of everything else: somebody who tapped an invitation and sees
        // no shared plan is looking for this sentence, and a sync verdict about
        // their own data does not answer it.
        if let shareError = PersistenceController.shared.shareAcceptanceError {
            warning("The invitation could not be opened, so the shared plan is not here. \(shareError)")
        } else if PersistenceController.shared.usesLocalFallback {
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
    /// assume, and it differs per iPhone. Somebody who expects a ring at three
    /// in the morning and gets a silent banner does not find out until the dose
    /// has been missed.
    ///
    /// The order runs from the worst state to the best, because the states can
    /// overlap and the most restrictive one is the one worth reading.
    @ViewBuilder
    private var loudnessStatus: some View {
        if timeSensitiveSetting == .disabled {
            settingsHint(
                "Time sensitive notifications are switched off for DosiCrew, so Focus will hold reminders back.",
                icon: "bell.slash"
            )
        } else if criticalAlertSetting == .enabled {
            Label("Rings even when the iPhone is silenced.", systemImage: "bell.badge.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if criticalAlertSetting == .notSupported {
            // For this app `.notSupported` does not mean the iPhone cannot do
            // it — the entitlement is in the build, and the release run refuses
            // to upload without it. It means the permission was never granted,
            // because iOS asks for notification permission exactly once and
            // DosiCrew could not ring through the mute switch when it asked.
            // iOS then shows no switch either, so there is nothing to send
            // anybody to.
            VStack(alignment: .leading, spacing: 8) {
                Label("Reminders may ring through the mute switch, but iOS never granted it — it asks only once, and back then DosiCrew was not allowed to.", systemImage: "bell.badge")
                    .foregroundStyle(.orange)
                if askedForCriticalAlerts {
                    Text("iOS did not ask again. Only removing DosiCrew and installing it afresh resets that. The plan itself is in iCloud and comes back; only the name in these settings has to be typed again.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Ask iOS again") { askForCriticalAlerts() }
                }
            }
            .font(.footnote)
        } else if criticalAlertSetting == .disabled {
            // The state this app is most likely to be in, and the one that used
            // to be invisible: iOS asks for notification permission exactly
            // once, so an iPhone that said yes before this app could ring
            // through the mute switch never gets asked about it. Nothing
            // prompts again — the switch has to be found by hand, and nobody
            // goes looking for a switch they do not know exists.
            settingsHint(
                "Reminders can ring through the mute switch, but that permission is off. iOS only asks once, so it has to be switched on by hand under Notifications › DosiCrew.",
                icon: "bell.badge"
            )
        } else if timeSensitiveSetting == .enabled {
            Label("Gets past Focus and Do Not Disturb. A silenced iPhone still stays silent.", systemImage: "bell.and.waves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// A warning that also offers the way out of it. Naming a switch without a
    /// route to it leaves the reader worse off than saying nothing.
    private func settingsHint(_ text: LocalizedStringKey, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: icon)
                .foregroundStyle(.orange)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open iOS Settings", destination: url)
            }
        }
        .font(.footnote)
    }

    private func warning(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }

    private func load() {
        Task { await refreshNotificationSettings() }
    }

    private func refreshNotificationSettings() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            authorizationStatus = settings.authorizationStatus
            timeSensitiveSetting = settings.timeSensitiveSetting
            criticalAlertSetting = settings.criticalAlertSetting
            notificationSettingsLoaded = true
        }
    }

    /// Asks iOS for the critical-alert permission after the fact.
    ///
    /// This works, which is worth writing down because the obvious reading of
    /// Apple's rule says it should not: iOS asks about notifications once, and
    /// an app that already has permission gets no second dialog. That holds for
    /// the options it has already asked about. Naming an option it never could
    /// — critical alerts, before Apple granted the entitlement — does bring up
    /// a prompt, and answering it turns the switch on. Confirmed on a device
    /// that had granted permission several builds earlier.
    ///
    /// So this is the first thing to try, not the last resort it was written
    /// as. Deleting and reinstalling the app remains the fallback, and the line
    /// above only offers it once this has actually been tried and changed
    /// nothing.
    private func askForCriticalAlerts() {
        Task {
            await NotificationScheduler.shared.requestAuthorization()
            // The refresh comes first: setting the flag before the new values
            // arrive would show "iOS did not ask" for a moment in the very case
            // where it did.
            await refreshNotificationSettings()
            await MainActor.run { askedForCriticalAlerts = true }
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
                .fill(patient.displayColor)
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
