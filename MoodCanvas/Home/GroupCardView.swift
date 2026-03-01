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
        case .excited: return "happy_mood"   // fallback
        case .chill:   return "tired_mood"   // fallback
        }
    }

    /// Image name for the selectable mood button. Nil → emoji fallback.
    var buttonImageName: String? {
        switch self {
        case .happy:   return "happy_mood_button"
        case .sad:     return "sad_mood_button"
        case .angry:   return "angry_mood_button"
        case .tired:   return "tired_mood_button"
        default:       return nil
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

    private var containerColor: Color {
        isCouple ? Color(hex: "FDE7EA") : Color(hex: "E4BF89")
    }
    private var textColor: Color {
        isCouple ? Color(hex: "51083A") : Color(hex: "3C392A")
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
            VStack(alignment: isCouple ? .center : .leading, spacing: 10) {
                // Group name — tappable if a rename callback is provided
                Group {
                    if let onRenameTap {
                        Button(action: onRenameTap) {
                            Text(group.name)
                                .font(Font.custom("EBGaramond-SemiBold", size: 26))
                                .foregroundStyle(textColor)
                                .multilineTextAlignment(isCouple ? .center : .leading)
                                .frame(maxWidth: isCouple ? .infinity : nil)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(group.name)
                            .font(Font.custom("EBGaramond-SemiBold", size: 26))
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(isCouple ? .center : .leading)
                            .frame(maxWidth: isCouple ? .infinity : nil)
                    }
                }

                // Member names
                Text(membersText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor.opacity(0.75))
                    .multilineTextAlignment(isCouple ? .center : .leading)
                    .frame(maxWidth: isCouple ? .infinity : nil)
                    .lineLimit(2)

                Spacer(minLength: 12)

                // Mood row
                moodRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isCouple ? 210 : 190)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Members text

    /// Current user first, rest in original order.
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
            : names.joined(separator: " · ")
    }

    // MARK: - Mood row

    private var moodRow: some View {
        HStack(spacing: 10) {
            // User's current mood — no container
            Group {
                let mood = group.currentMoods[currentUserId] ?? .happy
                Image(mood.displayImageName)
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: 60, height: 60)

            // Separator
            Image("sep_line")
                .resizable()
                .scaledToFit()
                .frame(height: 66)

            // Scrollable mood buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Mood.cardMoods) { mood in
                        moodButton(mood)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func moodButton(_ mood: Mood) -> some View {
        Button {
            onMoodTap(mood)
        } label: {
            Group {
                if let imgName = mood.buttonImageName {
                    Image(imgName)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Text(mood.emoji)
                        .font(.title2)
                }
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(containerColor)
            )
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
