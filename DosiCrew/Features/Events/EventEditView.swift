import CoreData
import SwiftUI

struct EventEditView: View {
    @ObservedObject var patient: Patient
    /// `nil` creates a new event; an existing object edits it in place.
    var event: CareEvent?
    var defaultDate: Date

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: EventCategory = .fever
    @State private var timestamp = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var hasMeasurement = false
    @State private var measurementText: String = ""
    @State private var measurementUnit: String = "°C"
    /// The diastolic half. Only ever used by blood pressure — nothing else
    /// takes two numbers.
    @State private var secondaryText: String = ""
    @State private var bloodSugarUnit: BloodSugarUnit = .mgPerDeciliter
    @State private var seizureType: SeizureType = .unknown
    @State private var loaded = false

    private var isNew: Bool { event == nil }

    var body: some View {
        Group {
            if isNew {
                NavigationStack { form }
            } else {
                form
            }
        }
        .onAppear(perform: load)
    }

    private var form: some View {
        Form {
            Section("What happened?") {
                Picker("Category", selection: $category) {
                    ForEach(EventCategory.allCases) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                .onChange(of: category) { _, newValue in
                    if let suggested = newValue.suggestedUnit {
                        measurementUnit = suggested
                    }
                    if newValue.startsWithMeasurement { hasMeasurement = true }
                    // Switching away from blood pressure leaves the second
                    // number behind; keeping it would silently attach a
                    // diastolic value to a temperature.
                    if newValue.measurementShape != .bloodPressure { secondaryText = "" }
                    if newValue == .seizure, let last = AppSettings.lastSeizureType {
                        seizureType = last
                    }
                }

                TextField("Title", text: $title)
                DatePicker("When", selection: $timestamp)
            }

            Section {
                Toggle("Record a value", isOn: $hasMeasurement.animation())
                if hasMeasurement { measurementFields }
            } footer: {
                measurementFooter
            }

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if isNew {
                Section {
                    Text("Logged as \(AppSettings.personName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .dismissibleKeyboard()
        .navigationTitle(isNew ? Text("New event") : Text("Event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    // No rollback needed: a new event is only inserted in
                    // commit(), so there is nothing pending to undo — and
                    // rolling back here would discard unrelated edits.
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndDismiss)
                }
            }
        }
        // An existing event is edited live; leaving the screen commits it.
        .onDisappear { if !isNew { commit() } }
    }

    // MARK: Measurement fields

    @ViewBuilder
    private var measurementFields: some View {
        switch category.measurementShape {
        case .bloodPressure:
            LabeledContent("Systolic") {
                HStack(spacing: 4) {
                    TextField("120", text: $measurementText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text(BloodPressure.unit).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Diastolic") {
                HStack(spacing: 4) {
                    TextField("80", text: $secondaryText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text(BloodPressure.unit).foregroundStyle(.secondary)
                }
            }
            if let warning = bloodPressureWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

        case .bloodSugar:
            HStack {
                TextField("0", text: $measurementText)
                    .keyboardType(.decimalPad)
                Picker("Unit", selection: $bloodSugarUnit) {
                    ForEach(BloodSugarUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            // Shown while typing, not only after saving: the point of the
            // conversion is that the other person in the household reads the
            // other unit, and seeing both makes a wrong unit obvious at once.
            if let converted = convertedBloodSugar {
                Text(converted)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .seizure:
            Picker("Kind of seizure", selection: $seizureType) {
                // Grouped, because thirteen flat entries are hard to scan
                // while something is happening in the room.
                ForEach(SeizureType.Group.allCases) { group in
                    Section(group.label) {
                        ForEach(group.types) { type in
                            Text(type.label).tag(type)
                        }
                    }
                }
            }
            // Its own page rather than a menu: thirteen entries in three
            // groups need room, and this is often being tapped one-handed
            // while watching a child.
            .pickerStyle(.navigationLink)
            LabeledContent("Duration") {
                HStack(spacing: 4) {
                    TextField("0", text: $measurementText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("seconds").foregroundStyle(.secondary)
                }
            }
            if let duration = seizureDurationHint {
                Text(duration)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if exceedsEmergencyPlanThreshold {
                Label(
                    "Longer than five minutes. Most emergency plans say something about that — what applies to this child is in theirs.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

        case .fixedUnit(let unit):
            LabeledContent(fixedUnitLabel(for: unit)) {
                HStack(spacing: 4) {
                    TextField("98", text: $measurementText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text(unit).foregroundStyle(.secondary)
                }
            }
            if impossibleSaturation {
                Label("Above 100 % is not a reading.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

        case .single, .noValue:
            HStack {
                TextField("0", text: $measurementText)
                    .keyboardType(.decimalPad)
                TextField("Unit", text: $measurementUnit)
                    .frame(maxWidth: 80)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private var measurementFooter: some View {
        switch category.measurementShape {
        case .bloodPressure:
            Text("Systolic over diastolic, as the cuff reads them — for example 120 over 80.")
        case .bloodSugar:
            Text("Enter it in the unit you read. The other one is worked out for you, so nobody has to convert in their head.")
        case .fixedUnit:
            Text("A low reading is not a mistake — it is the reason for writing it down. Only a value above 100 % is flagged.")
        case .seizure:
            Text("In seconds — absences are counted in seconds, and a field asking for minutes would put a decimal in the way. The note below is the place for what it looked like.")
        case .single, .noValue:
            Text("For example a temperature of 38.9 °C.")
        }
    }

    /// Only the mistake that is certainly a mistake.
    ///
    /// Values outside the usual range are not flagged: a low pressure in a
    /// small child is exactly what has to reach the doctor, and an app that
    /// argues about it teaches people to type something else. The two numbers
    /// the wrong way round, though, is never a reading.
    private var bloodPressureWarning: LocalizedStringKey? {
        let systolic = DecimalText.value(of: measurementText)
        let diastolic = DecimalText.value(of: secondaryText)
        guard BloodPressure.isReversed(systolic: systolic, diastolic: diastolic) else { return nil }
        return "The lower number is not below the upper one — are they the wrong way round?"
    }

    /// Reads back what was typed, so "135" is visibly two and a quarter minutes.
    private var seizureDurationHint: String? {
        let seconds = DecimalText.value(of: measurementText)
        guard seconds >= 60 else { return nil }
        return "= " + SeizureDuration.description(seconds: seconds)
    }

    private var exceedsEmergencyPlanThreshold: Bool {
        SeizureDuration.exceedsEmergencyPlanThreshold(
            seconds: DecimalText.value(of: measurementText)
        )
    }

    /// Saturation is the only fixed-unit reading so far; "Value" is what any
    /// future one falls back to rather than being mislabelled as a saturation.
    private func fixedUnitLabel(for unit: String) -> LocalizedStringKey {
        unit == OxygenSaturation.unit ? "Saturation" : "Value"
    }

    /// The only bound worth enforcing here. A saturation of 82 is not a typo to
    /// argue with; a saturation of 981 is a finger that slipped.
    private var impossibleSaturation: Bool {
        category.measurementShape == .fixedUnit(OxygenSaturation.unit)
            && OxygenSaturation.isImpossible(percent: DecimalText.value(of: measurementText))
    }

    private var convertedBloodSugar: String? {
        let value = DecimalText.value(of: measurementText)
        guard value > 0 else { return nil }
        let other = bloodSugarUnit.other
        return "= " + other.format(bloodSugarUnit.convert(value, to: other))
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let event {
            category = event.categoryEnum
            timestamp = event.timestamp ?? defaultDate
            title = event.title ?? ""
            note = event.note ?? ""
            hasMeasurement = event.hasMeasurement
            measurementText = DecimalText.text(for: event.measurementValue)
            measurementUnit = event.measurementUnit ?? category.suggestedUnit ?? ""
            secondaryText = event.measurementSecondaryValue > 0
                ? DecimalText.text(for: event.measurementSecondaryValue)
                : ""
            bloodSugarUnit = BloodSugarUnit.from(unitString: event.measurementUnit) ?? .mgPerDeciliter
            seizureType = SeizureType.from(code: event.detailCode) ?? .unknown
        } else {
            category = .fever
            measurementUnit = EventCategory.fever.suggestedUnit ?? ""
            hasMeasurement = true
            timestamp = alignedTimestamp
        }
    }

    /// A new event logged while browsing another day belongs to that day, at
    /// the current time of day.
    private var alignedTimestamp: Date {
        let calendar = Calendar.current
        guard !calendar.isDateInToday(defaultDate) else { return Date() }
        let time = calendar.dateComponents([.hour, .minute], from: Date())
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: 0,
            of: calendar.startOfDay(for: defaultDate)
        ) ?? defaultDate
    }

    private func saveAndDismiss() {
        commit()
        dismiss()
    }

    private func commit() {
        let target = event ?? CareEvent.make(in: context, patient: patient)
        target.categoryEnum = category
        target.timestamp = timestamp
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        target.hasMeasurement = hasMeasurement
        target.measurementValue = hasMeasurement ? DecimalText.value(of: measurementText) : 0

        switch (hasMeasurement, category.measurementShape) {
        case (true, .bloodPressure):
            target.detailCode = nil
            target.measurementSecondaryValue = DecimalText.value(of: secondaryText)
            target.measurementUnit = BloodPressure.unit
        case (_, .seizure):
            // Kept whether or not a duration was caught: nobody times the first
            // seconds of a seizure, and the kind is the half a neurologist
            // would rather have.
            target.detailCode = seizureType.rawValue
            target.measurementSecondaryValue = 0
            target.measurementUnit = SeizureDuration.unit
            AppSettings.lastSeizureType = seizureType

        case (true, .bloodSugar):
            target.detailCode = nil
            // The unit is stored as entered and the value is never converted:
            // a stored conversion would round somebody's reading and hand the
            // doctor a figure no meter ever showed.
            target.measurementSecondaryValue = 0
            target.measurementUnit = bloodSugarUnit.rawValue
        case (true, .fixedUnit(let unit)):
            target.detailCode = nil
            target.measurementSecondaryValue = 0
            target.measurementUnit = unit

        case (true, _):
            target.detailCode = nil
            target.measurementSecondaryValue = 0
            target.measurementUnit = measurementUnit.trimmingCharacters(in: .whitespaces).nilIfEmpty
        case (false, _):
            target.detailCode = nil
            target.measurementSecondaryValue = 0
            target.measurementUnit = nil
        }
        if target.personName == nil { target.personName = AppSettings.personName }

        PersistenceController.shared.save(context)
    }
}

#Preview {
    let controller = PersistenceController.preview
    return EventEditView(
        patient: Patient.fetchOrCreate(in: controller.viewContext),
        event: nil,
        defaultDate: Date()
    )
    .environment(\.managedObjectContext, controller.viewContext)
}
