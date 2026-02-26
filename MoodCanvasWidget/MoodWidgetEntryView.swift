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

    private let olive = Color(red: 0.40, green: 0.35, blue: 0.22)

    /// The mood the current user has set in this group, nil if none yet.
    private var selectedMood: Mood? {
        guard let userId = entry.currentUserId else { return nil }
        return entry.group.currentMoods[userId]
    }

    var body: some View {
        ZStack {
        VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text(entry.group.name)
                        .font(.headline.bold())
                        .foregroundStyle(olive)

                    Spacer()

                    // Message button for couples only — opens the partner's iMessage thread
                    if entry.group.type == .couple, let url = partnerPhoneURL {
                        Link(destination: url) {
                            Image(systemName: "message.fill")
                                .foregroundStyle(olive.opacity(0.9))
                                .padding(6)
                                .background(olive.opacity(0.1))
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
                            .foregroundStyle(olive)
                            .contentTransition(.numericText())
                        Spacer()
                        Button(intent: heartIntent) {
                            Image(systemName: "heart.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.pink)
                                .padding(7)
                                .background(.white.opacity(0.7))
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
                                    .foregroundStyle(olive)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? olive.opacity(0.15) : olive.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(olive.opacity(0.4), lineWidth: isSelected ? 1.5 : 0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
        .padding(14)
        }
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

    /// Members sorted so the current user appears first (up to 4).
    private var sortedMembers: [User] {
        var list = Array(entry.group.members.prefix(4))
        guard let userId = entry.currentUserId,
              let idx = list.firstIndex(where: { $0.id == userId }),
              idx != 0 else { return list }
        let me = list.remove(at: idx)
        list.insert(me, at: 0)
        return list
    }

    /// Olive/dark-brown colour from the Figma design.
    private let olive = Color(red: 0.40, green: 0.35, blue: 0.22)

    var body: some View {
        ZStack {
            // Face emoji — bottom center, fixed size
            Image("face_emoji")
                .resizable()
                .scaledToFit()
                .frame(width: 110)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(alignment: .top, spacing: 6) {

                // ── Left: group name + member mood list ────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    // Group name in Instrument Serif Italic
                    Text(entry.group.name)
                        .font(.custom("InstrumentSerif-Italic", size: 14))
                        .foregroundStyle(olive.opacity(0.75))
                        .lineLimit(1)
                        .padding(.bottom, 6)

                    ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { idx, member in
                        let isMe = member.id == entry.currentUserId
                        let displayName = isMe ? "You" : member.name
                        let mood = entry.group.currentMoods[member.id]

                        HStack(spacing: 6) {
                            if let mood, let imgName = moodDisplayImageName(mood) {
                                Image(imgName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 54, height: 54)
                                    .offset(x: -8)
                            } else {
                                Color.clear.frame(width: 54, height: 54)
                                    .offset(x: -8)
                            }

                            memberLabel(name: displayName, userId: member.id)
                        }
                        .padding(.vertical, 2)

                        // Short divider separates the current user from friends
                        if idx == 0 && sortedMembers.count > 1 {
                            Image("line")
                                .resizable()
                                .frame(width: 90, height: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // Fixed width so the right column always gets enough room for buttons
                .frame(width: 148, alignment: .leading)
                .padding(.top, 8)

                // ── Right: "How are you feeling?" + 2×2 mood buttons ──────────
                // Buttons are 68×68pt: grid = (68+3+68) × (68+3+68) = 139×139pt
                // Total right column height: ~20 heading + 6 spacing + 139 = 165pt < 169pt ✓
                VStack(alignment: .trailing, spacing: 2) {
                    Text("How are you feeling?")
                        .padding(.top, 6)
                        .font(.system(size: 22, weight: .medium))
                        .fontDesign(.rounded)
                        .foregroundStyle(olive)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .kerning(-0.5)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    // 2×2 grid — compact fixed-size buttons, hugging the right edge
                    VStack(spacing: 0) {
                        HStack(spacing: 3) {
                            moodButtonView(.angry)
                            moodButtonView(.sad)
                        }
                        HStack(spacing: 3) {
                            moodButtonView(.tired)
                            moodButtonView(.happy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .padding(.leading, 0)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Name + optional "· HH:MM AM" timestamp label in EB Garamond Medium.
    @ViewBuilder
    private func memberLabel(name: String, userId: String) -> some View {
        if let timeStr = formattedTime(userId: userId) {
            (Text(name)
             + Text("  ·  \(timeStr)").foregroundStyle(olive.opacity(0.65)))
                .font(.custom("EB Garamond", size: 15).weight(.medium))
                .foregroundStyle(olive)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else {
            Text(name)
                .font(.custom("EB Garamond", size: 15).weight(.medium))
                .foregroundStyle(olive)
                .lineLimit(1)
        }
    }

    /// Parses the ISO-8601 timestamp stored in moodTimestamps and returns a
    /// locale-appropriate short time string (e.g. "7:33 AM").
    private func formattedTime(userId: String) -> String? {
        guard let iso = entry.group.moodTimestamps[userId] else { return nil }
        guard let date = parseTimestamp(iso) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    /// Robust ISO-8601 timestamp parser that handles:
    /// - PostgreSQL microseconds: "2026-02-25T20:33:33.123456+00:00"
    /// - ISO8601DateFormatter quirks with +00:00 timezone and fractional seconds
    private func parseTimestamp(_ iso: String) -> Date? {
        // Normalize: truncate microseconds (6 digits) to milliseconds (3 digits)
        // so ISO8601DateFormatter can parse the fractional part correctly.
        let s = iso.replacingOccurrences(
            of: #"(\.\d{3})\d+"#,
            with: "$1",
            options: .regularExpression
        )
        // Attempt 1: ISO8601DateFormatter with fractional seconds
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return d }

        // Attempt 2: ISO8601DateFormatter without fractional seconds
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return d }

        // Attempt 3: DateFormatter with XXX timezone specifier.
        // DateFormatter handles "+00:00" via XXX reliably, unlike ISO8601DateFormatter
        // which has known edge cases combining +HH:MM offset with fractional seconds.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return df.date(from: s)
    }

    @ViewBuilder
    private func moodButtonView(_ mood: Mood) -> some View {
        Button(intent: moodIntent(mood)) {
            Image(moodButtonImageName(mood))
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func moodDisplayImageName(_ mood: Mood) -> String? {
        switch mood {
        case .happy:  return "mood_mochi_v2_very_happy 30"
        case .sad:    return "mood_mochi_v2_sad 23"
        case .angry:  return "mood_mochi_v2_angry 25"
        case .tired:  return "mood_mochi_v2_neutral 21"
        default:      return nil
        }
    }

    private func moodButtonImageName(_ mood: Mood) -> String {
        switch mood {
        case .happy:  return "Group 43"
        case .sad:    return "Group 42"
        case .angry:  return "Group 41"
        case .tired:  return "Group 44"
        default:      return "Group 43"
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
