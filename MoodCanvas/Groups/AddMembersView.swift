import SwiftUI
import Contacts

struct AddMembersView: View {
    let group: MoodGroup
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var contactsService = ContactsService()
    @State private var selectedUsers: [User] = []
    @State private var isSending = false
    @State private var searchQuery = ""

    private var excludedUserIds: Set<String> {
        Set(group.members.map { $0.id })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    HStack {
                        TextField("+15551234567", text: $searchQuery)
                            .keyboardType(.phonePad)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await contactsService.searchByPhone(searchQuery) }
                            }
                        if contactsService.isSearching {
                            ProgressView()
                        } else {
                            Button {
                                Task { await contactsService.searchByPhone(searchQuery) }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let error = contactsService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ContactPickerView(
                        contactsService: contactsService,
                        selectedUsers: $selectedUsers,
                        excludedUserIds: excludedUserIds
                    )
                }
            }
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send Invites") {
                        Task {
                            isSending = true
                            await groupService.sendInvitations(selectedUsers, toGroup: group.id)
                            isSending = false
                            dismiss()
                        }
                    }
                    .disabled(selectedUsers.isEmpty || isSending)
                }
            }
            .task {
                contactsService.authService = authService
                let store = CNContactStore()
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .notDetermined {
                    _ = try? await store.requestAccess(for: .contacts)
                }
                await contactsService.fetchAndMatch()
            }
        }
    }
}
