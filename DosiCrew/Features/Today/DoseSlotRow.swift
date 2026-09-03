import SwiftUI

/// One planned dose. Tapping the circle records the dose under the name set on
/// this device; long-pressing offers skip, refuse, and undo.
struct DoseSlotRow: View {
    let slot: DaySlot
    let medication: Medication?
    /// Only true when more than one child is on the plan. Then the name is the
    /// most important word in the row.
    var showsChildName: Bool = false
    var onSetStatus: (DoseStatus) -> Void
    var onClear: () -> Void
    /// Only offered once something is recorded — there is no time to correct
    /// before that.
    var onEditTime: () -> Void = {}

    @State private var now = Date()

    private var isOverdue: Bool { slot.isOverdue(now: now) }

    var body: some View {
        HStack(spacing: 12) {
            marker

            VStack(alignment: .leading, spacing: 3) {
                if showsChildName {
                    Text(slot.medication.patientName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(childTint)
                        .textCase(.uppercase)
                }

                Text(slot.medication.name)
                    .font(.body.weight(.medium))
                    .strikethrough(slot.status == .skipped || slot.status == .refused, color: .secondary)

                HStack(spacing: 6) {
                    Text(slot.scheduledAt, format: .dateTime.hour().minute())
                    if !doseText.isEmpty {
                        Text("·")
                        Text(doseText)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(isOverdue ? Color.orange : Color.secondary)

                if let instructions = slot.medication.instructions?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !instructions.isEmpty {
                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                subtitle
            }

            Spacer(minLength: 8)

            statusButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if slot.isDone {
                Button(role: .destructive, action: onClear) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { onSetStatus(.given) } label: {
                    Label("Given", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !slot.isDone {
                Button { onSetStatus(.skipped) } label: {
                    Label("Skipped", systemImage: "minus")
                }
                .tint(.orange)
                Button { onSetStatus(.refused) } label: {
                    Label("Refused", systemImage: "xmark")
                }
                .tint(.red)
            }
        }
        .contextMenu {
            if slot.isDone {
                Button(action: onEditTime) {
                    Label("Change the time", systemImage: "clock.arrow.circlepath")
                }
                Button(role: .destructive, action: onClear) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            } else {
                ForEach(DoseStatus.allCases) { status in
                    Button { onSetStatus(status) } label: {
                        Label(status.label, systemImage: status.symbolName)
                    }
                }
            }
        }
        .task {
            // Keeps the "overdue" tint honest while the screen stays open.
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(slot.isDone ? .isSelected : [])
    }

    // MARK: Pieces

    private var tint: Color {
        Color(hex: slot.medication.colorHex) ?? MedColor.fallback.color
    }

    /// The child's colour, not the medication's: two children may well take
    /// the same medicine, and the row has to separate them, not merge them.
    private var childTint: Color {
        Color(hex: slot.medication.patientColorHex) ?? ChildColor.fallback.color
    }

    private var marker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.18))
            Image(systemName: slot.medication.form.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
    }

    private var doseText: String {
        medication?.doseDescription ?? formattedDose
    }

    private var formattedDose: String {
        Medication.doseDescription(amount: slot.medication.doseAmount, unit: slot.medication.doseUnit)
    }

    @ViewBuilder
    private var subtitle: some View {
        if slot.isDuplicate {
            Label {
                Text("Given twice: \(duplicateNames)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
        } else if let log = slot.resolvedLog {
            Text(completionText(for: log))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isOverdue {
            Text("Overdue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private var duplicateNames: String {
        slot.givenLogs
            .map { log in
                let name = log.personName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let who = (name?.isEmpty == false ? name! : String(localized: "Someone"))
                guard let takenAt = log.takenAt else { return who }
                return "\(who) (\(TimeText.of(takenAt)))"
            }
            .joined(separator: ", ")
    }

    private func completionText(for log: DoseLogSnapshot) -> String {
        let name = log.personName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = (name?.isEmpty == false ? name! : String(localized: "Someone"))
        let time = TimeText.of(log.takenAt ?? slot.scheduledAt)
        switch log.status {
        case .given: return String(localized: "Given by \(who) at \(time)")
        case .skipped: return String(localized: "Skipped by \(who) at \(time)")
        case .refused: return String(localized: "Refused, logged by \(who) at \(time)")
        }
    }

    private var statusButton: some View {
        Button {
            if slot.isDone { onClear() } else { onSetStatus(.given) }
        } label: {
            Image(systemName: slot.status?.symbolName ?? "circle")
                .font(.title2)
                .foregroundStyle(statusTint)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot.isDone ? Text("Undo") : Text("Mark as given"))
    }

    private var statusTint: Color {
        if slot.isDuplicate { return .red }
        if let status = slot.status { return status.tint }
        return isOverdue ? .orange : .secondary
    }
}

/// A dose that was not part of the plan — given early, given twice on purpose,
/// or logged after the schedule changed.
struct ExtraDoseRow: View {
    let extra: ExtraDose
    var showsChildName: Bool = false
    var onDelete: () -> Void
    var onEditTime: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: extra.medication.form.symbolName)
                .foregroundStyle(Color(hex: extra.medication.colorHex) ?? MedColor.fallback.color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                if showsChildName {
                    Text(extra.medication.patientName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: extra.medication.patientColorHex) ?? ChildColor.fallback.color)
                        .textCase(.uppercase)
                }
                Text(extra.medication.name).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let note = extra.log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onEditTime) {
                Label("Change the time", systemImage: "clock.arrow.circlepath")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var detail: String {
        let name = extra.log.personName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = (name?.isEmpty == false ? name! : String(localized: "Someone"))
        guard let takenAt = extra.log.takenAt else { return who }
        return String(localized: "Given by \(who) at \(TimeText.of(takenAt))")
    }
}
