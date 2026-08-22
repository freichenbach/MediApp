import CoreData
import SwiftUI

/// Tab shell. Also owns the one piece of setup every screen depends on: the
/// patient record that sharing is rooted at.
struct RootView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Patient.createdAt, order: .forward)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @AppStorage(AppSettings.personNameKey) private var personName: String = ""

    @State private var selection: Tab = .today
    @State private var showingNamePrompt = false

    private enum Tab: Hashable {
        case today, medications, events, settings
    }

    var body: some View {
        Group {
            if let patient = patients.first {
                TabView(selection: $selection) {
                    TodayView(patient: patient)
                        .tabItem { Label("Today", systemImage: "checklist") }
                        .tag(Tab.today)

                    MedicationListView(patient: patient)
                        .tabItem { Label("Medications", systemImage: "pills.fill") }
                        .tag(Tab.medications)

                    EventListView(patient: patient)
                        .tabItem { Label("Events", systemImage: "calendar.badge.exclamationmark") }
                        .tag(Tab.events)

                    SettingsView(patient: patient)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(Tab.settings)
                }
                .onAppear { showingNamePrompt = !AppSettings.hasPersonName }
                .sheet(isPresented: $showingNamePrompt) {
                    WhoAreYouView(personName: $personName)
                        .interactiveDismissDisabled()
                }
            } else {
                ProgressView()
                    .task { ensurePatientExists() }
            }
        }
    }

    /// The first launch on a device with no shared plan creates the patient. A
    /// device that later accepts an invitation will simply see a second one and
    /// the user can delete the empty local plan in Settings.
    private func ensurePatientExists() {
        guard patients.isEmpty else { return }
        Patient.makeDefault(in: context)
        PersistenceController.shared.save(context)
    }
}

/// Asked once per device. Without a name, "given by …" on a shared plan would
/// read as an anonymous tick, which defeats the point of sharing.
struct WhoAreYouView: View {
    @Binding var personName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $draft)
                        .textContentType(.givenName)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commit)
                } header: {
                    Text("Who is using this iPhone?")
                } footer: {
                    Text("Shown next to every dose you tick off, so everyone can see who gave what.")
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        personName = trimmed
        dismiss()
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
