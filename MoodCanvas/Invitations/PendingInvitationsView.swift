import SwiftUI

struct PendingInvitationsView: View {
    @EnvironmentObject var groupService: GroupService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(groupService.pendingInvitations) { invitation in
                InvitationRow(invitation: invitation)
            }
            .navigationTitle("Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: groupService.pendingInvitations) { _, invitations in
            if invitations.isEmpty { dismiss() }
        }
    }
}

// MARK: - Invitation Row

private struct InvitationRow: View {
    let invitation: GroupInvitationDetail
    @EnvironmentObject var groupService: GroupService

    var body: some View {
        HStack(spacing: 12) {
            // Group icon
            RoundedRectangle(cornerRadius: 10)
                .fill(invitation.groupType.backgroundGradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(invitation.groupType.icon)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.groupName)
                    .font(.subheadline.bold())
                Text("invited by \(invitation.inviterName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await groupService.respondToInvitation(invitation.id, accept: false) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await groupService.respondToInvitation(invitation.id, accept: true) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
