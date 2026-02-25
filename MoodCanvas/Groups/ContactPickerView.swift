import SwiftUI

/// Shows contacts who are already on MoodCanvas and lets the user select members.
struct ContactPickerView: View {
    @ObservedObject var contactsService: ContactsService
    @Binding var selectedUsers: [User]
    var excludedUserIds: Set<String> = []

    private var displayedUsers: [User] {
        contactsService.matchedUsers.filter { !excludedUserIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if contactsService.isLoading || contactsService.isSearching {
                HStack {
                    ProgressView()
                    Text(contactsService.isSearching ? "Searching…" : "Finding friends on MoodCanvas…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

            } else if displayedUsers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No results yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Search by phone number above to find someone on MoodCanvas.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)

            } else {
                ForEach(displayedUsers) { user in
                    ContactRow(
                        user: user,
                        isSelected: selectedUsers.contains { $0.id == user.id }
                    ) {
                        toggle(user)
                    }
                }
            }
        }
    }

    private func toggle(_ user: User) {
        if let idx = selectedUsers.firstIndex(where: { $0.id == user.id }) {
            selectedUsers.remove(at: idx)
        } else {
            selectedUsers.append(user)
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(user.name.prefix(1)).uppercased())
                            .font(.subheadline.bold())
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(user.phoneNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
