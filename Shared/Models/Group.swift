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
        heartCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdBy = createdBy
        self.members = members
        self.currentMoods = currentMoods
        self.heartCount = heartCount
    }

    // Custom decoder so that JSON lacking "heartCount" (e.g. cached widget data
    // written before this feature was added) decodes to 0 instead of throwing.
    enum CodingKeys: String, CodingKey {
        case id, name, type, createdBy, members, currentMoods, heartCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(String.self,          forKey: .id)
        name         = try c.decode(String.self,          forKey: .name)
        type         = try c.decode(GroupType.self,       forKey: .type)
        createdBy    = try c.decode(String.self,          forKey: .createdBy)
        members      = try c.decode([User].self,          forKey: .members)
        currentMoods = try c.decode([String: Mood].self,  forKey: .currentMoods)
        heartCount   = try c.decodeIfPresent(Int.self,    forKey: .heartCount) ?? 0
    }
}

// MARK: - Preview Data

extension MoodGroup {
    static var preview: MoodGroup {
        MoodGroup(
            id: "preview",
            name: "Squad",
            type: .bff,
            members: [
                User(id: "1", name: "Alex", phoneNumber: "+11234567890"),
                User(id: "2", name: "Jordan", phoneNumber: "+10987654321"),
                User(id: "3", name: "Sam", phoneNumber: "+11112223333"),
            ],
            currentMoods: ["1": .happy, "2": .chill, "3": .excited]
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
}
