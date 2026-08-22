import CloudKit
import CoreData
import SwiftUI
import UIKit

/// Invites other people into the same plan. Sharing is rooted at the patient,
/// so accepting an invitation brings across the medications, their schedules,
/// every logged dose and every event in one go.
struct SharingView: View {
    @ObservedObject var patient: Patient

    @State private var share: CKShare?
    @State private var container: CKContainer?
    @State private var presentingSharingController = false
    @State private var preparing = false
    @State private var errorMessage: String?
    @State private var confirmingStop = false

    private let persistence = PersistenceController.shared

    var body: some View {
        List {
            Section {
                if let share {
                    ForEach(share.participants, id: \.userIdentity.userRecordID) { participant in
                        ParticipantRow(
                            participant: participant,
                            isOwner: participant.userIdentity.userRecordID == share.owner.userIdentity.userRecordID
                        )
                    }
                } else {
                    Label("Not shared yet", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("People")
            } footer: {
                Text("Everyone you invite sees the same plan and can tick off doses. Changes appear on the other iPhones within a few seconds.")
            }

            Section {
                Button {
                    prepareShare()
                } label: {
                    if preparing {
                        HStack { ProgressView(); Text("Preparing…") }
                    } else {
                        Label(share == nil ? "Invite people" : "Manage sharing", systemImage: "person.badge.plus")
                    }
                }
                .disabled(preparing)

                if share != nil {
                    Button(role: .destructive) {
                        confirmingStop = true
                    } label: {
                        Label(isOwner ? "Stop sharing" : "Leave this plan", systemImage: "person.badge.minus")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Label("Everyone needs an iPhone signed in to iCloud.", systemImage: "icloud")
                Label("Read-only participants can see the plan but cannot tick doses off.", systemImage: "eye")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshShare)
        .sheet(isPresented: $presentingSharingController) {
            if let share, let container {
                CloudSharingView(share: share, container: container, title: patient.displayName)
                    .ignoresSafeArea()
                    .onDisappear(perform: refreshShare)
            }
        }
        .confirmationDialog(
            isOwner ? "Stop sharing this plan?" : "Leave this plan?",
            isPresented: $confirmingStop,
            titleVisibility: .visible
        ) {
            Button(isOwner ? "Stop sharing" : "Leave", role: .destructive) { stopSharing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOwner
                 ? "The others lose access immediately. Your own copy of the plan stays on this iPhone."
                 : "The plan disappears from this iPhone. The others keep it.")
        }
    }

    private var isOwner: Bool {
        guard let share, let current = share.currentUserParticipant else { return true }
        return current.userIdentity.userRecordID == share.owner.userIdentity.userRecordID
    }

    // MARK: Actions

    private func refreshShare() {
        share = persistence.existingShare(for: patient)
        if container == nil {
            container = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
        }
    }

    private func prepareShare() {
        errorMessage = nil
        preparing = true
        Task {
            do {
                let (share, container) = try await persistence.share(patient)
                await MainActor.run {
                    self.share = share
                    self.container = container
                    self.preparing = false
                    self.presentingSharingController = true
                }
            } catch {
                await MainActor.run {
                    self.preparing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopSharing() {
        Task {
            do {
                try await persistence.stopSharing(patient)
                await MainActor.run { self.share = nil }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct ParticipantRow: View {
    let participant: CKShare.Participant
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: participant.acceptanceStatus == .accepted ? "person.crop.circle.fill" : "person.crop.circle.dashed")
                .font(.title3)
                .foregroundStyle(participant.acceptanceStatus == .accepted ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var name: String {
        let components = participant.userIdentity.nameComponents
        if let components {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber { return phone }
        return String(localized: "Invited person")
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(isOwner ? String(localized: "Owner") : roleText)
        parts.append(statusText)
        return parts.joined(separator: " · ")
    }

    private var roleText: String {
        switch participant.permission {
        case .readWrite: return String(localized: "Can tick off doses")
        case .readOnly: return String(localized: "Read only")
        default: return String(localized: "Unknown access")
        }
    }

    private var statusText: String {
        switch participant.acceptanceStatus {
        case .accepted: return String(localized: "Accepted")
        case .pending: return String(localized: "Invitation pending")
        case .removed: return String(localized: "Removed")
        default: return String(localized: "Unknown")
        }
    }
}

/// `UICloudSharingController` is still the only UI that can add participants,
/// change their permissions and revoke access.
private struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(title: title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String

        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            PersistenceController.logger.error("Saving the share failed: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
