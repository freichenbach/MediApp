import AppIntents
import CoreData
import Foundation

/// A medication as Siri sees it, so "Amoxicillin gegeben" can be resolved to a
/// record without the person having to name the child as well.
///
/// The display title carries the child's name when there is more than one, for
/// the same reason the Today list does: two children can be on the same
/// medicine, and picking the wrong one is the failure this app exists to
/// prevent. With a single child the suffix would only be noise.
struct MedicationEntity: AppEntity, Identifiable {

    let id: UUID
    let name: String
    let patientName: String
    /// Whether the plan holds more than one child at all.
    let namesChild: Bool

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Medication")
    }

    var displayRepresentation: DisplayRepresentation {
        guard namesChild, !patientName.isEmpty else {
            return DisplayRepresentation(title: "\(name)")
        }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(patientName)")
    }

    static var defaultQuery = MedicationQuery()
}

/// Answers Siri's two questions: "which ones are there" and "which one did they
/// mean".
struct MedicationQuery: EntityStringQuery {

    func entities(for identifiers: [MedicationEntity.ID]) async throws -> [MedicationEntity] {
        let wanted = Set(identifiers)
        return await Self.all().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MedicationEntity] {
        await Self.all()
    }

    /// Matching is deliberately forgiving. Speech recognition rarely returns a
    /// drug name letter-perfect, and refusing "Amoxi" when exactly one
    /// medication starts with it helps nobody.
    func entities(matching string: String) async throws -> [MedicationEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return await Self.all() }
        return await Self.all().filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.patientName.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Reads through the same background context as everything else, so a cold
    /// launch by Siri cannot talk to a store that is not open.
    static func all() async -> [MedicationEntity] {
        await PersistenceController.shared.withBackgroundContext { context -> [MedicationEntity] in
            let patients = NSFetchRequest<Patient>(entityName: "Patient")
            let childCount = (try? context.count(for: patients)) ?? 0

            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "isArchived == NO")
            let medications = (try? context.fetch(request)) ?? []

            return medications.compactMap { medication in
                guard let id = medication.id else { return nil }
                return MedicationEntity(
                    id: id,
                    name: medication.displayName,
                    patientName: medication.patient?.displayName ?? "",
                    namesChild: childCount > 1
                )
            }
        } ?? []
    }
}
