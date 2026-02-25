import SwiftUI
import Contacts

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var groupService = GroupService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showCreateGroup = false
    @State private var showInvitations = false

    var body: some View {
        NavigationStack {
            Group {
                if groupService.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("MoodCanvas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !groupService.pendingInvitations.isEmpty {
                        Button {
                            showInvitations = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.title2)
                                Text("\(groupService.pendingInvitations.count)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            Task {
                                await groupService.fetchGroups()
                                await groupService.fetchPendingInvitations()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                        }
                        Button {
                            requestContactsThenCreate()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
                    .environmentObject(groupService)
                    .environmentObject(authService)
            }
            .sheet(isPresented: $showInvitations) {
                PendingInvitationsView()
                    .environmentObject(groupService)
            }
            .task {
                await groupService.fetchGroups()
                await groupService.fetchPendingInvitations()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        // Refresh JWT first so any push-notification or widget call
                        // that runs immediately after also gets a fresh token.
                        await authService.refreshJWTIfNeeded()
                        await groupService.processPendingWidgetMoods(currentUserId: authService.currentUser?.id)
                        await groupService.fetchGroups()
                        await groupService.fetchPendingInvitations()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No groups yet")
                .font(.title2.bold())
            Text("Create a group to start sharing moods.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Create a Group") {
                requestContactsThenCreate()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var groupList: some View {
        List(groupService.groups) { group in
            NavigationLink(destination: GroupDetailView(group: group)
                .environmentObject(groupService)
                .environmentObject(authService)) {
                GroupRowView(group: group)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await groupService.fetchGroups()
            await groupService.fetchPendingInvitations()
        }
    }

    // MARK: - Helpers

    private func requestContactsThenCreate() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async {
                showCreateGroup = true
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService())
}
