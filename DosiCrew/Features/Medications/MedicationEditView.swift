import CoreData
import SwiftUI

struct MedicationEditView: View {
    @ObservedObject var medication: Medication

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var form: MedicationForm = .tablet
    @State private var doseAmount: Double = 0
    @State private var doseUnit: String = ""
    @State private var strengthText: String = ""
    @State private var instructions: String = ""
    @State private var colorHex: String = MedColor.fallback.rawValue

    @State private var hasStartDate = false
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()

    @State private var loaded = false

    private var isNew: Bool { medication.isInserted }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Form", selection: $form) {
                        ForEach(MedicationForm.allCases) { form in
                            Label(form.label, systemImage: form.symbolName).tag(form)
                        }
                    }
                    .onChange(of: form) { _, newValue in
                        if doseUnit.trimmingCharacters(in: .whitespaces).isEmpty {
                            doseUnit = newValue.defaultUnit
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Amount per dose")
                        Spacer()
                        TextField("0", value: $doseAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                    }

                    Picker("Unit", selection: $doseUnit) {
                        ForEach(unitOptions, id: \.self) { unit in
                            Text(DoseUnit.label(for: unit)).tag(unit)
                        }
                    }

                    TextField("Strength, e.g. 250 mg / 5 ml", text: $strengthText)
                } header: {
                    Text("Dose")
                } footer: {
                    Text("The amount handed over at one scheduled time.")
                }

                Section("Notes for whoever gives it") {
                    TextField("e.g. with a meal", text: $instructions, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Colour") {
                    colorPicker
                }

                ScheduleEditor(medication: medication)

                Section {
                    Toggle("Starts on", isOn: $hasStartDate.animation())
                    if hasStartDate {
                        DatePicker("First day", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("Ends on", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("Last day", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Treatment period")
                } footer: {
                    Text("Leave both off for an ongoing medication. Both days are included.")
                }

                if !isNew {
                    Section {
                        Toggle("Archived", isOn: Binding(
                            get: { medication.isArchived },
                            set: { medication.isArchived = $0 }
                        ))
                    } footer: {
                        Text("An archived medication disappears from the Today screen but keeps its history.")
                    }
                }
            }
            .navigationTitle(isNew ? Text("New medication") : Text("Edit medication"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .interactiveDismissDisabled()
    }

    private var unitOptions: [String] {
        var options = DoseUnit.suggestions
        let current = doseUnit.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !options.contains(current) { options.insert(current, at: 0) }
        return options
    }

    private var colorPicker: some View {
        HStack(spacing: 12) {
            ForEach(MedColor.allCases) { option in
                Button {
                    colorHex = option.rawValue
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if colorHex == option.rawValue {
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
        .frame(maxWidth: .infinity)
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = medication.name ?? ""
        form = medication.formEnum
        doseAmount = medication.doseAmount
        doseUnit = medication.doseUnit ?? medication.formEnum.defaultUnit
        strengthText = medication.strengthText ?? ""
        instructions = medication.instructions ?? ""
        colorHex = medication.colorHex ?? MedColor.fallback.rawValue
        if let start = medication.startDate { hasStartDate = true; startDate = start }
        if let end = medication.endDate { hasEndDate = true; endDate = end }
    }

    /// Discards everything unsaved in the view context, which also removes a
    /// medication that was inserted just to open this editor.
    private func cancel() {
        context.rollback()
        dismiss()
    }

    private func save() {
        medication.name = trimmedName
        medication.formEnum = form
        medication.doseAmount = max(0, doseAmount)
        medication.doseUnit = doseUnit.trimmingCharacters(in: .whitespaces)
        medication.strengthText = strengthText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        medication.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        medication.colorHex = colorHex
        medication.startDate = hasStartDate ? Calendar.current.startOfDay(for: startDate) : nil
        medication.endDate = hasEndDate ? Calendar.current.startOfDay(for: endDate) : nil

        PersistenceController.shared.save(context)
        Task { await NotificationScheduler.shared.reschedule() }
        dismiss()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    let controller = PersistenceController.preview
    let patient = Patient.fetchOrCreate(in: controller.viewContext)
    return MedicationEditView(medication: patient.activeMedications.first ?? Medication.make(in: controller.viewContext, patient: patient))
        .environment(\.managedObjectContext, controller.viewContext)
}
