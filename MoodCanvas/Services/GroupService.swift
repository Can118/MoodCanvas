import Foundation
import SwiftUI
import WidgetKit
import FirebaseAuth

@MainActor
class GroupService: ObservableObject {
    @Published var groups: [MoodGroup] = []
    @Published var pendingInvitations: [GroupInvitationDetail] = []
    @Published var isLoading = false
    /// Cached heart counts for couple groups — used for real-time optimistic updates in the app.
    @Published var heartCounts: [String: Int] = [:]
    /// Groups that currently have an in-flight sendHeart RPC call.
    /// While a group ID is in this set, fetchGroups uses max() to avoid flicker.
    /// Once the RPC completes (success or failure), the ID is removed and
    /// fetchGroups trusts the authoritative Supabase value.
    private var pendingHeartGroupIds: Set<String> = []

    init() {
        // Pre-populate from the AppGroup cache written by the last session.
        // This lets HomeView render real group data instantly on cold launch
        // instead of showing the empty state while waiting for the network fetch.
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        if let data = defaults?.data(forKey: "widget_groups"),
           let cached = try? JSONDecoder().decode([MoodGroup].self, from: data) {
            groups = cached
            // Seed heartCounts from cache so couple widgets are consistent immediately
            for g in cached where g.type == .couple {
                heartCounts[g.id] = g.heartCount
            }
        }
    }

    // MARK: - Fetch

    func fetchGroups() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        // Store the current user ID in App Group so widget intents know who is logged in
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.set(userId, forKey: "widget_current_user_id")

        do {
            var fetchedGroups = try await SupabaseService.shared.fetchGroups(for: userId)

            // Re-apply any pending in-flight mood updates so a concurrent fetchGroups()
            // cannot revert an optimistic UI change before the Supabase write completes.
            // widgetMood_* is set at the START of updateMood() and cleared only AFTER
            // the Supabase write confirms — its presence means a write is still in flight.
            let sharedDefaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
            for idx in fetchedGroups.indices {
                let moodKey = "widgetMood_\(fetchedGroups[idx].id)"
                if let pendingMoodRaw = sharedDefaults?.string(forKey: moodKey),
                   let pendingMood = Mood(rawValue: pendingMoodRaw) {
                    fetchedGroups[idx].currentMoods[userId] = pendingMood
                }
            }
            groups = fetchedGroups

            // Heart count reconciliation for couple groups — three cases:
            //
            // Case 1 — fetched == 0:
            //   fetchHeartCounts failed silently (RLS error, network blip) OR
            //   the couple has never sent a heart yet. Either way, never reset
            //   the display to 0; preserve whatever is in memory.
            //   A genuine zero is safe because current would also be 0.
            //
            // Case 2 — fetched > 0, RPC in flight (pendingHeartGroupIds):
            //   Our own increment_heart write hasn't committed yet, so Supabase
            //   is one tap behind. Take max to prevent a visible downward flicker.
            //
            // Case 3 — fetched > 0, no pending RPC:
            //   Supabase is fully authoritative. Trust it directly.
            //   This also corrects stale-high local counts (divergence fix):
            //   if local has 16 from pre-fix optimistic accumulation and Supabase
            //   has 3 (real), we set 3 so both devices converge to the same value.
            //   Partner taps are captured here too: fetched > current → take fetched.
            for idx in groups.indices where groups[idx].type == .couple {
                let groupId = groups[idx].id
                let fetched = groups[idx].heartCount
                let current = heartCounts[groupId] ?? 0

                let resolved: Int
                if fetched == 0 {
                    resolved = current                                   // Case 1
                } else if pendingHeartGroupIds.contains(groupId) {
                    resolved = max(fetched, current)                     // Case 2
                } else {
                    resolved = fetched                                   // Case 3
                }

                groups[idx].heartCount = resolved
                heartCounts[groupId]   = resolved
            }
            writeGroupsToSharedContainer()

            // Sync the freshest Keychain JWT to AppGroup so the widget always has
            // a valid token after every app-open — belt-and-suspenders alongside
            // AuthService.restoreSession() which also writes to AppGroup at launch.
            // This covers the case where the JWT was refreshed between app opens
            // but the widget extension still holds an older copy.
            if let freshJWT = KeychainService.load(.supabaseJWT) {
                sharedDefaults?.set(freshJWT, forKey: "widget_jwt")
            }

            // NOTE: reloadAllTimelines() is intentionally NOT called here.
            // fetchGroups() runs every 8-10 s from the HomeView and GroupDetailView
            // polling timers. WidgetKit allocates a finite daily refresh budget
            // (~40-70 reloads/widget/day); calling reloadAllTimelines() at polling
            // frequency exhausts it in minutes. Once the budget is gone, WidgetKit
            // ignores ALL programmatic reloads — including the critical one in
            // handleMoodUpdatePush() — so the partner's mood update never appears.
            // The widget refreshes through the correct channels instead:
            //   • updateMood()     — two reloads: optimistic pre-write + authoritative post-write
            //   • handleMoodUpdatePush() — one reload per incoming silent push
            //   • SetMoodIntent   — always honored (user-interactive, budget-exempt)
            //   • WidgetKit scheduled policy — 1-minute fallback on real devices

            // Register/refresh device token so this user can receive mood-update pushes.
            // Note: AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken also saves
            // the token immediately when the APNs callback fires; this call handles the
            // race-condition case where fetchGroups() runs before that callback arrives.
            if let token = KeychainService.load(.apnsToken) {
                #if DEBUG
                let apnsEnvironment = "sandbox"
                #else
                let apnsEnvironment = "production"
                #endif
                await SupabaseService.shared.saveDeviceToken(token, userId: userId, environment: apnsEnvironment)
            } else {
                print("[Groups] fetchGroups: APNs token not in Keychain yet — APNs registration may still be pending")
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

    /// Creates a group and sends in-app invitations to existing Moodi members.
    /// Returns the new group's ID on success, or nil on failure.
    @discardableResult
    func createGroup(name: String, type: GroupType, members: [User] = []) async -> String? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }

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
                // Push each invited user so their app wakes and shows the invitation
                // card in real-time — without this they must hard-close and reopen.
                for invitedId in nonCreatorIds {
                    await EdgeFunctionService.notifyInvited(groupId: newGroup.id, invitedUserId: invitedId)
                }
            }
            return newGroup.id
        } catch {
            print("[Groups] createGroup error: \(error)")
            return nil
        }
    }

    // MARK: - Leave

    func leaveGroup(id: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw MCError.noSession
        }
        try await SupabaseService.shared.leaveGroup(userId: userId, groupId: id)
        groups.removeAll { $0.id == id }
        writeGroupsToSharedContainer()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Rename

    func renameGroup(id: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = trimmed
        writeGroupsToSharedContainer()
        WidgetCenter.shared.reloadAllTimelines()
        do {
            try await SupabaseService.shared.renameGroup(id: id, name: trimmed)
        } catch {
            print("[Groups] renameGroup error: \(error)")
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
            // Push each invited user so their invitation card appears immediately
            for user in users {
                await EdgeFunctionService.notifyInvited(groupId: groupId, invitedUserId: user.id)
            }
        } catch {
            print("[Groups] sendInvitations error: \(error)")
        }
    }

    func respondToInvitation(_ id: String, accept: Bool) async {
        do {
            if accept {
                // Capture the group ID now — the invitation row disappears after acceptance
                // and pendingInvitations will be cleared by fetchPendingInvitations() below.
                let groupId = pendingInvitations.first(where: { $0.id == id })?.groupId
                try await SupabaseService.shared.acceptInvitation(id)
                // Notify all existing group members that someone joined so their apps
                // call fetchGroups() and see the new member without needing a hard-close.
                // The acceptor (this user) is already in group_members at this point,
                // so send-mood-push's membership check passes and they are excluded
                // from the push (they're the one who changed state — they don't need it).
                if let groupId, let userId = Auth.auth().currentUser?.uid {
                    await WidgetDataService.notifyMoodUpdate(groupId: groupId, userId: userId)
                }
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
        // Wrap the optimistic update in withAnimation so SwiftUI has an active
        // animation context when it re-renders — this is what makes .transition()
        // + .id() on the mood image actually play instead of snapping instantly.
        let nowISO = ISO8601DateFormatter().string(from: Date())
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            groups[index].currentMoods[userId] = mood
            groups[index].moodTimestamps[userId] = nowISO
        }

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
            // Reload #2 — triggers the widget's slow path (no pending keys → Supabase
            // fetch) so the widget renders authoritative data that includes the
            // partner's latest mood, not just the locally-cached optimistic snapshot
            // from Reload #1 above. This is budget-safe: it fires at most once per
            // user mood tap, not on every polling cycle.
            WidgetCenter.shared.reloadAllTimelines()
            // Notify other group members via silent APNs push so their widgets reload immediately
            await WidgetDataService.notifyMoodUpdate(groupId: groupId, userId: userId)
        } catch {
            print("[Groups] updateMood error: \(error)")
        }
    }

    // MARK: - Hearts

    /// Optimistically increments the heart count for a couple group, then confirms with Supabase.
    func sendHeart(groupId: String) async {
        // Mark RPC as in-flight so fetchGroups() uses max() during the write.
        pendingHeartGroupIds.insert(groupId)

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
        }

        // RPC complete — fetchGroups() will now trust Supabase directly.
        pendingHeartGroupIds.remove(groupId)

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

    // MARK: - Debug

#if DEBUG
    /// Replaces the live group list with mock groups covering every member-count size (3–8).
    /// Tap the flask button in HomeView to invoke this during development.
    func loadMockGroups() {
        groups = MoodGroup.allMockGroups
        writeGroupsToSharedContainer()
        // Persist mocks to a separate key so fetchGroups() never overwrites them.
        // The widget queries merge this key with widget_groups, so mock groups
        // survive the fetchGroups() call that fires when the app re-enters foreground.
        if let data = try? JSONEncoder().encode(MoodGroup.allMockGroups) {
            let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
            defaults?.set(data, forKey: "widget_groups_debug")
            defaults?.synchronize()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearMockGroups() {
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.removeObject(forKey: "widget_groups_debug")
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.synchronize()
    }
#endif

    // MARK: - Private

    private func writeGroupsToSharedContainer() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        defaults?.set(data, forKey: "widget_groups")
        defaults?.synchronize()
    }
}
