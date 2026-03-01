import SwiftUI

struct CreateGroupView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @StateObject private var contactsService = ContactsService()

    @State private var groupName = ""
    @State private var selectedType: GroupType
    @State private var selectedMembers: [User] = []
    @State private var isCreating = false
    @State private var searchQuery = ""

    init(initialType: GroupType = .bff, initialName: String = "") {
        _selectedType = State(initialValue: initialType)
        _groupName    = State(initialValue: initialName)
    }

    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Couple groups can only have 1 other member
    private var memberLimit: Int {
        selectedType == .couple ? 1 : 20
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Group Details
                Section("Group Details") {
                    TextField("Group name", text: $groupName)

                    HStack {
                        ForEach(GroupType.allCases, id: \.self) { type in
                            Button {
                                selectedType = type
                                // Remove extra members if switching to couple
                                if type == .couple && selectedMembers.count > 1 {
                                    selectedMembers = Array(selectedMembers.prefix(1))
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(type.backgroundGradient)
                                        .frame(height: 56)
                                        .overlay { Text(type.icon).font(.title2) }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(
                                                    selectedType == type ? Color.primary : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }
                                    Text(type.displayName)
                                        .font(.caption.bold())
                                        .foregroundStyle(selectedType == type ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Members — search
                Section {
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
                } header: {
                    HStack {
                        Text("Add Members")
                        Spacer()
                        if !selectedMembers.isEmpty {
                            Text("\(selectedMembers.count)\(selectedType == .couple ? "/1" : "") selected")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // MARK: Members — results
                Section {
                    ContactPickerView(
                        contactsService: contactsService,
                        selectedUsers: $selectedMembers
                    )
                } footer: {
                    if selectedType == .couple {
                        Text("Couple groups are limited to 2 people.")
                    }
                }

            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createGroup()
                    }
                    .bold()
                    .disabled(!isValid || isCreating)
                }
            }
            .task {
                contactsService.authService = authService
                await contactsService.fetchAndMatch()
            }
        }
    }

    // MARK: - Create

    private func createGroup() {
        Task {
            isCreating = true
            await groupService.createGroup(
                name: groupName,
                type: selectedType,
                members: selectedMembers
            )
            isCreating = false
            dismiss()
        }
    }
}

#Preview {
    CreateGroupView()
        .environmentObject(GroupService())
}
