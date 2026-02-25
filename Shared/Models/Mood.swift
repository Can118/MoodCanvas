import Foundation

enum Mood: String, CaseIterable, Codable, Identifiable {
    case happy
    case sad
    case excited
    case chill
    case tired
    case angry

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .happy:   return "😊"
        case .sad:     return "😢"
        case .excited: return "🤩"
        case .chill:   return "😌"
        case .tired:   return "😴"
        case .angry:   return "😠"
        }
    }

    var label: String {
        switch self {
        case .happy:   return "Happy"
        case .sad:     return "Sad"
        case .excited: return "Excited"
        case .chill:   return "Chill"
        case .tired:   return "Tired"
        case .angry:   return "Angry"
        }
    }
}
