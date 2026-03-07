import Foundation
import Supabase

// MARK: - DTOs (match Supabase column names exactly)

struct SupabaseUserRecord: Codable {
    let id: String
    var name: String?
    // phone_hash is write-only via Edge Function — never read back to client

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct SupabaseGroupRecord: Codable {
    let id: String
    let name: String
    let type: String
    let createdBy: String

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case createdBy = "created_by"
    }
}

struct SupabaseGroupMemberRecord: Codable {
    let groupId: String
    let userId: String
    let joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case groupId  = "group_id"
        case userId   = "user_id"
        case joinedAt = "joined_at"
    }
}

struct SupabaseMoodRecord: Codable {
    let userId:    String
    let groupId:   String
    let mood:      String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId    = "user_id"
        case groupId   = "group_id"
        case mood
        case updatedAt = "updated_at"
    }
}

struct SupabaseInvitationRecord: Codable {
    let id: String
    let groupId: String
    let invitedBy: String
    let invitedUserId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case groupId       = "group_id"
        case invitedBy     = "invited_by"
        case invitedUserId = "invited_user_id"
        case status
    }
}

struct SupabaseInvitationInsertRecord: Codable {
    let groupId: String
    let invitedBy: String
    let invitedUserId: String

    enum CodingKeys: String, CodingKey {
        case groupId       = "group_id"
        case invitedBy     = "invited_by"
        case invitedUserId = "invited_user_id"
    }
}

// MARK: - Service

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private var client: SupabaseClient
    /// True once configure(jwt:) has been called with a non-nil JWT.
    /// Used by AppDelegate to guard against calling saveDeviceToken before the
    /// Supabase client has an Authorization header (which would fail RLS with 42501).
    private(set) var hasJWT: Bool = false

    private init() {
        // Start unauthenticated — configure() is called after login
        client = Self.makeClient(jwt: nil)
    }

    /// Reconfigures the underlying client with a fresh JWT (or nil to reset to anon).
    /// Called by AuthService after login / token refresh / sign-out.
    func configure(jwt: String?) {
        hasJWT = jwt != nil
        client = Self.makeClient(jwt: jwt)
    }

    // MARK: - User

    /// Fetch the display name for a user. Returns nil if the name has never been set.
    func fetchUserName(userId: String) async throws -> String? {
        struct NameRecord: Codable { let name: String? }
        let record: NameRecord = try await client
            .from("users")
            .select("name")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        return record.name
    }

    /// Update the display name for the current user.
    func updateName(_ name: String, userId: String) async throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let record = SupabaseUserRecord(id: userId, name: name)
        try await client
            .from("users")
            .update(record)
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Device Tokens

    /// Upserts the APNs device token so the backend can send silent mood-update pushes.
    /// Called from GroupService.fetchGroups() on every app open — fire-and-forget.
    ///
    /// `environment` must match how the app was installed:
    ///   - "sandbox"    → debug builds installed via Xcode
    ///   - "production" → TestFlight or App Store builds
    /// Sending a sandbox token to the production APNs endpoint (or vice-versa)
    /// returns 400 BadDeviceToken and the push is silently dropped.
    func saveDeviceToken(_ token: String, userId: String, environment: String) async {
        struct TokenRecord: Encodable {
            let user_id: String
            let token: String
            let updated_at: String
            let apns_environment: String
        }
        let record = TokenRecord(
            user_id: userId,
            token: token,
            updated_at: ISO8601DateFormatter().string(from: Date()),
            apns_environment: environment
        )
        do {
            try await client
                .from("device_tokens")
                .upsert(record, onConflict: "user_id")
                .execute()
            print("[Supabase] Device token saved (userId=\(userId.prefix(8))… token=\(token.prefix(8))… env=\(environment))")
        } catch {
            print("[Supabase] saveDeviceToken FAILED: \(error) — silent pushes will NOT reach this device")
        }
    }

    // MARK: - Groups

    func leaveGroup(userId: String, groupId: String) async throws {
        // Use .select() so PostgREST returns the deleted rows (Prefer: return=representation).
        // If the RLS policy silently blocks the DELETE, 0 rows come back and we throw —
        // without this check, a blocked DELETE returns HTTP 200 and Swift sees no error.
        let deleted: [SupabaseGroupMemberRecord] = try await client
            .from("group_members")
            .delete()
            .eq("user_id", value: userId)
            .eq("group_id", value: groupId)
            .select()
            .execute()
            .value
        guard !deleted.isEmpty else {
            throw MCError.edgeFunction("Unable to leave the group. Please try again.")
        }
    }

    func renameGroup(id: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try await client
            .from("groups")
            .update(["name": trimmed])
            .eq("id", value: id)
            .execute()
    }

    func createGroup(_ group: MoodGroup, createdBy userId: String) async throws {
        // Validate before touching the network
        guard !group.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MCError.edgeFunction("Group name cannot be empty.")
        }

        let groupRecord = SupabaseGroupRecord(
            id: group.id,
            name: group.name,
            type: group.type.rawValue,
            createdBy: userId
        )
        try await client.from("groups").insert(groupRecord).execute()

        // Only insert the creator — other members will be invited via group_invitations
        let creatorMember = SupabaseGroupMemberRecord(groupId: group.id, userId: userId, joinedAt: nil)
        try await client.from("group_members").insert(creatorMember).execute()
    }

    func fetchGroups(for userId: String) async throws -> [MoodGroup] {
        // 1. My group IDs
        let myMemberships: [SupabaseGroupMemberRecord] = try await client
            .from("group_members")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        let groupIds = myMemberships.map { $0.groupId }
        guard !groupIds.isEmpty else { return [] }

        // 2. Group details
        let groups: [SupabaseGroupRecord] = try await client
            .from("groups")
            .select()
            .in("id", values: groupIds)
            .execute()
            .value

        // 3. All members of those groups
        let allMemberships: [SupabaseGroupMemberRecord] = try await client
            .from("group_members")
            .select()
            .in("group_id", values: groupIds)
            .execute()
            .value

        let allUserIds = Array(Set(allMemberships.map { $0.userId }))

        // 4. User records for members (RLS already scopes this)
        let users: [SupabaseUserRecord] = try await client
            .from("users")
            .select("id, name")   // never select phone_hash
            .in("id", values: allUserIds)
            .execute()
            .value

        let userMap: [String: User] = Dictionary(
            uniqueKeysWithValues: users.map { u in
                (u.id, User(id: u.id, name: u.name ?? "Unknown", phoneNumber: ""))
            }
        )

        // 5. Moods (including updated_at for moodTimestamps)
        let moodRecords: [SupabaseMoodRecord] = try await client
            .from("moods")
            .select("user_id,group_id,mood,updated_at")
            .in("group_id", values: groupIds)
            .execute()
            .value

        // 6. Heart counts for couple groups (nil = query failed, [:] = no hearts yet)
        let coupleIds = groups.filter { $0.type == "couple" }.map { $0.id }
        let heartCountMap: [String: Int]? = await fetchHeartCounts(for: coupleIds)

        // 7. Assemble
        // Build a map of groupId → current user's join timestamp for sorting below.
        let myJoinMap = Dictionary(uniqueKeysWithValues: myMemberships.map { ($0.groupId, $0.joinedAt ?? "") })

        let assembled = groups.map { g in
            let memberIds = allMemberships.filter { $0.groupId == g.id }.map { $0.userId }
            let members   = memberIds.compactMap { userMap[$0] }
            var moods:      [String: Mood]   = [:]
            var timestamps: [String: String] = [:]
            for m in moodRecords where m.groupId == g.id {
                if let mood = Mood(rawValue: m.mood) {
                    moods[m.userId] = mood
                    if let ts = m.updatedAt { timestamps[m.userId] = ts }
                }
            }
            return MoodGroup(
                id: g.id,
                name: g.name,
                type: GroupType(rawValue: g.type) ?? .bff,
                createdBy: g.createdBy,
                members: members,
                currentMoods: moods,
                moodTimestamps: timestamps,
                // heartCountMap is nil when the query failed → 0 so GroupService
                // can detect the failure case via "fetched == 0, current > 0".
                heartCount: heartCountMap?[g.id] ?? 0
            )
        }

        // Sort newest-joined first (ISO-8601 strings sort lexicographically in
        // chronological order, so descending string comparison gives newest first).
        return assembled.sorted { (myJoinMap[$0.id] ?? "") > (myJoinMap[$1.id] ?? "") }
    }

    // MARK: - Invitations

    func sendInvitations(_ userIds: [String], toGroup groupId: String, invitedBy inviterId: String) async throws {
        let records = userIds.map { userId in
            SupabaseInvitationInsertRecord(groupId: groupId, invitedBy: inviterId, invitedUserId: userId)
        }
        try await client
            .from("group_invitations")
            .upsert(records, onConflict: "group_id,invited_user_id")
            .execute()
    }

    func fetchPendingInvitations(for userId: String) async throws -> [GroupInvitationDetail] {
        // 1. Pending invitations for this user
        let invitations: [SupabaseInvitationRecord] = try await client
            .from("group_invitations")
            .select()
            .eq("invited_user_id", value: userId)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value

        guard !invitations.isEmpty else { return [] }

        let groupIds   = invitations.map { $0.groupId }
        let inviterIds = Array(Set(invitations.map { $0.invitedBy }))

        // 2+3. Fetch group details and inviter names in parallel
        async let groupsFetch: [SupabaseGroupRecord] = client
            .from("groups")
            .select()
            .in("id", values: groupIds)
            .execute()
            .value

        async let invitersFetch: [SupabaseUserRecord] = client
            .from("users")
            .select("id, name")
            .in("id", values: inviterIds)
            .execute()
            .value

        let groups  = try await groupsFetch
        let inviters = try await invitersFetch

        // 4. Assemble
        let groupMap    = Dictionary(uniqueKeysWithValues: groups.map   { ($0.id, $0) })
        let inviterMap  = Dictionary(uniqueKeysWithValues: inviters.map { ($0.id, $0.name ?? "Unknown") })

        return invitations.compactMap { inv in
            guard let group = groupMap[inv.groupId] else { return nil }
            // Prefer the name saved in the recipient's device contacts over the in-app name
            let resolvedName = ContactsService.contactDisplayName(forUserId: inv.invitedBy)
                ?? inviterMap[inv.invitedBy]
                ?? "Unknown"
            return GroupInvitationDetail(
                id: inv.id,
                groupId: inv.groupId,
                groupName: group.name,
                groupType: GroupType(rawValue: group.type) ?? .bff,
                inviterName: resolvedName,
                inviterId: inv.invitedBy
            )
        }
    }

    func searchUsers(query: String) async throws -> [User] {
        struct SearchResult: Codable {
            let id: String
            let name: String?
        }
        let results: [SearchResult] = try await client
            .rpc("search_users", params: ["query": query])
            .execute()
            .value
        return results.map { User(id: $0.id, name: $0.name ?? "Unknown", phoneNumber: "") }
    }

    func acceptInvitation(_ id: String) async throws {
        try await client
            .rpc("accept_group_invitation", params: ["p_invitation_id": id])
            .execute()
    }

    func rejectInvitation(_ id: String) async throws {
        try await client
            .rpc("reject_group_invitation", params: ["p_invitation_id": id])
            .execute()
    }

    // MARK: - Hearts

    /// Calls the `increment_heart` RPC and returns the new authoritative count.
    func incrementHeart(groupId: String) async throws -> Int {
        try await client
            .rpc("increment_heart", params: ["p_group_id": groupId])
            .execute()
            .value
    }

    /// Fetches heart counts for the given couple-group IDs.
    /// Returns nil on query failure so callers can distinguish "no hearts yet"
    /// (empty dict) from "query failed" (nil) and avoid resetting the display.
    func fetchHeartCounts(for groupIds: [String]) async -> [String: Int]? {
        guard !groupIds.isEmpty else { return [:] }
        struct HeartRecord: Codable {
            let groupId: String
            let count: Int
            enum CodingKeys: String, CodingKey {
                case groupId = "group_id"
                case count
            }
        }
        do {
            let records: [HeartRecord] = try await client
                .from("couple_hearts")
                .select("group_id,count")
                .in("group_id", values: groupIds)
                .execute()
                .value
            return Dictionary(uniqueKeysWithValues: records.map { ($0.groupId, $0.count) })
        } catch {
            print("[Supabase] fetchHeartCounts error: \(error)")
            return nil  // nil = query failed, distinct from [:] = no hearts yet
        }
    }

    // MARK: - Moods

    func updateMood(_ mood: Mood, userId: String, groupId: String) async throws {
        struct MoodUpsert: Encodable {
            let user_id:    String
            let group_id:   String
            let mood:       String
            let updated_at: String
        }
        let record = MoodUpsert(
            user_id: userId,
            group_id: groupId,
            mood: mood.rawValue,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        try await client
            .from("moods")
            .upsert(record, onConflict: "user_id,group_id")
            .execute()
    }

    // MARK: - Private

    private static func makeClient(jwt: String?) -> SupabaseClient {
        var headers: [String: String] = [:]
        if let jwt {
            headers["Authorization"] = "Bearer \(jwt)"
        }
        return SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                global: SupabaseClientOptions.GlobalOptions(headers: headers)
            )
        )
    }
}

// MARK: - Array Extension

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
