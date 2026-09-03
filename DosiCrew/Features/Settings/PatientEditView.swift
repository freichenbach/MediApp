import CoreData
import SwiftUI

/// One child: name, date of birth, and who it is shared with.
///
/// Sharing is rooted at the child, not at the app, which is what makes several
/// children useful beyond a longer list: one plan can go to the childminder
/// while another stays between the parents.
struct PatientEditView: View {
    @ObservedObject var patient: Patient

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var colorHex: String = ChildColor.fallback.rawValue
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var loaded = false
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Toggle("Date of birth", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                }

                LabeledContent("Colour") { colorPicker }
            } footer: {
                Text("Shared with everyone you invite. The colour marks this child's doses on the Today screen.")
            }

            Section {
                NavigationLink {
                    SharingView(patient: patient)
                } label: {
                    Label("Share with other people", systemImage: "person.2.fill")
                }
            } footer: {
                Text("Each child is shared separately.")
            }

            Section {
                LabeledContent("Medications", value: "\(patient.activeMedications.count)")
                LabeledContent("Events", value: "\(patient.sortedEvents.count)")
            }

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete child", systemImage: "trash")
                }
            }
        }
        .dismissibleKeyboard()
        .navigationTitle(name.isEmpty ? Text("Edit child") : Text(name))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .confirmationDialog(
            Text("Delete \(name.isEmpty ? patient.displayName : name) and everything recorded for them?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete child", role: .destructive, action: deleteChild)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Medications, schedules, logged doses and events for this child are removed on every shared iPhone. This cannot be undone.")
        }
    }

    /// Deliberately no green, orange or red: those three mean given, skipped
    /// and refused, and red is what the duplicate-dose warning shouts in.
    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(ChildColor.allCases) { option in
                Button { colorHex = option.rawValue } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if colorHex.caseInsensitiveCompare(option.rawValue) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.rawValue))
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = patient.name ?? ""
        colorHex = patient.colorHex ?? ChildColor.fallback.rawValue
        if let birth = patient.birthDate { hasBirthDate = true; birthDate = birth }
    }

    private func save() {
        guard !patient.isDeleted else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        patient.name = trimmed.isEmpty ? nil : trimmed
        patient.colorHex = colorHex
        patient.birthDate = hasBirthDate ? birthDate : nil
        PersistenceController.shared.save(context)
    }

    /// Leaves before deleting: the delete cascades to this child's medications
    /// and events, and this view must not still be reading from them.
    private func deleteChild() {
        let doomed = patient
        dismiss()
        DispatchQueue.main.async {
            context.delete(doomed)
            PersistenceController.shared.save(context)
            Task { await NotificationScheduler.shared.reschedule() }
        }
    }
}

#Preview {
    let controller = PersistenceController.preview
    return NavigationStack {
        PatientEditView(patient: Patient.fetchOrCreate(in: controller.viewContext))
    }
    .environment(\.managedObjectContext, controller.viewContext)
}
