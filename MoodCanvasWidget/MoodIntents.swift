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

struct GroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GroupAppEntity] {
        loadEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GroupAppEntity] {
        loadEntities()
    }

    private func loadEntities() -> [GroupAppEntity] {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard
            let data   = defaults?.data(forKey: "widget_groups"),
            let groups = try? JSONDecoder().decode([MoodGroup].self, from: data)
        else { return [] }
        return groups.map { GroupAppEntity(id: $0.id, name: $0.name, typeName: $0.type.displayName) }
    }
}

// MARK: - Widget Configuration Intent

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description = IntentDescription("Choose which group's mood canvas to display.")

    @Parameter(title: "Group", optionsProvider: GroupQuery())
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

        // Check that the widget JWT exists before attempting sync (gives early diagnostic)
        if defaults?.string(forKey: "widget_jwt") == nil {
            print("[Widget] SetMoodIntent: WARNING — widget_jwt is missing from AppGroup; open the main app")
        }

        // Update the cached groups JSON so the widget immediately shows the new mood
        if let data = defaults?.data(forKey: "widget_groups"),
           var groups = try? JSONDecoder().decode([MoodGroup].self, from: data),
           let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].currentMoods[userId] = mood
            if let updated = try? JSONEncoder().encode(groups) {
                defaults?.set(updated, forKey: "widget_groups")
            }
        }

        // Keep as a pending key — used as fallback if the network call below fails,
        // and also consumed by processPendingWidgetMoods() when the app opens.
        defaults?.set(moodRaw, forKey: "widgetMood_\(groupId)")
        defaults?.synchronize()

        // Fire-and-forget: sync to Supabase in a detached task so perform() returns
        // in < 1 ms. WidgetKit re-renders immediately from the already-updated cache.
        // The detached task sends the APNs push to the partner and then triggers a
        // second authoritative reload once Supabase confirms the write.
        let capturedMood     = mood
        let capturedUserId   = userId
        let capturedGroupId  = groupId
        Task.detached {
            await WidgetDataService.syncMood(capturedMood, userId: capturedUserId, groupId: capturedGroupId)
            WidgetCenter.shared.reloadAllTimelines()
        }
        print("[Widget] SetMoodIntent: done (background sync started)")
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
