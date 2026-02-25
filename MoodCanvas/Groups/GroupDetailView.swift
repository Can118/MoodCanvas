import SwiftUI

struct GroupDetailView: View {
    let group: MoodGroup
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService

    @State private var showAddMembers = false

    // Always read the freshest version from GroupService so the view
    // updates automatically when members are added or moods change.
    private var liveGroup: MoodGroup {
        groupService.groups.first { $0.id == group.id } ?? group
    }

    private var heartCount: Int {
        groupService.heartCounts[liveGroup.id] ?? liveGroup.heartCount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Mood canvas card
                MoodCanvasCard(group: liveGroup)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Heart counter — couple groups only
                if liveGroup.type == .couple {
                    CoupleHeartSection(count: heartCount) {
                        Task { await groupService.sendHeart(groupId: liveGroup.id) }
                    }
                    .padding(.horizontal)
                }

                // Member mood list
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Members")
                            .font(.headline)
                        Spacer()
                        if liveGroup.createdBy == authService.currentUser?.id {
                            Button {
                                showAddMembers = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.bold())
                            }
                        }
                    }
                    .padding(.horizontal)

                    ForEach(liveGroup.members) { member in
                        MemberMoodRow(
                            member: member,
                            mood: liveGroup.currentMoods[member.id]
                        )
                        .padding(.horizontal)

                        if member.id != liveGroup.members.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Pick your mood
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Mood")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack(spacing: 10) {
                        ForEach(Mood.allCases) { mood in
                            Button {
                                Task {
                                    if let userId = authService.currentUser?.id {
                                        await groupService.updateMood(mood, for: userId, in: liveGroup.id)
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(mood.emoji)
                                        .font(.title2)
                                    Text(mood.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(liveGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddMembers) {
            AddMembersView(group: liveGroup)
                .environmentObject(groupService)
                .environmentObject(authService)
        }
    }
}

// MARK: - Couple Heart Section

struct CoupleHeartSection: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hearts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: count)
            }

            Spacer()

            Button(action: onTap) {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.pink)
                    .clipShape(Circle())
                    .shadow(color: .pink.opacity(0.4), radius: 8, y: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Mood Canvas Card

struct MoodCanvasCard: View {
    let group: MoodGroup

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(group.type.backgroundGradient)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .overlay {
                VStack(spacing: 12) {
                    Text(group.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        ForEach(group.members) { member in
                            VStack(spacing: 4) {
                                Text(group.currentMoods[member.id]?.emoji ?? "·")
                                    .font(.title)
                                Text(member.name)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - Member Mood Row

struct MemberMoodRow: View {
    let member: User
    let mood: Mood?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(member.name.prefix(1)).uppercased())
                        .font(.subheadline.bold())
                }

            Text(member.name)
                .font(.subheadline)

            Spacer()

            if let mood {
                HStack(spacing: 4) {
                    Text(mood.emoji)
                    Text(mood.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("–")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: .preview)
            .environmentObject(GroupService())
            .environmentObject(AuthService())
    }
}
