import SwiftUI
import Contacts
import MessageUI

struct CouplePickerView: View {
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @StateObject private var contactsService = ContactsService()
    @AppStorage("isPremium") private var isPremium = false

    let onComplete: () -> Void

    private static let freeGroupLimit = 3

    @State private var selectedContacts: [ContactEntry] = []
    @State private var showContactsPicker = false
    @State private var isCreating = false
    @State private var showMessageCompose = false
    @State private var showTutorial = false
    @State private var contactsDenied = false
    @State private var showPaywall = false

    private var partner: ContactEntry? { selectedContacts.first }
    private var partnerMoodiUsers: [User]        { selectedContacts.compactMap(\.moodiUser) }
    private var partnerNonMoodi: [ContactEntry]  { selectedContacts.filter { !$0.isOnMoodi } }

    var body: some View {
        // ─────────────────────────────────────────────────────────────────
        // Architecture note:
        //   • Plain ZStack (no alignment) — background layers fill screen,
        //     content VStack is centered by its own two flexible Spacers.
        //   • NEVER use ZStack(alignment:.bottom) here: it bottom-anchors
        //     the VStack (whose natural height < screen height), pushing
        //     all content into the lower half regardless of padding values.
        //   • The "next" button is a separate .overlay(alignment:.bottom)
        //     so it never participates in VStack layout at all.
        // ─────────────────────────────────────────────────────────────────
        ZStack {
            // Base colour — fills any sub-pixel gap the image might leave
            Color(hex: "F4AABB").ignoresSafeArea()

            // Background image
            Image("couples_bacgkround3")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Content — two equal flexible Spacers vertically centre the block
            VStack(spacing: 0) {
                Spacer()

                Text("Who's Your Couple?")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "51083A"))

                Spacer().frame(height: 70)

                Text(authService.currentUser?.name ?? "You")
                    .font(Font.custom("EBGaramond-Medium", size: 36))
                    .foregroundStyle(Color(hex: "FF689E"))

                Spacer().frame(height: 14)

                Image("heart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                if let p = partner {
                    Spacer().frame(height: 14)
                    Text(p.name)
                        .font(Font.custom("EBGaramond-Medium", size: 36))
                        .foregroundStyle(Color(hex: "FF689E"))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 50)

                if partner == nil {
                    addCoupleButton
                        .padding(.horizontal, 88)
                        .transition(.opacity)
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: partner?.id)
        }
        // "next" button pinned to the bottom — completely outside the VStack
        .overlay(alignment: .bottom) {
            if partner != nil {
                nextButton
                    .padding(.horizontal, 88)
                    .padding(.bottom, 48)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: partner == nil)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall, onDismiss: {
            if isPremium { createCoupleGroup() }
        }) {
            PaywallView()
        }
        .sheet(isPresented: $showContactsPicker) {
            ContactsPickerSheet(
                contactsService: contactsService,
                selectedContacts: $selectedContacts,
                memberLimit: 1,
                isCouplesTheme: true
            )
        }
        .sheet(isPresented: $showMessageCompose, onDismiss: {
            DispatchQueue.main.async { showTutorial = true }
        }) {
            MessageComposeView(
                recipients: partnerNonMoodi.map(\.phone),
                body: "Hey sweetie! I'm inviting you to join my Moodi as my partner. Join here and stay in sync with me: https://apps.apple.com/app/moodi/id000000000"
            ) {
                showMessageCompose = false
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            WidgetTutorialView(onDismiss: onComplete)
        }
        .task {
            contactsService.authService = authService
        }
        .alert("Contact Access Required", isPresented: $contactsDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow contact access in Settings to find and add your partner.")
        }
    }

    // MARK: - Add couple button

    private func requestContactsThenPick() {
        Task {
            let store = CNContactStore()
            let status = CNContactStore.authorizationStatus(for: .contacts)
            let hasAccess: Bool
            if #available(iOS 18, *) {
                hasAccess = status == .authorized || status == .limited
            } else {
                hasAccess = status == .authorized
            }
            if hasAccess {
                if contactsService.allContactEntries.isEmpty {
                    await contactsService.fetchAllContactsAndMatch()
                }
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
                contactsDenied = true
            }
        }
    }

    private var addCoupleButton: some View {
        Button { requestContactsThenPick() } label: {
            ZStack {
                Text("add couple")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Text("+")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .padding(.trailing, 26)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background {
                Capsule()
                    .fill(Color(hex: "C01A8C"))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(hex: "51083A").opacity(0.4), lineWidth: 5)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Next button (creates group and shows tutorial)

    private var nextButton: some View {
        Button {
            #if !DEBUG
            guard isPremium || groupService.groups.count < Self.freeGroupLimit else {
                showPaywall = true
                return
            }
            #endif
            createCoupleGroup()
        } label: {
            ZStack {
                Text(isCreating ? "creating..." : "next")
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
                    .fill(Color(hex: "C01A8C"))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(hex: "51083A").opacity(0.4), lineWidth: 5)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
    }

    // MARK: - Create couple group

    private func createCoupleGroup() {
        guard let p = partner else { return }
        Task {
            isCreating = true
            let userName = authService.currentUser?.name ?? "Me"
            let groupName = "\(userName) 💞 \(p.name)"
            let groupId = await groupService.createGroup(
                name: groupName,
                type: .couple,
                members: partnerMoodiUsers
            )
            if let groupId, let jwt = KeychainService.load(.supabaseJWT) {
                for entry in partnerNonMoodi {
                    await EdgeFunctionService.inviteByPhone(groupId: groupId, phone: entry.phone, jwt: jwt)
                }
            }
            isCreating = false

            if !partnerNonMoodi.isEmpty && MFMessageComposeViewController.canSendText() {
                showMessageCompose = true
            } else {
                DispatchQueue.main.async { showTutorial = true }
            }
        }
    }
}
