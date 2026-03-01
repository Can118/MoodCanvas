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
            if entry.group.type == .couple {
                MediumWidgetView(entry: entry)
            } else {
                // BFF and Family both use the member-list layout
                BFFMediumWidgetView(entry: entry)
            }
        case .systemLarge:
            // Only BFF/Family widget supports large; couple widget never reaches here
            BFFLargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - 4×2 Widget (systemMedium)

struct MediumWidgetView: View {
    let entry: MoodEntry

    private let olive = Color(red: 0.40, green: 0.35, blue: 0.22)

    /// Current user first, partner second.
    private var sortedMembers: [User] {
        var list = Array(entry.group.members.prefix(2))
        guard let userId = entry.currentUserId,
              let idx = list.firstIndex(where: { $0.id == userId }),
              idx != 0 else { return list }
        let me = list.remove(at: idx)
        list.insert(me, at: 0)
        return list
    }

    var body: some View {
        ZStack {
            // Heart — background watermark, lower-center
            Image("heart_couples")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(x: 30, y: 0)
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 6) {

                // ── Left: member mood rows + message button ─────────────────
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { idx, member in
                        let isMe = member.id == entry.currentUserId
                        let displayName = isMe ? "You" : member.name
                        let mood = entry.group.currentMoods[member.id] ?? .happy

                        HStack(spacing: 6) {
                            Image(moodDisplayImageName(mood))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 54, height: 54)
                                .offset(x: -8)
                            // offset matches icon so the gap between icon and name stays tight
                            memberLabel(name: displayName, userId: member.id)
                                .offset(x: -8)
                        }
                        // Row 0 pushed down, row 1 pulled up toward center
                        .padding(.top, idx == 0 ? 10 : -8)

                        // if idx == 0 && sortedMembers.count > 1 {
                        //     Image("line")
                        //         .resizable()
                        //         .scaledToFit()
                        //         .frame(width: 90)
                        //         .frame(maxWidth: .infinity, alignment: .center)
                        //         .padding(.vertical, 2)
                        // }
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: 148, alignment: .leading)
                .padding(.top, 8)

                // ── Right: heading + 2×2 mood buttons ──────────────────────
                // 19pt (vs 17pt for BFF medium) compensates for the larger 54pt
                // couple mochi icons creating more visual mass on the left side,
                // which makes same-size text appear smaller by comparison.
                VStack(alignment: .trailing, spacing: 2) {
                    Text("How are you feeling?")
                        .padding(.top, 6)
                        .font(.system(size: 19, weight: .medium))
                        .fontDesign(.rounded)
                        .foregroundStyle(olive)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                        .kerning(-0.5)
                        .frame(maxWidth: .infinity, alignment: .trailing)

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

            // ── Message button — pinned to bottom-left, independent of rows ──
            if let url = partnerPhoneURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text("Message")
                            .font(.system(size: 11, weight: .medium))
                            .fontDesign(.rounded)
                    }
                    .foregroundStyle(olive.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(olive.opacity(0.08))
                            .overlay(Capsule().strokeBorder(olive.opacity(0.2), lineWidth: 0.5))
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `sms:` URL for the partner — opens their iMessage thread.
    private var partnerPhoneURL: URL? {
        guard let userId = entry.currentUserId else { return nil }
        guard let partner = entry.group.members.first(where: { $0.id != userId }) else { return nil }
        return URL(string: "sms:\(partner.phoneNumber)")
    }

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

    private func formattedTime(userId: String) -> String? {
        guard let iso = entry.group.moodTimestamps[userId] else { return nil }
        guard let date = parseTimestamp(iso) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private func parseTimestamp(_ iso: String) -> Date? {
        let s = iso.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return d }
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return d }
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

    private func moodDisplayImageName(_ mood: Mood) -> String {
        switch mood {
        case .happy, .excited: return "mood_mochi_v2_very_happy 30"
        case .sad:             return "mood_mochi_v2_sad 23"
        case .angry:           return "mood_mochi_v2_angry 25"
        case .tired, .chill:   return "mood_mochi_v2_neutral 21"
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

// MARK: - BFF + Family 4×2 Widget (systemMedium)

struct BFFMediumWidgetView: View {
    let entry: MoodEntry

    private var selectedMood: Mood? {
        guard let userId = entry.currentUserId else { return nil }
        return entry.group.currentMoods[userId]
    }

    /// Members sorted so the current user appears first (up to 3 for 4×2 widget).
    private var sortedMembers: [User] {
        var list = Array(entry.group.members.prefix(3))
        guard let userId = entry.currentUserId,
              let idx = list.firstIndex(where: { $0.id == userId }),
              idx != 0 else { return list }
        let me = list.remove(at: idx)
        list.insert(me, at: 0)
        return list
    }

    // Scale mochi and row padding down when a 3rd member is present
    private var mochiSize: CGFloat    { sortedMembers.count <= 2 ? 54 : 38 }
    private var rowPadding: CGFloat   { sortedMembers.count <= 2 ? 2  : 1  }

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
                .ignoresSafeArea()

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
                        let mood = entry.group.currentMoods[member.id] ?? .happy

                        HStack(spacing: 6) {
                            Image(moodDisplayImageName(mood))
                                .resizable()
                                .scaledToFit()
                                .frame(width: mochiSize, height: mochiSize)
                                .offset(x: -8)

                            memberLabel(name: displayName, userId: member.id)
                                .offset(x: -8)
                        }
                        .padding(.vertical, rowPadding)

                        // Short divider separates the current user from friends
                        // if idx == 0 && sortedMembers.count > 1 {
                        //     Image("line")
                        //         .resizable()
                        //         .scaledToFit()
                        //         .frame(width: 90)
                        //         .frame(maxWidth: .infinity, alignment: .center)
                        //         .padding(.vertical, 2)
                        // }
                    }
                    Spacer(minLength: 0)
                }
                // Fixed width so the right column always gets enough room for buttons
                .frame(width: 148, alignment: .leading)
                .padding(.top, 8)

                // ── Right: "How are you feeling?" + 2×2 mood buttons ──────────
                VStack(alignment: .trailing, spacing: 2) {
                    Text("How are you feeling?")
                        .padding(.top, 6)
                        .font(.system(size: 17, weight: .medium))
                        .fontDesign(.rounded)
                        .foregroundStyle(olive)
                        .minimumScaleFactor(0.85)
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

    private func moodDisplayImageName(_ mood: Mood) -> String {
        switch mood {
        case .happy, .excited: return "mood_mochi_v2_very_happy 30"
        case .sad:             return "mood_mochi_v2_sad 23"
        case .angry:           return "mood_mochi_v2_angry 25"
        case .tired, .chill:   return "mood_mochi_v2_neutral 21"
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

// MARK: - BFF + Family 4×4 Widget (systemLarge)

struct BFFLargeWidgetView: View {
    let entry: MoodEntry

    private var selectedMood: Mood? {
        guard let userId = entry.currentUserId else { return nil }
        return entry.group.currentMoods[userId]
    }

    /// Members sorted so the current user appears first (up to 8).
    private var sortedMembers: [User] {
        var list = Array(entry.group.members.prefix(8))
        guard let userId = entry.currentUserId,
              let idx = list.firstIndex(where: { $0.id == userId }),
              idx != 0 else { return list }
        let me = list.remove(at: idx)
        list.insert(me, at: 0)
        return list
    }

    // Member list column is flexible: ~193pt (full widget - 127pt buttons - 6pt gap).
    // Text area per member count (icon frame + 6pt HStack spacing subtracted):
    //   ≤4 members  60pt icon → 193-60-6 = 127pt text  (18pt font)
    //    5 members  52pt icon → 193-52-6 = 135pt text  (17pt font)
    //    6 members  44pt icon → 193-44-6 = 143pt text  (16pt font)
    //    7 members  36pt icon → 193-36-6 = 151pt text  (16pt font)
    //    8 members  30pt icon → 193-30-6 = 157pt text  (16pt font)
    // Worst-case "Morgan · 11:45 AM" fits in all slots; minimumScaleFactor(0.8)
    // provides a safety margin for unusually long names.
    private var mochiSize: CGFloat {
        switch sortedMembers.count {
        case ...4: return 60
        case 5:    return 52
        case 6:    return 44
        case 7:    return 36
        default:   return 30   // 8 members
        }
    }
    private var labelFontSize: CGFloat {
        switch sortedMembers.count {
        case ...4: return 18
        case 5:    return 17
        default:   return 16   // 6–8 members — consistent size, full timestamps
        }
    }
    private var mochiOffset: CGFloat {
        switch sortedMembers.count {
        case ...5: return -8
        case 6, 7: return -6
        default:   return -4
        }
    }

    private let olive = Color(red: 0.40, green: 0.35, blue: 0.22)

    var body: some View {
        ZStack {
            // Face emoji — bottom center watermark
            Image("face_emoji")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, -16)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Header row: group name (left) + heading (right) ───────────
                // The heading spans the full widget width, so it always fits on
                // one line. The member list below is no longer width-coupled to
                // the heading, so both can be as wide as they need to be.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(entry.group.name)
                        .font(.custom("InstrumentSerif-Italic", size: 14))
                        .foregroundStyle(olive.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                    Text("How are you feeling?")
                        .font(.system(size: 16, weight: .medium))
                        .fontDesign(.rounded)
                        .foregroundStyle(olive)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                        .kerning(-0.5)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)

                // ── Content row: member list (flexible) + mood buttons (fixed) ─
                // Member list gets ~193pt (full width - 127pt buttons - 6pt gap),
                // which comfortably fits icons + "Morgan · 11:45 AM" at 18pt.
                HStack(alignment: .top, spacing: 6) {

                    // Member mood rows — each fills an equal share of height
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { idx, member in
                            let isMe = member.id == entry.currentUserId
                            let displayName = isMe ? "You" : member.name
                            let mood = entry.group.currentMoods[member.id] ?? .happy

                            // Separator is fixed-height, before row 1
                            // if idx == 1 && sortedMembers.count > 1 {
                            //     Image("line")
                            //         .resizable()
                            //         .scaledToFit()
                            //         .frame(width: 90)
                            //         .frame(maxWidth: .infinity, alignment: .center)
                            //         .padding(.vertical, 2)
                            // }

                            HStack(spacing: 6) {
                                Image(moodDisplayImageName(mood))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: mochiSize, height: mochiSize)
                                    .offset(x: mochiOffset)

                                memberLabel(name: displayName, userId: member.id)
                                    .offset(x: mochiOffset)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 2×2 mood button grid — fixed to exactly 2×62pt + 3pt gap
                    VStack(alignment: .trailing, spacing: 0) {
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
                        Spacer(minLength: 0)
                    }
                    .frame(width: 127, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 4)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func memberLabel(name: String, userId: String) -> some View {
        if let timeStr = formattedTime(userId: userId) {
            (Text(name)
             + Text("  ·  \(timeStr)").foregroundStyle(olive.opacity(0.65)))
                .font(.custom("EB Garamond", size: labelFontSize).weight(.medium))
                .foregroundStyle(olive)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(name)
                .font(.custom("EB Garamond", size: labelFontSize).weight(.medium))
                .foregroundStyle(olive)
                .lineLimit(1)
        }
    }

    private func formattedTime(userId: String) -> String? {
        guard let iso = entry.group.moodTimestamps[userId] else { return nil }
        guard let date = parseTimestamp(iso) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private func parseTimestamp(_ iso: String) -> Date? {
        let s = iso.replacingOccurrences(
            of: #"(\.\d{3})\d+"#,
            with: "$1",
            options: .regularExpression
        )
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return d }
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return d }
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

    private func moodDisplayImageName(_ mood: Mood) -> String {
        switch mood {
        case .happy, .excited: return "mood_mochi_v2_very_happy 30"
        case .sad:             return "mood_mochi_v2_sad 23"
        case .angry:           return "mood_mochi_v2_angry 25"
        case .tired, .chill:   return "mood_mochi_v2_neutral 21"
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

