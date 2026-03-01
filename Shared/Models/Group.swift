import SwiftUI

// MARK: - Group Type

enum GroupType: String, Codable, CaseIterable {
    case couple
    case bff
    case family

    var displayName: String {
        switch self {
        case .couple: return "Couple"
        case .bff:    return "BFF"
        case .family: return "Family"
        }
    }

    var icon: String {
        switch self {
        case .couple: return "💑"
        case .bff:    return "👯"
        case .family: return "👨‍👩‍👧"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .couple: return .pink
        case .bff:    return .purple
        case .family: return .orange
        }
    }

    var backgroundGradient: LinearGradient {
        switch self {
        case .couple:
            return LinearGradient(colors: [.pink, Color(red: 0.9, green: 0.2, blue: 0.4)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bff:
            return LinearGradient(colors: [.purple, .indigo],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .family:
            return LinearGradient(colors: [.orange, .yellow],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Mood Group

struct MoodGroup: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var type: GroupType
    var createdBy: String
    var members: [User]
    var currentMoods: [String: Mood]  // userId → Mood
    /// ISO-8601 strings from Supabase moods.updated_at, keyed by userId.
    /// Decoded safely — empty if the RPC doesn't return this field yet.
    var moodTimestamps: [String: String]
    /// Cumulative heart count — couple groups only. Defaults to 0 so existing
    /// cached JSON (which lacks this key) decodes cleanly.
    var heartCount: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        type: GroupType,
        createdBy: String = "",
        members: [User] = [],
        currentMoods: [String: Mood] = [:],
        moodTimestamps: [String: String] = [:],
        heartCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdBy = createdBy
        self.members = members
        self.currentMoods = currentMoods
        self.moodTimestamps = moodTimestamps
        self.heartCount = heartCount
    }

    // Custom decoder so that JSON lacking "heartCount" (e.g. cached widget data
    // written before this feature was added) decodes to 0 instead of throwing.
    enum CodingKeys: String, CodingKey {
        case id, name, type, createdBy, members, currentMoods, moodTimestamps, heartCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self,                   forKey: .id)
        name           = try c.decode(String.self,                   forKey: .name)
        type           = try c.decode(GroupType.self,                forKey: .type)
        createdBy      = try c.decode(String.self,                   forKey: .createdBy)
        members        = try c.decode([User].self,                   forKey: .members)
        currentMoods   = try c.decode([String: Mood].self,           forKey: .currentMoods)
        moodTimestamps = try c.decodeIfPresent([String: String].self, forKey: .moodTimestamps) ?? [:]
        heartCount     = try c.decodeIfPresent(Int.self,             forKey: .heartCount) ?? 0
    }
}

// MARK: - Preview Data

extension MoodGroup {
    static var preview: MoodGroup {
        let now = Date()
        let cal = Calendar.current
        func iso(_ h: Int, _ m: Int) -> String {
            let d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return ISO8601DateFormatter().string(from: d)
        }
        return MoodGroup(
            id: "preview",
            name: "Squad",
            type: .bff,
            members: [
                User(id: "1", name: "Alex",   phoneNumber: "+11234567890"),
                User(id: "2", name: "Aaron",  phoneNumber: "+10987654321"),
                User(id: "3", name: "Sarah",  phoneNumber: "+11112223333"),
                User(id: "4", name: "Jessica", phoneNumber: "+12223334444"),
            ],
            currentMoods: ["1": .happy, "2": .angry, "3": .sad, "4": .tired],
            moodTimestamps: [
                "1": iso(7, 33),
                "2": iso(13, 59),
                "3": iso(0, 2),
                "4": iso(16, 42),
            ]
        )
    }

    /// 3-member BFF group — used for the 4×2 medium widget preview
    static var bffThreePreview: MoodGroup {
        let now = Date()
        let cal = Calendar.current
        func iso(_ h: Int, _ m: Int) -> String {
            let d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return ISO8601DateFormatter().string(from: d)
        }
        return MoodGroup(
            id: "bff-three-preview",
            name: "Trio",
            type: .bff,
            members: [
                User(id: "1", name: "Alex",  phoneNumber: ""),
                User(id: "2", name: "Aaron", phoneNumber: ""),
                User(id: "3", name: "Sarah", phoneNumber: ""),
            ],
            currentMoods: ["1": .happy, "2": .angry, "3": .sad],
            moodTimestamps: ["1": iso(7, 33), "2": iso(13, 59), "3": iso(0, 2)]
        )
    }

    static var couplePreview: MoodGroup {
        MoodGroup(
            id: "couple-preview",
            name: "Us",
            type: .couple,
            members: [
                User(id: "4", name: "Riley", phoneNumber: "+14445556666"),
                User(id: "5", name: "Morgan", phoneNumber: "+17778889999"),
            ],
            currentMoods: ["4": .happy, "5": .excited]
        )
    }

    static var bffLargePreview: MoodGroup {
        let now = Date()
        let cal = Calendar.current
        func iso(_ h: Int, _ m: Int) -> String {
            let d = cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return ISO8601DateFormatter().string(from: d)
        }
        return MoodGroup(
            id: "bff-large-preview",
            name: "Heaven winners",
            type: .bff,
            members: [
                User(id: "1",  name: "Alex",    phoneNumber: ""),
                User(id: "2",  name: "Aaron",   phoneNumber: ""),
                User(id: "3",  name: "Sarah",   phoneNumber: ""),
                User(id: "4",  name: "Jessica", phoneNumber: ""),
                User(id: "5",  name: "Emily",   phoneNumber: ""),
                User(id: "6",  name: "Chris",   phoneNumber: ""),
                User(id: "7",  name: "Taylor",  phoneNumber: ""),
                User(id: "8",  name: "Jordan",  phoneNumber: ""),
            ],
            currentMoods: [
                "1": .happy, "2": .angry, "3": .sad,   "4": .tired,
                "5": .happy, "6": .angry, "7": .sad,   "8": .tired,
            ],
            moodTimestamps: [
                "1": iso(7, 33),  "2": iso(13, 59), "3": iso(0, 2),  "4": iso(19, 44),
                "5": iso(7, 33),  "6": iso(13, 59), "7": iso(0, 2),  "8": iso(3, 22),
            ]
        )
    }

    static var familyPreview: MoodGroup {
        MoodGroup(
            id: "family-preview",
            name: "Family",
            type: .family,
            members: [
                User(id: "6", name: "Mom", phoneNumber: "+10001112222"),
                User(id: "7", name: "Dad", phoneNumber: "+10002223333"),
                User(id: "8", name: "Sis", phoneNumber: "+10003334444"),
            ],
            currentMoods: ["6": .tired, "7": .chill, "8": .happy]
        )
    }

    // MARK: - Mock groups for size testing (3 → 8 members)

    static var mock3: MoodGroup {
        MoodGroup(id: "mock-3", name: "3 Members", type: .bff,
            members: names(3),
            currentMoods: moods(3), moodTimestamps: stamps(3))
    }
    static var mock4: MoodGroup {
        MoodGroup(id: "mock-4", name: "4 Members", type: .bff,
            members: names(4),
            currentMoods: moods(4), moodTimestamps: stamps(4))
    }
    static var mock5: MoodGroup {
        MoodGroup(id: "mock-5", name: "5 Members", type: .bff,
            members: names(5),
            currentMoods: moods(5), moodTimestamps: stamps(5))
    }
    static var mock6: MoodGroup {
        MoodGroup(id: "mock-6", name: "6 Members", type: .family,
            members: names(6),
            currentMoods: moods(6), moodTimestamps: stamps(6))
    }
    static var mock7: MoodGroup {
        MoodGroup(id: "mock-7", name: "7 Members", type: .bff,
            members: names(7),
            currentMoods: moods(7), moodTimestamps: stamps(7))
    }
    static var mock8: MoodGroup {
        MoodGroup(id: "mock-8", name: "8 Members", type: .family,
            members: names(8),
            currentMoods: moods(8), moodTimestamps: stamps(8))
    }

    /// All size-test mock groups in one array — use in GroupService.loadMockGroups()
    static var allMockGroups: [MoodGroup] {
        [mock3, mock4, mock5, mock6, mock7, mock8]
    }

    // MARK: - Mock helpers

    private static let mockNames = ["Alex", "Jordan", "Sam", "Riley", "Casey", "Morgan", "Taylor", "Jamie"]
    private static let mockMoods: [Mood] = [.happy, .angry, .sad, .tired, .excited, .chill, .happy, .sad]
    private static let mockHours = [7, 9, 11, 13, 15, 17, 20, 22]
    private static let mockMins  = [33, 5, 45, 59, 10, 30, 2, 50]

    private static func names(_ n: Int) -> [User] {
        (0..<n).map { User(id: "mock-u\($0)", name: mockNames[$0], phoneNumber: "") }
    }
    private static func moods(_ n: Int) -> [String: Mood] {
        Dictionary(uniqueKeysWithValues: (0..<n).map { ("mock-u\($0)", mockMoods[$0]) })
    }
    private static func stamps(_ n: Int) -> [String: String] {
        let now = Date()
        let cal = Calendar.current
        return Dictionary(uniqueKeysWithValues: (0..<n).map { i in
            let d = cal.date(bySettingHour: mockHours[i], minute: mockMins[i], second: 0, of: now) ?? now
            return ("mock-u\(i)", ISO8601DateFormatter().string(from: d))
        })
    }
}
