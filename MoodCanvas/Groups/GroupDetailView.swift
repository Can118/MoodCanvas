import SwiftUI

struct GroupDetailView: View {
    let group: MoodGroup

    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showAddMembers    = false
    @State private var showSettings      = false
    @State private var showWidgetTutorial = false

    // Always read fresh data from GroupService
    private var liveGroup: MoodGroup {
        groupService.groups.first { $0.id == group.id } ?? group
    }

    private var currentUserId: String { authService.currentUser?.id ?? "" }

    private var otherMembers: [User] {
        liveGroup.members.filter { $0.id != currentUserId }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "FFFCED").ignoresSafeArea()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Space for floating top buttons
                    Color.clear.frame(height: 72)

                    // Group name
                    Text(liveGroup.name)
                        .font(Font.custom("EBGaramond-Bold", size: 34))
                        .foregroundStyle(Color(hex: "3C392A"))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    // Current user's big mood
                    let myMood = liveGroup.currentMoods[currentUserId] ?? .happy
                    Image(myMood.displayImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 116)
                        .frame(maxWidth: .infinity)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: myMood)
                        .padding(.bottom, 20)

                    // Divider
                    Divider()
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)

                    // Other members' moods
                    ForEach(otherMembers) { member in
                        memberRow(member)
                    }

                    // Padding so last row isn't hidden by bottom mood bar
                    Color.clear.frame(height: 110)
                }
            }

            // Fixed bottom mood selector
            moodSelector
        }
        // Floating top-right buttons
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                // + (add members)
                Button { showAddMembers = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color(hex: "B8721C")))
                }
                .buttonStyle(.plain)

                // Settings
                Button { showSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "3C392A").opacity(0.5))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color(hex: "EDE8D8")))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddMembers) {
            AddMembersView(group: liveGroup)
                .environmentObject(groupService)
                .environmentObject(authService)
        }
        .fullScreenCover(isPresented: $showWidgetTutorial) {
            WidgetTutorialView(onDismiss: { showWidgetTutorial = false })
        }
        .confirmationDialog("", isPresented: $showSettings, titleVisibility: .hidden) {
            Button("Leave the group", role: .destructive) {
                Task {
                    await groupService.leaveGroup(id: liveGroup.id)
                    dismiss()
                }
            }
            Button("How to add the widget") {
                showWidgetTutorial = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Member row

    private func memberRow(_ member: User) -> some View {
        HStack(spacing: 14) {
            let mood = liveGroup.currentMoods[member.id] ?? .happy
            Image(mood.displayImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)

            HStack(spacing: 5) {
                Text(member.name)
                    .font(Font.custom("EBGaramond-Bold", size: 20))
                    .foregroundStyle(Color(hex: "3C392A"))

                Text("•")
                    .font(Font.custom("EBGaramond-Medium", size: 18))
                    .foregroundStyle(Color(hex: "837C5A"))

                Text(formattedTime(liveGroup.moodTimestamps[member.id]))
                    .font(Font.custom("EBGaramond-Medium", size: 18))
                    .foregroundStyle(Color(hex: "837C5A"))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Bottom mood selector

    private var moodSelector: some View {
        HStack(spacing: 10) {
            ForEach(Mood.cardMoods) { mood in
                Button {
                    Task {
                        await groupService.updateMood(mood, for: currentUserId, in: liveGroup.id)
                    }
                } label: {
                    Group {
                        if let imgName = mood.buttonImageName {
                            Image(imgName)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                        } else {
                            Text(mood.emoji).font(.title2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(hex: "E4BF89"))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 44)
        .padding(.top, 12)
        .background(
            Color(hex: "FFFCED")
                .ignoresSafeArea()
                .shadow(color: Color(hex: "3C392A").opacity(0.07), radius: 10, y: -4)
        )
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

#Preview {
    NavigationStack {
        GroupDetailView(group: .preview)
            .environmentObject(GroupService())
            .environmentObject(AuthService())
    }
}
