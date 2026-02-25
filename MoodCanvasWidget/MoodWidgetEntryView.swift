import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Entry View Router

struct MoodWidgetEntryView: View {
    let entry: MoodEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            if entry.group.type == .bff {
                BFFMediumWidgetView(entry: entry)
            } else {
                MediumWidgetView(entry: entry)
            }
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - 4×2 Widget (systemMedium)

struct MediumWidgetView: View {
    let entry: MoodEntry

    /// The mood the current user has set in this group, nil if none yet.
    private var selectedMood: Mood? {
        guard let userId = entry.currentUserId else { return nil }
        return entry.group.currentMoods[userId]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(entry.group.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)

                Spacer()

                // Message button for couples only — opens the partner's iMessage thread
                if entry.group.type == .couple, let url = partnerPhoneURL {
                    Link(destination: url) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(6)
                            .background(.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            }

            // Heart counter row — couple groups only
            if entry.group.type == .couple {
                HStack(spacing: 8) {
                    Text("❤️")
                        .font(.subheadline)
                    Text("\(entry.group.heartCount)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Spacer()
                    Button(intent: heartIntent) {
                        Image(systemName: "heart.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.pink)
                            .padding(7)
                            .background(.white.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // 5 mood buttons — the current user's active mood is visually highlighted
            HStack(spacing: 6) {
                ForEach(Mood.allCases) { mood in
                    let isSelected = mood == selectedMood
                    Button(intent: moodIntent(mood)) {
                        VStack(spacing: 3) {
                            Text(mood.emoji)
                                .font(.title3)
                            Text(mood.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isSelected ? .white.opacity(0.45) : .white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white, lineWidth: isSelected ? 1.5 : 0)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }

    /// `sms:` URL for the partner's phone — opens the existing iMessage thread on device.
    /// Returns nil if the current user is unknown or the group has no other member.
    private var partnerPhoneURL: URL? {
        guard let userId = entry.currentUserId else { return nil }
        guard let partner = entry.group.members.first(where: { $0.id != userId }) else { return nil }
        return URL(string: "sms:\(partner.phoneNumber)")
    }

    private var heartIntent: SendHeartIntent {
        var intent = SendHeartIntent()
        intent.groupId = entry.group.id
        return intent
    }

    private func moodIntent(_ mood: Mood) -> SetMoodIntent {
        var intent = SetMoodIntent()
        intent.payload = "\(entry.group.id)|\(mood.rawValue)"
        return intent
    }
}

// MARK: - BFF 4×2 Widget (systemMedium, .bff groups)

struct BFFMediumWidgetView: View {
    let entry: MoodEntry

    private var selectedMood: Mood? {
        guard let userId = entry.currentUserId else { return nil }
        return entry.group.currentMoods[userId]
    }

    /// Members sorted so the current user appears first.
    private var sortedMembers: [User] {
        var list = Array(entry.group.members.prefix(4))
        guard let userId = entry.currentUserId,
              let idx = list.firstIndex(where: { $0.id == userId }),
              idx != 0 else { return list }
        let me = list.remove(at: idx)
        list.insert(me, at: 0)
        return list
    }

    /// Olive/khaki colour from the Figma design.
    private let olive = Color(red: 0.50, green: 0.47, blue: 0.35)

    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // ── Left: member mood list ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { idx, member in
                    HStack(spacing: 8) {
                        if let mood = entry.group.currentMoods[member.id],
                           let name = moodDisplayImageName(mood) {
                            Image(name)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                        } else {
                            Color.clear.frame(width: 34, height: 34)
                        }
                        Text(member.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(olive)
                            .lineLimit(1)
                    }
                    // Thin divider separates the current user from friends
                    if idx == 0 && sortedMembers.count > 1 {
                        Rectangle()
                            .fill(olive.opacity(0.25))
                            .frame(height: 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Right: "How are you feeling?" + 2×2 mood buttons ──────────
            VStack(alignment: .center, spacing: 8) {
                Image("how_are_you_feeling")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)

                // 2×2 grid matching Figma order: angry/sad top, tired/happy bottom
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        moodButtonView(.angry)
                        moodButtonView(.sad)
                    }
                    HStack(spacing: 6) {
                        moodButtonView(.tired)
                        moodButtonView(.happy)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Render the design background INSIDE the widget so iOS dark-mode
        // adaptive rendering (which blacks out containerBackground images) is bypassed.
        .background {
            Image("widget_background")
                .resizable()
                .scaledToFill()
                .clipped()
        }
    }

    @ViewBuilder
    private func moodButtonView(_ mood: Mood) -> some View {
        Button(intent: moodIntent(mood)) {
            Image(moodButtonImageName(mood))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(olive, lineWidth: mood == selectedMood ? 2.5 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func moodDisplayImageName(_ mood: Mood) -> String? {
        switch mood {
        case .happy: return "happy_mood"
        case .sad:   return "sad_mood"
        case .tired: return "tired_mood"
        case .angry: return "angry_mood"
        default:     return nil
        }
    }

    private func moodButtonImageName(_ mood: Mood) -> String {
        switch mood {
        case .happy: return "happy_mood_button"
        case .sad:   return "sad_mood_button"
        case .tired: return "tired_mood_button"
        case .angry: return "angry_mood_button"
        default:     return "happy_mood_button"
        }
    }

    private func moodIntent(_ mood: Mood) -> SetMoodIntent {
        var intent = SetMoodIntent()
        intent.payload = "\(entry.group.id)|\(mood.rawValue)"
        return intent
    }
}

// MARK: - 4×4 Widget (systemLarge)

struct LargeWidgetView: View {
    let entry: MoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.group.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(entry.group.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if entry.group.type == .couple, let url = partnerPhoneURL {
                    Link(destination: url) {
                        Label("Message", systemImage: "message.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            // Member mood rows
            VStack(spacing: 6) {
                ForEach(entry.group.members) { member in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Text(String(member.name.prefix(1)).uppercased())
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }

                        Text(member.name)
                            .font(.subheadline)
                            .foregroundStyle(.white)

                        Spacer()

                        if let mood = entry.group.currentMoods[member.id] {
                            HStack(spacing: 4) {
                                Text(mood.emoji)
                                Text(mood.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        } else {
                            Text("–")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Heart counter row — couple groups only
            if entry.group.type == .couple {
                HStack(spacing: 8) {
                    Text("❤️")
                        .font(.title3)
                    Text("\(entry.group.heartCount)")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Spacer()
                    Button(intent: heartIntent) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.pink)
                            .padding(9)
                            .background(.white.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // 5 mood buttons
            HStack(spacing: 8) {
                ForEach(Mood.allCases) { mood in
                    Button(intent: moodIntent(mood)) {
                        VStack(spacing: 5) {
                            Text(mood.emoji)
                                .font(.title2)
                            Text(mood.label)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    /// `sms:` URL for the partner's phone — opens the existing iMessage thread on device.
    private var partnerPhoneURL: URL? {
        guard let userId = entry.currentUserId else { return nil }
        guard let partner = entry.group.members.first(where: { $0.id != userId }) else { return nil }
        return URL(string: "sms:\(partner.phoneNumber)")
    }

    private var heartIntent: SendHeartIntent {
        var intent = SendHeartIntent()
        intent.groupId = entry.group.id
        return intent
    }

    private func moodIntent(_ mood: Mood) -> SetMoodIntent {
        var intent = SetMoodIntent()
        intent.payload = "\(entry.group.id)|\(mood.rawValue)"
        return intent
    }
}
