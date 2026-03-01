import Foundation

// MARK: - Domain Model

struct GroupInvitationDetail: Identifiable, Equatable {
    let id: String
    let groupId: String
    let groupName: String
    let groupType: GroupType
    /// In-app display name set by the inviter during onboarding.
    let inviterName: String
    /// The inviter's Supabase user ID — used to look up their contact-saved name locally.
    let inviterId: String
}
