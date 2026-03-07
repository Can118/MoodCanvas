import SwiftUI
import Contacts
import MessageUI

struct GroupDetailView: View {
    let group: MoodGroup

    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var contactsService = ContactsService()
    @State private var newMemberEntries: [ContactEntry] = []
    @State private var pendingNonMoodi: [ContactEntry] = []
    @State private var showContactsPicker = false
    @State private var showMessageCompose = false
    @State private var showSettings       = false
    @State private var showWidgetTutorial = false
    @State private var contactsDenied     = false
    @State private var showLeaveError     = false
    @Environment(\.scenePhase) private var scenePhase

    // Always read fresh data from GroupService
    private var liveGroup: MoodGroup {
        groupService.groups.first { $0.id == group.id } ?? group
    }

    private var currentUserId: String { authService.currentUser?.id ?? "" }

    private var otherMembers: [User] {
        liveGroup.members.filter { $0.id != currentUserId }
    }

    private var addMemberLimit: Int {
        let maxSize = liveGroup.type == .couple ? 2 : 8
        return max(0, maxSize - liveGroup.members.count)
    }

    // MARK: - Theme helpers
    private var isCouple: Bool { liveGroup.type == .couple }
    private var nameColor:   Color { isCouple ? Color(hex: "51083A") : Color(hex: "3C392A") }
    private var memberColor: Color { isCouple ? Color(hex: "A05070") : Color(hex: "837C5A") }
    private var iconFgColor: Color { isCouple ? Color(hex: "51083A").opacity(0.5) : Color(hex: "3C392A").opacity(0.5) }
    private var iconBgColor: Color { isCouple ? Color.white.opacity(0.7)           : Color(hex: "EDE8D8") }
    private var plusBgColor: Color { isCouple ? Color(hex: "A05070")               : Color(hex: "B8721C") }

    var body: some View {
        Group {
            if isCouple {
                coupleBody
            } else {
                regularBody
            }
        }
        .background(NavigationPopGestureEnabler())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showContactsPicker, onDismiss: sendNewMemberInvitations) {
            ContactsPickerSheet(
                contactsService: contactsService,
                selectedContacts: $newMemberEntries,
                memberLimit: addMemberLimit,
                isCouplesTheme: liveGroup.type == .couple
            )
        }
        .sheet(isPresented: $showMessageCompose) {
            MessageComposeView(
                recipients: pendingNonMoodi.map(\.phone),
                body: "Hey! You're invited to my Moodi circle! Join here and share your mood with me: https://apps.apple.com/app/moodi/id000000000"
            ) {
                showMessageCompose = false
            }
        }
        .fullScreenCover(isPresented: $showWidgetTutorial) {
            WidgetTutorialView(onDismiss: { showWidgetTutorial = false })
        }
        .confirmationDialog("", isPresented: $showSettings, titleVisibility: .hidden) {
            Button("Leave the group", role: .destructive) {
                Task {
                    do {
                        try await groupService.leaveGroup(id: liveGroup.id)
                        dismiss()
                    } catch {
                        showLeaveError = true
                    }
                }
            }
            Button("How to add the widget") { showWidgetTutorial = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Unable to leave group", isPresented: $showLeaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong. Please try again.")
        }
        .task {
            contactsService.authService = authService
            await contactsService.fetchAllContactsAndMatch()
        }
        .alert("Contact Access Required", isPresented: $contactsDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow contact access in Settings to add members.")
        }
        // Refresh when a silent push arrives while this screen is already on top.
        // HomeView has the same handler but is behind the navigation stack, so
        // GroupDetailView needs its own to guarantee the live data is applied here.
        .onReceive(NotificationCenter.default.publisher(for: .moodUpdateReceived)) { _ in
            Task { await groupService.fetchGroups() }
        }
        // Poll every 8 s while the screen is active.
        // .task(id: scenePhase) is cancelled and restarted whenever scenePhase
        // changes, so it pauses in the background and resumes on foreground.
        // Unlike Timer.publish (which resets on every @Published change / body
        // re-render), a task-based loop is never disturbed by SwiftUI re-renders.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                await groupService.fetchGroups()
            }
        }
    }

    // MARK: - Couple layout

    private var coupleBody: some View {
        ZStack {
            VStack(spacing: 0) {

                // Top bar — back (left) + settings (right)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "51083A").opacity(0.5))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if addMemberLimit > 0 {
                        Button { requestContactsThenAddMember() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color(hex: "C01A8C")))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: "51083A").opacity(0.5))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Group name
                Text(liveGroup.name)
                    .font(Font.custom("EBGaramond-Bold", size: 30))
                    .foregroundStyle(Color(hex: "51083A"))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 48)
                    .padding(.bottom, 26)

                // 4 mood selector buttons (top position for couple view)
                HStack(spacing: 8) {
                    ForEach(Mood.cardMoods) { mood in
                        Button {
                            Task { await groupService.updateMood(mood, for: currentUserId, in: liveGroup.id) }
                        } label: {
                            Image(mood.displayImageName)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .background {
                                    Image("pink_button_container")
                                        .resizable()
                                        .scaledToFill()
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)

                // Member names "Emily 💜 John"
                Text(liveGroup.members.map(\.name).joined(separator: " 💜 "))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "A05070"))
                    .padding(.bottom, 14)

                // Two mood icons side by side with separator
                HStack(spacing: 0) {
                    Spacer()
                    let myMood = liveGroup.currentMoods[currentUserId] ?? .happy
                    Image(myMood.displayImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .id(myMood)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    Spacer()
                    Capsule()
                        .fill(Color(hex: "E9A0B8").opacity(0.6))
                        .frame(width: 1.5, height: 70)
                    Spacer()
                    if let partner = otherMembers.first {
                        let partnerMood = liveGroup.currentMoods[partner.id] ?? .happy
                        Image(partnerMood.displayImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                    } else {
                        Circle()
                            .fill(Color(hex: "E9A0B8").opacity(0.25))
                            .frame(width: 100, height: 100)
                    }
                    Spacer()
                }
                .padding(.bottom, 32)

                // Heart count pill — last digit rolls like a slot-machine wheel on increment
                let hearts = groupService.heartCounts[liveGroup.id] ?? liveGroup.heartCount
                Text(hearts.formatted())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "51083A"))
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hearts)
                    .offset(x: 12)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background {
                        Image("heart_counter_container")
                            .resizable()
                            .scaledToFill()
                    }

                Spacer()

                // Send heart button
                Button {
                    Task { await groupService.sendHeart(groupId: liveGroup.id) }
                } label: {
                    Text("🤍")
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(
                            Capsule()
                                .fill(Color(hex: "C01A8C"))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color(hex: "8B1265").opacity(0.6), lineWidth: 5)
                                }
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "F2B8CC").ignoresSafeArea())
    }

    // MARK: - Regular (BFF / family) layout

    private var regularBody: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 72)

                    Text(liveGroup.name)
                        .font(Font.custom("EBGaramond-Bold", size: 34))
                        .foregroundStyle(nameColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    let myMood = liveGroup.currentMoods[currentUserId] ?? .happy
                    Image(myMood.displayImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .frame(maxWidth: .infinity)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: myMood)
                        .padding(.bottom, 20)

                    Divider()
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)

                    ForEach(otherMembers) { member in
                        memberRow(member)
                    }

                    Color.clear.frame(height: 170)
                }
            }

            moodSelector
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconFgColor)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(iconBgColor))
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 16)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if addMemberLimit > 0 {
                    Button { requestContactsThenAddMember() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(plusBgColor))
                    }
                    .buttonStyle(.plain)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconFgColor)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(iconBgColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Bottom mood selector (regular view only)

    private var moodSelector: some View {
        HStack(spacing: 10) {
            ForEach(Mood.cardMoods) { mood in
                Button {
                    Task {
                        await groupService.updateMood(mood, for: currentUserId, in: liveGroup.id)
                    }
                } label: {
                    Image(mood.displayImageName)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background {
                            Image("moodbutton_container_detailsscreen")
                                .resizable()
                                .scaledToFill()
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 44)
        .padding(.top, 12)
        .background {
            VStack(spacing: 0) {
                // Soft fade so scroll content disappears before the buttons
                LinearGradient(
                    colors: [Color(hex: "FFFCED").opacity(0), Color(hex: "FFFCED")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 44)
                // Solid block covers the button area and fills through the home indicator
                Color(hex: "FFFCED")
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Contact access gating for add-member flow

    private func requestContactsThenAddMember() {
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

    // MARK: - Send invitations after picker dismisses

    private func sendNewMemberInvitations() {
        guard !newMemberEntries.isEmpty else { return }
        let moodiUsers = newMemberEntries.compactMap(\.moodiUser)
        let nonMoodi   = newMemberEntries.filter { !$0.isOnMoodi }
        newMemberEntries = []
        Task {
            if !moodiUsers.isEmpty {
                await groupService.sendInvitations(moodiUsers, toGroup: liveGroup.id)
            }
            if let jwt = KeychainService.load(.supabaseJWT) {
                for entry in nonMoodi {
                    await EdgeFunctionService.inviteByPhone(groupId: liveGroup.id, phone: entry.phone, jwt: jwt)
                }
            }
            if !nonMoodi.isEmpty && MFMessageComposeViewController.canSendText() {
                pendingNonMoodi = nonMoodi
                showMessageCompose = true
            }
        }
    }

    // MARK: - Member row (regular view only)

    private func memberRow(_ member: User) -> some View {
        let mood = liveGroup.currentMoods[member.id] ?? .happy
        return HStack(spacing: 14) {
            Image(mood.displayImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)

            HStack(spacing: 5) {
                Text(member.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(nameColor)

                Text("•")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(memberColor)

                Text(formattedTime(liveGroup.moodTimestamps[member.id]))
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(memberColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Time helper

    private func formattedTime(_ isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else { return "" }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let date = f1.date(from: isoString) ?? f2.date(from: isoString)
        guard let date else { return "" }
        let display = DateFormatter()
        display.dateFormat = "h:mm a"
        return display.string(from: date)
    }
}

// MARK: - Native swipe-back gesture re-enabler

private struct NavigationPopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Enabler { Enabler() }
    func updateUIViewController(_ uiViewController: Enabler, context: Context) {}

    final class Enabler: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: .preview)
            .environmentObject(GroupService())
            .environmentObject(AuthService())
    }
}
