import CoreData
import SwiftUI

/// Makes the report a doctor asks for: what was given, when, and what was not.
///
/// The numbers are shown here before anything is shared. Handing over a health
/// record about a child is not a step to take blind, and seeing "4 not
/// recorded" beforehand is also the moment somebody remembers to fill a gap in.
struct ReportView: View {

    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Patient.createdAt, ascending: true)],
        animation: .default
    )
    private var patients: FetchedResults<Patient>

    @State private var selectedPatientID: UUID?
    @State private var days = 14
    @State private var report: DoseReport.Report?
    @State private var fileURL: URL?
    @State private var building = false
    @State private var failure: String?

    /// Ranges people actually ask for. A week covers a course of antibiotics,
    /// a fortnight the gap between appointments, three months a chronic
    /// prescription being reviewed.
    private static let ranges = [7, 14, 30, 90]

    private var selectedPatient: Patient? {
        patients.first { $0.id == selectedPatientID } ?? patients.first
    }

    var body: some View {
        Form {
            if patients.count > 1 {
                Section {
                    Picker(selection: $selectedPatientID) {
                        ForEach(patients, id: \.objectID) { patient in
                            Text(patient.displayName).tag(patient.id)
                        }
                    } label: {
                        Text("Child")
                    }
                }
            }

            Section {
                Picker("Period", selection: $days) {
                    ForEach(Self.ranges, id: \.self) { value in
                        Text("Last \(value) days").tag(value)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Doses still to come are left out — only what has already fallen due can be missing.")
            }

            if let report {
                summary(report)
            } else if building {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Putting it together…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }

            Section {
                if let fileURL, let report, !report.isEmpty {
                    ShareLink(item: fileURL) {
                        Label("Share the report", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("The PDF holds health data about your child. It goes only where you send it.")
            }
        }
        .navigationTitle("Report for the doctor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedPatientID == nil { selectedPatientID = patients.first?.id }
            rebuild()
        }
        .onChange(of: days) { _, _ in rebuild() }
        .onChange(of: selectedPatientID) { _, _ in rebuild() }
    }

    // MARK: - Preview of what is in it

    @ViewBuilder
    private func summary(_ report: DoseReport.Report) -> some View {
        if report.isEmpty {
            Section {
                Label("Nothing was recorded in this period.", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        } else {
            Section {
                LabeledContent("Doses due", value: "\(report.planned)")
                LabeledContent("Given on time", value: "\(report.given)")
                if report.late > 0 { LabeledContent("Given late", value: "\(report.late)") }
                if report.skipped > 0 { LabeledContent("Deliberately skipped", value: "\(report.skipped)") }
                if report.refused > 0 { LabeledContent("Refused by the child", value: "\(report.refused)") }
                if report.notRecorded > 0 {
                    LabeledContent("Not recorded", value: "\(report.notRecorded)")
                }
                if report.extras > 0 { LabeledContent("Extra doses", value: "\(report.extras)") }
                if report.duplicates > 0 {
                    LabeledContent("Given twice by two people", value: "\(report.duplicates)")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("What the report will say")
            } footer: {
                // Said here as well as in the PDF, because this is where
                // somebody can still do something about it.
                Text("“Not recorded” means nobody ticked the dose off. It does not mean it was missed — the report says so too.")
            }
        }
    }

    // MARK: - Building

    private func rebuild() {
        guard let patient = selectedPatient else {
            report = nil
            fileURL = nil
            return
        }
        let patientID = patient.objectID
        let days = self.days
        building = true
        failure = nil

        Task {
            do {
                let built = try await Self.build(patientID: patientID, days: days, context: context)
                let url = try ReportPDF.write(built)
                await MainActor.run {
                    report = built
                    fileURL = url
                    building = false
                }
            } catch {
                await MainActor.run {
                    report = nil
                    fileURL = nil
                    building = false
                    failure = String(localized: "The report could not be put together. \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reads on the context that owns the objects, then hands plain snapshots
    /// onwards. `DoseReport.build` never touches Core Data, which is what makes
    /// the counting testable.
    private static func build(
        patientID: NSManagedObjectID,
        days: Int,
        context: NSManagedObjectContext
    ) async throws -> DoseReport.Report {
        try await context.perform {
            guard let patient = try context.existingObject(with: patientID) as? Patient else {
                throw ReportError.patientGone
            }

            let calendar = Calendar.current
            let now = Date()
            let to = calendar.startOfDay(for: now)
            guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: to) else {
                throw ReportError.badPeriod
            }

            // Archived medications belong in here. A course of antibiotics that
            // ended last week is exactly what the appointment is about, and
            // leaving it out would silently shorten the record.
            let medications = patient.sortedMedications.map { $0.snapshot() }

            let logs = patient.sortedMedications
                .flatMap(\.allLogs)
                .compactMap { $0.snapshot() }
                .filter { log in
                    let stamp = log.takenAt ?? log.scheduledAt
                    guard let stamp else { return false }
                    return stamp >= from
                }

            let events = patient.sortedEvents
                .filter { ($0.timestamp ?? .distantPast) >= from }
                .compactMap { event -> DoseReport.EventEntry? in
                    guard let id = event.id, let timestamp = event.timestamp else { return nil }
                    return DoseReport.EventEntry(
                        id: id,
                        timestamp: timestamp,
                        category: event.categoryEnum,
                        title: event.displayTitle,
                        measurement: event.measurementDescription,
                        note: event.note,
                        personName: event.personName
                    )
                }

            return DoseReport.build(
                patientName: patient.displayName,
                patientBirthDate: patient.birthDate,
                patientWeightKg: patient.weightKg,
                medications: medications,
                logs: logs,
                events: events,
                from: from,
                to: to,
                now: now,
                calendar: calendar
            )
        }
    }

    private enum ReportError: LocalizedError {
        case patientGone
        case badPeriod

        var errorDescription: String? {
            switch self {
            case .patientGone: return String(localized: "That child is no longer in the plan.")
            case .badPeriod: return String(localized: "The period could not be worked out.")
            }
        }
    }
}
