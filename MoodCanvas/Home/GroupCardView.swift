import SwiftUI

// MARK: - Mood image helpers (main-app only)

extension Mood {
    /// Image name for the user's current-mood display (no container).
    var displayImageName: String {
        switch self {
        case .happy:   return "happy_mood"
        case .sad:     return "sad_mood"
        case .angry:   return "angry_mood"
        case .tired:   return "tired_mood"
        case .excited: return "happy_mood"
        case .chill:   return "tired_mood"
        }
    }

    /// The four moods shown as tappable buttons on the home card.
    static var cardMoods: [Mood] { [.happy, .sad, .angry, .tired] }
}

// MARK: - GroupCardView

struct GroupCardView: View {
    let group: MoodGroup
    let currentUserId: String
    let onMoodTap: (Mood) -> Void
    var onRenameTap: (() -> Void)? = nil

    private var isCouple: Bool { group.type == .couple }

    private var buttonContainerImage: String {
        isCouple ? "mood_button_container_couples" : "mood_button_container"
    }
    private var separatorColor: Color {
        isCouple ? Color(hex: "E9A0B8") : Color(hex: "C4A882")
    }
    private var nameColor: Color {
        isCouple ? Color(hex: "51083A") : Color(hex: "665938")
    }
    private var memberColor: Color {
        isCouple ? Color(hex: "A05070") : Color(hex: "6C6649")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background card PNG
            Image(isCouple ? "couples_card" : "bff_family_card")
                .resizable()
                .scaledToFill()

            // Couple heart decoration
            if isCouple {
                Image("heart_couples")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.top, 16)
                    .opacity(0.9)
            }

            // Content
            VStack(alignment: .center, spacing: 10) {
                // Group name — tappable if a rename callback is provided
                if let onRenameTap {
                    Button(action: onRenameTap) {
                        Text(group.name)
                            .font(Font.custom("EBGaramond-SemiBold", size: 26))
                            .foregroundStyle(nameColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                } else {
                    Text(group.name)
                        .font(Font.custom("EBGaramond-SemiBold", size: 26))
                        .foregroundStyle(nameColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }

                // Couple: heart counter preview / BFF+Family: member names
                if isCouple {
                    HStack(spacing: 5) {
                        Text("🩷")
                            .font(.system(size: 14))
                        Text("\(group.heartCount)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(memberColor)
                    }
                    .padding(.top, 4)
                } else {
                    Text(membersText)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(memberColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                        .padding(.top, 4)
                }

                Spacer(minLength: 12)

                // Mood row — fixed height so .aspectRatio(1, .fit) buttons
                // never get a smaller proposed height than their natural width.
                moodRow
                    .frame(height: 62)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isCouple ? 210 : 190)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Members text

    private var orderedMembers: [User] {
        var list = group.members
        if let idx = list.firstIndex(where: { $0.id == currentUserId }) {
            let me = list.remove(at: idx)
            list.insert(me, at: 0)
        }
        return list
    }

    private var membersText: String {
        let names = orderedMembers.map { $0.name }
        return isCouple
            ? names.joined(separator: " 💜 ")
            : names.joined(separator: " • ")
    }

    // MARK: - Mood row

    private var moodRow: some View {
        HStack(spacing: 6) {
            // User's current mood — no container, slightly smaller to give
            // maximum width to the 4 tappable mood buttons
            let myMood = group.currentMoods[currentUserId] ?? .happy
            Image(myMood.displayImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .id(myMood)

            // Separator
            Capsule()
                .fill(separatorColor.opacity(0.7))
                .frame(width: 1.5, height: 42)

            // No ScrollView — plain HStack so buttons fill all remaining space.
            // frame(maxWidth:.infinity).aspectRatio(1) makes each button as large
            // as possible while staying square and showing all 4 without scrolling.
            HStack(spacing: 4) {
                ForEach(Mood.cardMoods) { mood in
                    moodButton(mood)
                }
            }
        }
    }

    private func moodButton(_ mood: Mood) -> some View {
        Button { onMoodTap(mood) } label: {
            Image(mood.displayImageName)
                .resizable()
                .scaledToFit()
                .padding(7)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background {
                    Image(buttonContainerImage)
                        .resizable()
                        .scaledToFill()
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            GroupCardView(group: .preview, currentUserId: "1", onMoodTap: { _ in })
            GroupCardView(group: .couplePreview, currentUserId: "4", onMoodTap: { _ in })
            GroupCardView(group: .familyPreview, currentUserId: "6", onMoodTap: { _ in })
        }
        .padding(20)
    }
    .background(Color(hex: "FFFCED"))
}
