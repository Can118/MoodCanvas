import Foundation
import WidgetKit
import FirebaseAuth

@MainActor
class GroupService: ObservableObject {
    @Published var groups: [MoodGroup] = []
    @Published var pendingInvitations: [GroupInvitationDetail] = []
    @Published var isLoading = false
    /// Cached heart counts for couple groups — used for real-time optimistic updates in the app.
    @Published var heartCounts: [String: Int] = [:]

    // MARK: - Fetch

    func fetchGroups() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        // Store the current user ID in App Group so widget intents know who is logged in
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.set(userId, forKey: "widget_current_user_id")

        do {
            groups = try await SupabaseService.shared.fetchGroups(for: userId)
            // Populate heartCounts for couple groups, taking the max of the Supabase
            // value and whatever is already in memory. Since hearts only ever increment,
            // a lower fetched value means the couple_hearts query failed silently —
            // we must never let a bad fetch reset a count the user can already see.
            for idx in groups.indices where groups[idx].type == .couple {
                let fetched = groups[idx].heartCount
                let current = heartCounts[groups[idx].id] ?? 0
                let best    = max(fetched, current)
                groups[idx].heartCount   = best
                heartCounts[groups[idx].id] = best
            }
            writeGroupsToSharedContainer()
            WidgetCenter.shared.reloadAllTimelines()
            // Register/refresh device token so this user can receive mood-update pushes
            if let token = UserDefaults.standard.string(forKey: "apns_device_token") {
                await SupabaseService.shared.saveDeviceToken(token, userId: userId)
            } else {
                print("[Groups] fetchGroups: apns_device_token not in UserDefaults yet — APNs registration may still be pending")
            }
        } catch {
            print("[Groups] fetchGroups error: \(error)")
        }
    }

    func fetchPendingInvitations() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            pendingInvitations = try await SupabaseService.shared.fetchPendingInvitations(for: userId)
        } catch {
            print("[Groups] fetchPendingInvitations error: \(error)")
        }
    }

    // MARK: - Create

    func createGroup(name: String, type: GroupType, members: [User] = []) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Only the creator is added immediately; selected members receive invitations
        let newGroup = MoodGroup(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            members: []
        )

        do {
            try await SupabaseService.shared.createGroup(newGroup, createdBy: userId)
            groups.append(newGroup)

            // Send invitations to selected non-creator members
            let nonCreatorIds = members.map { $0.id }.filter { $0 != userId }
            if !nonCreatorIds.isEmpty {
                try await SupabaseService.shared.sendInvitations(
                    nonCreatorIds,
                    toGroup: newGroup.id,
                    invitedBy: userId
                )
            }
        } catch {
            print("[Groups] createGroup error: \(error)")
        }
    }

    // MARK: - Invitations

    func sendInvitations(_ users: [User], toGroup groupId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            try await SupabaseService.shared.sendInvitations(
                users.map { $0.id },
                toGroup: groupId,
                invitedBy: userId
            )
        } catch {
            print("[Groups] sendInvitations error: \(error)")
        }
    }

    func respondToInvitation(_ id: String, accept: Bool) async {
        do {
            if accept {
                try await SupabaseService.shared.acceptInvitation(id)
            } else {
                try await SupabaseService.shared.rejectInvitation(id)
            }
            await fetchGroups()
            await fetchPendingInvitations()
        } catch {
            print("[Groups] respondToInvitation error: \(error)")
        }
    }

    // MARK: - Update Mood

    func updateMood(_ mood: Mood, for userId: String, in groupId: String) async {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].currentMoods[userId] = mood

        // Stamp an optimistic timestamp so writeGroupsToSharedContainer()
        // writes a non-empty moodTimestamps to the widget cache, making the
        // BFF widget show the time immediately without waiting for a Supabase round-trip.
        let nowISO = ISO8601DateFormatter().string(from: Date())
        groups[index].moodTimestamps[userId] = nowISO

        // Write full groups snapshot to App Group so widget shows live data.
        // Also set the pending widgetMood/widgetMoodTime keys so the widget's
        // timeline() re-applies the correct mood + timestamp even if fetchGroups()
        // returns stale Supabase data (the write below is in-flight when timeline() is called).
        let sharedDefaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        sharedDefaults?.set(mood.rawValue, forKey: "widgetMood_\(groupId)")
        sharedDefaults?.set(nowISO,        forKey: "widgetMoodTime_\(groupId)_\(userId)")
        writeGroupsToSharedContainer()
        WidgetCenter.shared.reloadAllTimelines()

        do {
            try await SupabaseService.shared.updateMood(mood, userId: userId, groupId: groupId)
            // Supabase write is confirmed — clear pending keys so processPendingWidgetMoods()
            // doesn't treat this as an un-synced widget tap and fire a duplicate push.
            sharedDefaults?.removeObject(forKey: "widgetMood_\(groupId)")
            sharedDefaults?.removeObject(forKey: "widgetMoodTime_\(groupId)_\(userId)")
            // Sync the freshest Supabase JWT from Keychain into the App Group so that
            // the notifyMoodUpdate call below always has a valid token (the AppGroup
            // copy can go stale after the 1-hour JWT TTL).
            if let freshJWT = KeychainService.load(.supabaseJWT) {
                sharedDefaults?.set(freshJWT, forKey: "widget_jwt")
            }
            // Notify other group members via silent APNs push so their widgets reload immediately
            await WidgetDataService.notifyMoodUpdate(groupId: groupId, userId: userId)
        } catch {
            print("[Groups] updateMood error: \(error)")
        }
    }

    // MARK: - Hearts

    /// Optimistically increments the heart count for a couple group, then confirms with Supabase.
    func sendHeart(groupId: String) async {
        // 1. Optimistic update
        heartCounts[groupId, default: 0] += 1
        let optimistic = heartCounts[groupId]!
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].heartCount = optimistic
        }
        writeGroupsToSharedContainer()
        WidgetCenter.shared.reloadAllTimelines()

        // 2. Supabase RPC — returns authoritative count
        do {
            let authCount = try await SupabaseService.shared.incrementHeart(groupId: groupId)
            heartCounts[groupId] = authCount
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx].heartCount = authCount
            }
        } catch {
            print("[Groups] sendHeart error: \(error)")
            // Revert the optimistic increment on failure
            let reverted = max(0, optimistic - 1)
            heartCounts[groupId] = reverted
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx].heartCount = reverted
            }
        }

        writeGroupsToSharedContainer()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Widget Mood Sync

    /// Checks for mood taps made from the widget while the app was closed,
    /// then syncs them to the backend. Call this when the app comes to the foreground.
    func processPendingWidgetMoods(currentUserId: String?) async {
        guard let userId = currentUserId else { return }
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        for group in groups {
            let moodKey = "widgetMood_\(group.id)"
            guard let moodRaw = defaults?.string(forKey: moodKey),
                  let mood = Mood(rawValue: moodRaw) else { continue }
            // Clear both mood and timestamp keys — leaving the timestamp key behind
            // would cause timeline()'s slow path to re-apply a stale optimistic
            // timestamp on top of the authoritative Supabase data.
            defaults?.removeObject(forKey: moodKey)
            defaults?.removeObject(forKey: "widgetMoodTime_\(group.id)_\(userId)")
            await updateMood(mood, for: userId, in: group.id)
        }
    }

    // MARK: - Private

    private func writeGroupsToSharedContainer() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        defaults?.set(data, forKey: "widget_groups")
    }
}
