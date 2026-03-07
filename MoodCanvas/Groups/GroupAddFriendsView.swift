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
    @State private var contactsDenied = false

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
                    ZStack {
                        Text(groupName)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "3C392A"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        HStack {
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: "3C392A").opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "FFFBE4"))
                            .shadow(color: Color(hex: "B8920A").opacity(0.22), radius: 7, x: 1, y: 5)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 48)

                // Members title
                Text("Members")
                    .font(Font.custom("EBGaramond-Medium", size: 28))
                    .foregroundStyle(Color(hex: "3C392A"))
                    .padding(.top, 52)

                ScrollView {
                    VStack(spacing: 10) {
                        memberPill(name: "You", bold: true)

                        Divider()
                            .padding(.horizontal, 100)
                            .padding(.vertical, 2)

                        ForEach(selectedContacts) { entry in
                            memberPill(name: entry.name, bold: false) {
                                selectedContacts.removeAll { $0.id == entry.id }
                            }
                        }

                        if contactsDenied {
                            contactsDeniedView
                        } else if selectedContacts.count < memberLimit {
                            Button { showContactsPicker = true } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(Color(hex: "B8721C"))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
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
                .opacity(selectedContacts.isEmpty ? 0.45 : 1)
                .padding(.horizontal, 48)
                .padding(.bottom, 28)
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
        .sheet(isPresented: $showMessageCompose, onDismiss: {
            // Dispatch async so SwiftUI fully settles the sheet dismissal animation
            // before we present the tutorial. Without this, SwiftUI can receive both
            // "sheet gone" and "fullScreenCover appear" in the same layout pass and
            // silently drop the cover presentation.
            DispatchQueue.main.async { showTutorial = true }
        }) {
            MessageComposeView(
                recipients: selectedNonMoodi.map(\.phone),
                body: "Hey! You're invited to my Moodi circle! Join here: https://apps.apple.com/app/moodi/id000000000"
            ) {
                showMessageCompose = false
            }
        }
        // fullScreenCover is independent of NavigationStack state — far more reliable
        // than navigationDestination for post-flow tutorial presentation.
        .fullScreenCover(isPresented: $showTutorial) {
            WidgetTutorialView(onDismiss: onComplete)
        }
        .task {
            contactsService.authService = authService
            let store = CNContactStore()
            let status = CNContactStore.authorizationStatus(for: .contacts)
            let hasAccess: Bool
            if #available(iOS 18, *) {
                hasAccess = status == .authorized || status == .limited
            } else {
                hasAccess = status == .authorized
            }
            if hasAccess {
                await contactsService.fetchAllContactsAndMatch()
                showContactsPicker = true
            } else if status == .notDetermined {
                let granted = (try? await store.requestAccess(for: .contacts)) ?? false
                if granted {
                    await contactsService.fetchAllContactsAndMatch()
                    showContactsPicker = true
                } else {
                    contactsDenied = true
                }
            } else {
                // .denied or .restricted — block the flow
                contactsDenied = true
            }
        }
    }

    // MARK: - Member pill

    private func memberPill(name: String, bold: Bool, onDelete: (() -> Void)? = nil) -> some View {
        ZStack {
            Text(name)
                .font(.system(size: 17, weight: bold ? .bold : .semibold, design: .rounded))
                .foregroundStyle(Color(hex: "3C392A"))
                .frame(maxWidth: .infinity)

            if let onDelete {
                HStack {
                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "3C392A").opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "FEF9DF"))
                .shadow(color: Color(hex: "B8920A").opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 52)
    }

    // MARK: - Contacts denied view

    private var contactsDeniedView: some View {
        VStack(spacing: 10) {
            Text("Contact access is required to add friends.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color(hex: "3C392A").opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: "B8721C"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    // MARK: - Create group

    private func createGroup() {
        Task {
            isCreating = true
            let groupId = await groupService.createGroup(
                name: groupName,
                type: selectedType,
                members: selectedMoodiUsers
            )

            // Register deferred phone invitations for non-Moodi contacts so they
            // automatically see the invite after downloading the app.
            if let groupId, let jwt = KeychainService.load(.supabaseJWT) {
                for entry in selectedNonMoodi {
                    await EdgeFunctionService.inviteByPhone(groupId: groupId, phone: entry.phone, jwt: jwt)
                }
            }

            isCreating = false

            if !selectedNonMoodi.isEmpty && MFMessageComposeViewController.canSendText() {
                showMessageCompose = true
            } else {
                DispatchQueue.main.async { showTutorial = true }
            }
        }
    }

    // MARK: - Done button label

    private var doneButtonLabel: some View {
        ZStack {
            Text(isCreating ? "creating..." : "done!")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .black))
                    .padding(.trailing, 26)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            Capsule()
                .fill(Color(hex: "B8721C"))
                .overlay {
                    Capsule()
                        .strokeBorder(Color(hex: "3C392A").opacity(0.4), lineWidth: 5)
                }
        }
    }
}

// MARK: - Contacts picker sheet

struct ContactsPickerSheet: View {
    @ObservedObject var contactsService: ContactsService
    @Binding var selectedContacts: [ContactEntry]
    let memberLimit: Int
    var isCouplesTheme: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var atLimit: Bool { selectedContacts.count >= memberLimit }

    // Theme colours — swapped to pink when isCouplesTheme is true
    private var bgColor:           Color { isCouplesTheme ? Color(hex: "FFEBF5") : Color(hex: "FFFCED") }
    private var accentColor:       Color { isCouplesTheme ? Color(hex: "C01A8C") : Color(hex: "665938") }
    private var circleSelected:    Color { isCouplesTheme ? Color(hex: "C01A8C") : Color(hex: "665938") }
    private var circleMoodi:       Color { isCouplesTheme ? Color(hex: "F5A8D4") : Color(hex: "E4BF89") }
    private var circleDefault:     Color { isCouplesTheme ? Color(hex: "F5D0E8") : Color(hex: "EDE8D8") }
    private var nameColor:         Color { isCouplesTheme ? Color(hex: "51083A") : Color(hex: "3C392A") }
    private var subtitleColor:     Color { isCouplesTheme ? Color(hex: "C01A8C").opacity(0.6) : Color(hex: "837C5A").opacity(0.7) }
    private var searchBarBgColor:  Color { isCouplesTheme ? Color(hex: "F5D0E8") : Color(hex: "EDE8D8") }

    private var filteredEntries: [ContactEntry] {
        guard !searchText.isEmpty else { return contactsService.allContactEntries }
        return contactsService.allContactEntries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            // Using a manual search field instead of .searchable — because .searchable
            // takes over the navigation bar when focused, hiding the Done button.
            // With an inline TextField the nav bar (and Done button) always stays visible.
            VStack(spacing: 0) {
                // Inline search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(accentColor.opacity(0.5))
                    TextField("Search contacts", text: $searchText)
                        .font(.system(.body, design: .rounded))
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(searchBarBgColor))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Subtle indicator while Phase 2 (server match) is running in the background
                if contactsService.isMatching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(accentColor)
                        Text("finding Moodi users...")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(accentColor.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }

                ZStack {
                    bgColor.ignoresSafeArea()

                    if contactsService.isLoading {
                        VStack(spacing: 16) {
                            ProgressView().tint(accentColor)
                            Text("loading contacts...")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(accentColor)
                        }
                    } else if contactsService.allContactEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image("sad_mood").resizable().scaledToFit().frame(width: 90)
                            Text("no contacts found")
                                .font(.system(.callout, design: .rounded).weight(.medium))
                                .foregroundStyle(accentColor)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(filteredEntries) { entry in
                                    contactRow(entry)
                                    Divider().padding(.leading, 78)
                                }
                                if filteredEntries.isEmpty {
                                    Text("no results")
                                        .font(.system(.callout, design: .rounded).weight(.medium))
                                        .foregroundStyle(accentColor)
                                        .padding(.top, 40)
                                }
                            }
                        }
                    }
                }
            }
            .background(bgColor.ignoresSafeArea())
            .navigationTitle(
                selectedContacts.isEmpty ? "Add Friends" : "\(selectedContacts.count)/\(memberLimit) selected"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .tint(accentColor)
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
                    .fill(isSelected ? circleSelected : (entry.isOnMoodi ? circleMoodi : circleDefault))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(entry.name.prefix(1)).uppercased())
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : accentColor)
                    }
                    .animation(.easeInOut(duration: 0.12), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isDisabled ? nameColor.opacity(0.3) : nameColor)
                    if entry.isOnMoodi {
                        Text("on Moodi")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(circleMoodi))
                    } else {
                        Text("invite via iMessage")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(subtitleColor)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentColor)
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
