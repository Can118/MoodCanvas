import SwiftUI
import Contacts
import MessageUI

struct GroupAddFriendsView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService

    let selectedType: GroupType
    let onComplete: () -> Void

    @State private var groupName: String
    @StateObject private var contactsService = ContactsService()
    @State private var selectedContacts: [ContactEntry] = []
    @State private var showContactsPicker = false
    @State private var showMessageCompose = false
    @State private var showTutorial = false
    @State private var showRenameSheet = false
    @State private var isCreating = false

    init(selectedType: GroupType, groupName: String, onComplete: @escaping () -> Void) {
        self.selectedType = selectedType
        self.onComplete = onComplete
        _groupName = State<String>(initialValue: groupName)
    }

    private var memberLimit: Int { selectedType == .couple ? 1 : 8 }
    private var selectedMoodiUsers: [User]       { selectedContacts.compactMap(\.moodiUser) }
    private var selectedNonMoodi: [ContactEntry] { selectedContacts.filter { !$0.isOnMoodi } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            VStack(spacing: 0) {
                // Group name card — tap to rename
                Button { showRenameSheet = true } label: {
                    HStack {
                        Text(groupName)
                            .font(Font.custom("EBGaramond-Bold", size: 22))
                            .foregroundStyle(Color(hex: "3C392A"))
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "3C392A").opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background { RoundedRectangle(cornerRadius: 18).fill(Color(hex: "FFF8D4")) }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Members title
                Text("Members")
                    .font(Font.custom("EBGaramond-SemiBold", size: 28))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .padding(.top, 28)

                ScrollView {
                    VStack(spacing: 10) {
                        memberPill(name: "You", bold: true)

                        Divider()
                            .padding(.horizontal, 60)
                            .padding(.vertical, 2)

                        ForEach(selectedContacts) { entry in
                            memberPill(name: entry.name, bold: false)
                        }

                        if selectedContacts.count < memberLimit {
                            Button { showContactsPicker = true } label: {
                                Text("add friend")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Capsule().fill(Color(hex: "B8721C")))
                                    .padding(.horizontal, 36)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }
            }

            // Fixed done button
            Button { createGroup() } label: { doneButtonLabel }
                .buttonStyle(.plain)
                .disabled(isCreating || selectedContacts.isEmpty)
                .opacity(selectedContacts.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 36)
                .padding(.bottom, 48)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showRenameSheet) {
            EditGroupNameSheet(initialName: groupName) { newName in
                groupName = newName
            }
        }
        .sheet(isPresented: $showContactsPicker) {
            ContactsPickerSheet(
                contactsService: contactsService,
                selectedContacts: $selectedContacts,
                memberLimit: memberLimit
            )
        }
        .sheet(isPresented: $showMessageCompose, onDismiss: { showTutorial = true }) {
            MessageComposeView(
                recipients: selectedNonMoodi.map(\.phone),
                body: "Hey! I'm using Moodi to share moods with my close people — join me! 💜\nDownload here: https://apps.apple.com/app/moodi/id000000000"
            ) {
                showMessageCompose = false
            }
        }
        .navigationDestination(isPresented: $showTutorial) {
            WidgetTutorialView(onDismiss: onComplete)
        }
        .task {
            contactsService.authService = authService
            let store = CNContactStore()
            let status = CNContactStore.authorizationStatus(for: .contacts)
            try? await Task.sleep(for: .seconds(1))

            if status == .authorized {
                await contactsService.fetchAllContactsAndMatch()
                showContactsPicker = true
            } else if status == .notDetermined {
                let granted = (try? await store.requestAccess(for: .contacts)) ?? false
                if granted {
                    await contactsService.fetchAllContactsAndMatch()
                    showContactsPicker = true
                }
            } else {
                // .denied, .restricted, or .limited (iOS 18+)
                await contactsService.fetchAllContactsAndMatch()
                showContactsPicker = true
            }
        }
    }

    // MARK: - Member pill

    private func memberPill(name: String, bold: Bool) -> some View {
        Text(name)
            .font(bold
                  ? Font.custom("EBGaramond-Bold", size: 20)
                  : Font.custom("EBGaramond-SemiBold", size: 20))
            .foregroundStyle(Color(hex: "3C392A"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "FFF8D4")))
            .padding(.horizontal, 36)
    }

    // MARK: - Create group

    private func createGroup() {
        Task {
            isCreating = true
            await groupService.createGroup(
                name: groupName,
                type: selectedType,
                members: selectedMoodiUsers
            )
            isCreating = false

            if !selectedNonMoodi.isEmpty && MFMessageComposeViewController.canSendText() {
                showMessageCompose = true
            } else {
                showTutorial = true
            }
        }
    }

    // MARK: - Done button label

    private var doneButtonLabel: some View {
        Text(isCreating ? "creating..." : "done!")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                Capsule().fill(Color(hex: "665938"))
                    .overlay { Capsule().strokeBorder(Color(hex: "3C392A").opacity(0.3), lineWidth: 5) }
            }
    }
}

// MARK: - Contacts picker sheet

struct ContactsPickerSheet: View {
    @ObservedObject var contactsService: ContactsService
    @Binding var selectedContacts: [ContactEntry]
    let memberLimit: Int
    @Environment(\.dismiss) private var dismiss

    private var atLimit: Bool { selectedContacts.count >= memberLimit }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "FFFCED").ignoresSafeArea()

                if contactsService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("loading contacts...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color(hex: "837C5A"))
                    }
                } else if contactsService.allContactEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image("sad_mood").resizable().scaledToFit().frame(width: 90)
                        Text("no contacts found")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundStyle(Color(hex: "837C5A"))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(contactsService.allContactEntries) { entry in
                                contactRow(entry)
                                Divider().padding(.leading, 78)
                            }
                        }
                    }
                }
            }
            .navigationTitle(
                selectedContacts.isEmpty ? "Add Friends" : "\(selectedContacts.count)/\(memberLimit) selected"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(Color(hex: "665938"))
                }
            }
        }
    }

    @ViewBuilder
    private func contactRow(_ entry: ContactEntry) -> some View {
        let isSelected  = selectedContacts.contains { $0.id == entry.id }
        let isDisabled  = atLimit && !isSelected

        Button {
            if isSelected {
                selectedContacts.removeAll { $0.id == entry.id }
            } else if !isDisabled {
                selectedContacts.append(entry)
            }
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(isSelected ? Color(hex: "665938") : (entry.isOnMoodi ? Color(hex: "E4BF89") : Color(hex: "EDE8D8")))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(entry.name.prefix(1)).uppercased())
                            .font(Font.custom("EBGaramond-Bold", size: 19))
                            .foregroundStyle(isSelected ? .white : Color(hex: "665938"))
                    }
                    .animation(.easeInOut(duration: 0.12), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(Font.custom("EBGaramond-SemiBold", size: 18))
                        .foregroundStyle(isDisabled ? Color(hex: "3C392A").opacity(0.3) : Color(hex: "3C392A"))
                    if entry.isOnMoodi {
                        Text("on Moodi")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hex: "665938"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "E4BF89")))
                    } else {
                        Text("invite via iMessage")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color(hex: "837C5A").opacity(0.7))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "665938"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
