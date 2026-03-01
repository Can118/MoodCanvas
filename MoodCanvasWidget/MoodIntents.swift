import AppIntents
import WidgetKit

// MARK: - Group Entity (drives the widget configuration picker)

struct GroupAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Group"
    static var defaultQuery = GroupQuery()

    var id: String
    var name: String
    var typeName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: typeName)
        )
    }
}

/// Loads groups from AppGroup cache, merging in any debug mock groups written by loadMockGroups().
/// Debug groups are stored under a separate key so fetchGroups() never overwrites them.
func mergedGroups() -> [MoodGroup] {
    let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
    var groups: [MoodGroup] = []
    if let data = defaults?.data(forKey: "widget_groups"),
       let decoded = try? JSONDecoder().decode([MoodGroup].self, from: data) {
        groups = decoded
    }
#if DEBUG
    if let data = defaults?.data(forKey: "widget_groups_debug"),
       let debugGroups = try? JSONDecoder().decode([MoodGroup].self, from: data) {
        let existingIds = Set(groups.map { $0.id })
        groups += debugGroups.filter { !existingIds.contains($0.id) }
    }
#endif
    return groups
}

struct GroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroupAppEntity] {
        loadEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GroupAppEntity] {
        loadEntities()
    }

    private func loadEntities() -> [GroupAppEntity] {
        return mergedGroups().map { GroupAppEntity(id: $0.id, name: $0.name, typeName: $0.type.displayName) }
    }
}

// Query that surfaces only couple groups
struct CoupleGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroupAppEntity] {
        loadEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [GroupAppEntity] { loadEntities() }
    private func loadEntities() -> [GroupAppEntity] {
        mergedGroups()
            .filter { $0.type == .couple }
            .map { GroupAppEntity(id: $0.id, name: $0.name, typeName: $0.type.displayName) }
    }
}

// Query that surfaces only BFF + family groups with 4+ members (4×4 large widget only)
// Groups with ≤ 3 members should use the 4×2 medium widget instead.
struct BFFGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroupAppEntity] {
        loadEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [GroupAppEntity] { loadEntities() }
    private func loadEntities() -> [GroupAppEntity] {
        mergedGroups()
            .filter { ($0.type == .bff || $0.type == .family) && $0.members.count >= 4 }
            .map { GroupAppEntity(id: $0.id, name: $0.name, typeName: $0.type.displayName) }
    }
}

// Query that surfaces only BFF + family groups with ≤ 3 members (4×2 medium widget only)
// Groups with 4+ members are intentionally hidden — they should use the 4×4 large widget.
struct BFFMediumGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroupAppEntity] {
        loadEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [GroupAppEntity] { loadEntities() }
    private func loadEntities() -> [GroupAppEntity] {
        mergedGroups()
            .filter { ($0.type == .bff || $0.type == .family) && $0.members.count <= 3 }
            .map { GroupAppEntity(id: $0.id, name: $0.name, typeName: $0.type.displayName) }
    }
}

// MARK: - Widget Configuration Intents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description = IntentDescription("Choose which group's mood canvas to display.")

    @Parameter(title: "Group", optionsProvider: GroupQuery())
    var group: GroupAppEntity?
}

struct CoupleConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Couple Group"
    static var description = IntentDescription("Choose your couple group.")

    @Parameter(title: "Group", optionsProvider: CoupleGroupQuery())
    var group: GroupAppEntity?
}

// Used by the 4×4 large widget — shows all BFF + family groups
struct BFFConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description = IntentDescription("Choose your BFF or Family group.")

    @Parameter(title: "Group", optionsProvider: BFFGroupQuery())
    var group: GroupAppEntity?
}

// Used by the 4×2 medium widget — only shows groups with ≤ 3 members
struct BFFMediumConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description = IntentDescription("Choose your BFF or Family group (up to 3 members).")

    @Parameter(title: "Group", optionsProvider: BFFMediumGroupQuery())
    var group: GroupAppEntity?
}

// MARK: - Interactive Mood Button Intent

struct SetMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Mood"
    static var description = IntentDescription("Update your mood in a group.")

    // Encoded as "groupId|moodRawValue" for simplicity
    @Parameter(title: "Payload")
    var payload: String

    func perform() async throws -> some IntentResult {
        let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .result() }
        let (groupId, moodRaw) = (parts[0], parts[1])
        guard let mood = Mood(rawValue: moodRaw) else { return .result() }

        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)

        // Require the current user's ID — written by the main app on fetchGroups()
        guard let userId = defaults?.string(forKey: "widget_current_user_id") else {
            print("[Widget] SetMoodIntent: no widget_current_user_id in AppGroup — open the app first")
            return .result()
        }

        print("[Widget] SetMoodIntent: mood=\(moodRaw) groupId=\(groupId) userId=\(userId.prefix(8))…")

        if defaults?.string(forKey: "widget_jwt") == nil {
            print("[Widget] SetMoodIntent: WARNING — widget_jwt is missing from AppGroup; open the main app")
        }

        // Stamp the current time as the mood timestamp so the widget shows it instantly
        let nowISO = ISO8601DateFormatter().string(from: Date())

        // ── Step 1: Update the cached groups immediately ──────────────────────
        // The cache update happens BEFORE any network call so that when WidgetKit
        // calls timeline() after perform() returns, the fast path finds fresh data
        // and the local widget re-renders without waiting for Supabase.
        if let data = defaults?.data(forKey: "widget_groups"),
           var groups = try? JSONDecoder().decode([MoodGroup].self, from: data),
           let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].currentMoods[userId] = mood
            groups[idx].moodTimestamps[userId] = nowISO
            if let updated = try? JSONEncoder().encode(groups) {
                defaults?.set(updated, forKey: "widget_groups")
            }
        }

        // ── Step 2: Write pending keys as a retry fallback ────────────────────
        // If the Supabase sync below fails (network error, expired JWT, etc.),
        // processPendingWidgetMoods() in the main app will retry on next open.
        defaults?.set(moodRaw, forKey: "widgetMood_\(groupId)")
        defaults?.set(nowISO,  forKey: "widgetMoodTime_\(groupId)_\(userId)")
        defaults?.synchronize()

        // ── Step 3: Sync to Supabase INSIDE perform() ─────────────────────────
        // Previously a Task.detached was used so perform() returned in < 1 ms.
        // Problem: the widget extension process is terminated by iOS immediately
        // after perform() returns — the detached task was killed before syncMood
        // completed, so notifyMoodUpdate (and the APNs push to other devices)
        // was never called. Cross-device widget updates silently broke.
        //
        // Awaiting here keeps the extension process alive for the duration of
        // the network call. The cache update in Step 1 ensures timeline() uses
        // the fast path and the local widget still renders quickly after return.
        let synced = await WidgetDataService.syncMood(mood, userId: userId, groupId: groupId)

        // ── Step 4: Clear pending keys on success ─────────────────────────────
        // Once Supabase confirms the write, remove the pending keys so the next
        // timeline() call takes the slow path (Supabase fetch) and picks up
        // authoritative data — including other members' mood changes.
        // If sync failed the pending keys remain so the fallback retry can fire.
        if synced {
            defaults?.removeObject(forKey: "widgetMood_\(groupId)")
            defaults?.removeObject(forKey: "widgetMoodTime_\(groupId)_\(userId)")
            defaults?.synchronize()
        }

        // ── Step 5: Reload timelines ──────────────────────────────────────────
        // Synced → slow path fetches authoritative Supabase data.
        // Failed → fast path re-applies the pending keys over the cached data.
        WidgetCenter.shared.reloadAllTimelines()

        print("[Widget] SetMoodIntent: \(synced ? "sync OK — push sent to other devices" : "sync FAILED — app will retry on next open")")
        return .result()
    }
}

// MARK: - Interactive Heart Button Intent

struct SendHeartIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Heart"
    static var description = IntentDescription("Send a heart to your partner.")

    @Parameter(title: "Group ID")
    var groupId: String

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        print("[Widget] SendHeartIntent: groupId=\(groupId)")

        // 1. Optimistically update the cached groups (heartCount + 1)
        var optimisticCount = 0
        if let data = defaults?.data(forKey: "widget_groups"),
           var groups = try? JSONDecoder().decode([MoodGroup].self, from: data),
           let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].heartCount += 1
            optimisticCount = groups[idx].heartCount
            if let updated = try? JSONEncoder().encode(groups) {
                defaults?.set(updated, forKey: "widget_groups")
            }
        }
        // Write pending key so timeline() fast-path knows to skip the Supabase fetch
        defaults?.set(optimisticCount, forKey: "widgetHeartCount_\(groupId)")
        defaults?.synchronize()

        // Return immediately — WidgetKit re-renders from the already-updated cache
        // in < 1 ms (fast path in timeline() detects the pending key and skips the
        // network round-trip). The detached task handles the Supabase RPC in the
        // background and triggers a second reload with the authoritative count.
        let capturedGroupId   = groupId
        let capturedOptimistic = optimisticCount
        Task.detached {
            let authCount  = await WidgetDataService.incrementHeart(groupId: capturedGroupId)
            let bg         = UserDefaults(suiteName: AppGroupConstants.suiteName)
            if authCount > 0 {
                if let data = bg?.data(forKey: "widget_groups"),
                   var groups = try? JSONDecoder().decode([MoodGroup].self, from: data),
                   let idx   = groups.firstIndex(where: { $0.id == capturedGroupId }) {
                    groups[idx].heartCount = max(authCount, capturedOptimistic)
                    if let updated = try? JSONEncoder().encode(groups) {
                        bg?.set(updated, forKey: "widget_groups")
                    }
                }
                bg?.removeObject(forKey: "widgetHeartCount_\(capturedGroupId)")
                bg?.synchronize()
            }
            // Trigger authoritative reload — timeline() will take the slow path now
            // that the pending key is cleared and Supabase has the confirmed count.
            WidgetCenter.shared.reloadAllTimelines()
            print("[Widget] SendHeartIntent background: authCount=\(authCount)")
        }
        print("[Widget] SendHeartIntent: done (optimistic=\(optimisticCount), RPC in background)")
        return .result()
    }
}
