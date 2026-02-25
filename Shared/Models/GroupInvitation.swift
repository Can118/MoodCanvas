import Foundation

// MARK: - Domain Model

struct GroupInvitationDetail: Identifiable, Equatable {
    let id: String
    let groupId: String
    let groupName: String
    let groupType: GroupType
    let inviterName: String
}
