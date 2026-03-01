import SwiftUI
import Contacts

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var groupService = GroupService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showCreateGroup = false
    @State private var showPaywall     = false
    @State private var showSettings    = false
    @State private var selectedGroup: MoodGroup?
    @State private var renamingGroup: MoodGroup?

    private static let freeGroupLimit = 3

    var body: some View {
        NavigationStack {
            Group {
                if groupService.groups.isEmpty {
                    EmptyHomeView(onCreateGroup: requestContactsThenCreate)
                } else {
                    groupList
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                GroupTypePickerView()
                    .environmentObject(groupService)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $renamingGroup) { group in
                EditGroupNameSheet(initialName: group.name) { newName in
                    Task { await groupService.renameGroup(id: group.id, newName: newName) }
                }
            }
            .task {
                await groupService.fetchGroups()
                await groupService.fetchPendingInvitations()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await authService.refreshJWTIfNeeded()
                        await groupService.processPendingWidgetMoods(currentUserId: authService.currentUser?.id)
                        await groupService.fetchGroups()
                        await groupService.fetchPendingInvitations()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .moodUpdateReceived)) { _ in
                Task { await groupService.fetchGroups() }
            }
        }
    }

    // MARK: - Group list (full custom layout)

    private var groupList: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Invitation cards — shown above group cards
                    ForEach(groupService.pendingInvitations) { invitation in
                        InvitationCardView(
                            invitation: invitation,
                            onDecline: {
                                Task { await groupService.respondToInvitation(invitation.id, accept: false) }
                            },
                            onAccept: {
                                Task { await groupService.respondToInvitation(invitation.id, accept: true) }
                            }
                        )
                    }

                    // Group cards
                    ForEach(groupService.groups) { group in
                        GroupCardView(
                            group: group,
                            currentUserId: authService.currentUser?.id ?? "",
                            onMoodTap: { mood in
                                Task {
                                    if let userId = authService.currentUser?.id {
                                        await groupService.updateMood(mood, for: userId, in: group.id)
                                    }
                                }
                            },
                            onRenameTap: { renamingGroup = group }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedGroup = group }
                    }

                    // Bottom padding so last card isn't hidden by floating button
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
            }
            .refreshable {
                await groupService.fetchGroups()
                await groupService.fetchPendingInvitations()
            }
            .navigationDestination(item: $selectedGroup) { group in
                GroupDetailView(group: group)
                    .environmentObject(groupService)
                    .environmentObject(authService)
            }

            // Floating "create a group" button — bottom z-layer
            floatingCreateButton
                .padding(.horizontal, 64)
                .padding(.bottom, 32)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            // Floating icon bar — settings (and debug flask) only
            HStack(spacing: 8) {
#if DEBUG
                Button { groupService.loadMockGroups() } label: {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "3C392A").opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(hex: "EDE8D8")))
                }
                .buttonStyle(.plain)
#endif

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "3C392A").opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(hex: "EDE8D8")))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 24)
            .padding(.top, 8)
        }
        .confirmationDialog("", isPresented: $showSettings, titleVisibility: .hidden) {
            Button("How to add the widget") { }
            Button("Follow us on TikTok") { }
            Button("I need help") { }
            Button("Sign out", role: .destructive) { authService.signOut() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Floating create button

    private var floatingCreateButton: some View {
        Button(action: requestContactsThenCreate) {
            ZStack {
                Text("create a group")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Spacer()
                    Text("+")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .padding(.trailing, 24)
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
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func requestContactsThenCreate() {
        #if !DEBUG
        guard groupService.groups.count < Self.freeGroupLimit else {
            showPaywall = true
            return
        }
        #endif
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async { showCreateGroup = true }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService())
}
