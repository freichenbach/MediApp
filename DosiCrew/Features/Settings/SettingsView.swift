import CoreData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var patient: Patient

    @Environment(\.managedObjectContext) private var context

    @AppStorage(AppSettings.personNameKey) private var personName: String = ""
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled: Bool = true
    @AppStorage(AppSettings.overdueRemindersKey) private var overdueReminders: Bool = true

    @State private var patientName: String = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $patientName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(savePatient)

                    Toggle("Date of birth", isOn: $hasBirthDate.animation())
                    if hasBirthDate {
                        DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                } header: {
                    Text("Who the plan is for")
                } footer: {
                    Text("Shared with everyone you invite.")
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
                    NavigationLink {
                        SharingView(patient: patient)
                    } label: {
                        Label("Share with other people", systemImage: "person.2.fill")
                    }
                } footer: {
                    if PersistenceController.shared.usesLocalFallback {
                        // People rely on this plan being shared. If it silently
                        // is not, they must hear about it here.
                        Label(
                            "iCloud is not available right now. Everything is saved on this iPhone, but nothing is being shared — the others cannot see what you tick off.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Remind me when a dose is due", isOn: $remindersEnabled)
                    Toggle("Remind me again if it stays open", isOn: $overdueReminders)
                        .disabled(!remindersEnabled)

                    if authorizationStatus == .denied {
                        Label("Notifications are switched off for DosiCrew in iOS Settings.", systemImage: "bell.slash")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Each iPhone reminds on its own. When somebody else ticks a dose off, the pending reminder disappears here too.")
                }

                Section {
                    LabeledContent("Medications", value: "\(patient.activeMedications.count)")
                    LabeledContent("Events", value: "\(patient.sortedEvents.count)")
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
            .onDisappear(perform: savePatient)
            .onChange(of: remindersEnabled) { _, _ in rescheduleReminders() }
            .onChange(of: overdueReminders) { _, _ in rescheduleReminders() }
            .onChange(of: hasBirthDate) { _, _ in savePatient() }
            .onChange(of: birthDate) { _, _ in savePatient() }
        }
    }

    private func load() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run { authorizationStatus = settings.authorizationStatus }
        }
        guard !loaded else { return }
        loaded = true
        patientName = patient.name ?? ""
        if let birth = patient.birthDate { hasBirthDate = true; birthDate = birth }
    }

    private func savePatient() {
        let trimmed = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        patient.name = trimmed.isEmpty ? nil : trimmed
        patient.birthDate = hasBirthDate ? birthDate : nil
        PersistenceController.shared.save(context)
    }

    private func rescheduleReminders() {
        Task { await NotificationScheduler.shared.reschedule() }
    }
}

#Preview {
    let controller = PersistenceController.preview
    return SettingsView(patient: Patient.fetchOrCreate(in: controller.viewContext))
        .environment(\.managedObjectContext, controller.viewContext)
}
