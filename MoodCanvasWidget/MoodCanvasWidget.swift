import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct MoodEntry: TimelineEntry {
    let date: Date
    let group: MoodGroup
    let configuration: ConfigurationAppIntent
    /// The authenticated user's Firebase UID, used to highlight their selected mood button.
    let currentUserId: String?
}

// MARK: - Timeline Provider

struct MoodWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: .now, group: .preview, configuration: ConfigurationAppIntent(), currentUserId: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> MoodEntry {
        // Snapshot is shown in the widget gallery — use cache for speed
        let groups = loadGroupsFromCache() ?? []
        let group = pick(from: groups, selectedId: configuration.group?.id) ?? .preview
        let userId = UserDefaults(suiteName: AppGroupConstants.suiteName)?.string(forKey: "widget_current_user_id")
        return MoodEntry(date: .now, group: group, configuration: configuration, currentUserId: userId)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<MoodEntry> {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        let currentUserId = defaults?.string(forKey: "widget_current_user_id")

        // ── Fast path: skip network when an AppIntent just ran ─────────────────
        // Both SetMoodIntent and SendHeartIntent do two things before returning:
        //   1. Write the optimistic result directly into widget_groups (cache)
        //   2. Write a pending key (widgetMood_* or widgetHeartCount_*)
        //
        // When WidgetKit calls timeline() immediately after perform() returns, a
        // pending key means the cache is already the freshest possible truth —
        // skip the Supabase round-trip entirely and return in < 1 ms.
        //
        // The detached task in the intent clears the key and calls
        // reloadAllTimelines() once Supabase confirms, which triggers the slow
        // path below for the authoritative second update.
        let cachedBeforeFetch = loadGroupsFromCache() ?? []
        let hasPendingChange = !cachedBeforeFetch.isEmpty && cachedBeforeFetch.contains { g in
            defaults?.string(forKey: "widgetMood_\(g.id)") != nil ||
            defaults?.object(forKey: "widgetHeartCount_\(g.id)") as? Int != nil
        }
        if hasPendingChange {
            // Apply pending keys on top of cache — handles the race where
            // handleMoodUpdatePush() overwrote widget_groups with stale Supabase
            // data (partner's push) before our background task finished syncing.
            var groups = cachedBeforeFetch
            if let userId = currentUserId {
                for idx in groups.indices {
                    let moodKey = "widgetMood_\(groups[idx].id)"
                    if let moodRaw = defaults?.string(forKey: moodKey),
                       let mood    = Mood(rawValue: moodRaw) {
                        groups[idx].currentMoods[userId] = mood
                    }
                    // Re-apply pending timestamp so it shows immediately on widget tap
                    let timeKey = "widgetMoodTime_\(groups[idx].id)_\(userId)"
                    if let ts = defaults?.string(forKey: timeKey) {
                        groups[idx].moodTimestamps[userId] = ts
                    }
                }
            }
            for idx in groups.indices where groups[idx].type == .couple {
                let key = "widgetHeartCount_\(groups[idx].id)"
                if let pending = defaults?.object(forKey: key) as? Int,
                   pending > groups[idx].heartCount {
                    groups[idx].heartCount = pending
                }
            }
            let group = pick(from: groups, selectedId: configuration.group?.id) ?? .preview
            let entry = MoodEntry(date: .now, group: group, configuration: configuration, currentUserId: currentUserId)
            // 30-second safety net — fires a slow-path refresh if the background
            // task is somehow never able to call reloadAllTimelines().
            let safetyNet = Calendar.current.date(byAdding: .second, value: 30, to: .now) ?? .now
            return Timeline(entries: [entry], policy: .after(safetyNet))
        }

        // Fetch live data from Supabase (slow path — no pending changes)
        var freshGroups = await WidgetDataService.fetchGroups()
#if DEBUG
        // Merge mock groups so pick() can find them even after a Supabase fetch
        // (mock groups don't exist in Supabase, so the fetch will never return them)
        if let data = defaults?.data(forKey: "widget_groups_debug"),
           let debugGroups = try? JSONDecoder().decode([MoodGroup].self, from: data) {
            let existingIds = Set(freshGroups.map { $0.id })
            freshGroups += debugGroups.filter { !existingIds.contains($0.id) }
        }
#endif

        // ── Critical: re-apply any pending mood taps ──────────────────────────
        // When the user taps a mood button, SetMoodIntent writes the new mood to
        // the local cache AND stores a "widgetMood_<groupId>" pending key.
        // Then WidgetKit immediately calls timeline(), which re-fetches Supabase.
        // Supabase still has the OLD mood (not synced yet — app is closed).
        // Without this merge step that stale fetch would overwrite the tap,
        // making it look like taps never work.
        if !freshGroups.isEmpty,
           let userId = defaults?.string(forKey: "widget_current_user_id") {
            for idx in freshGroups.indices {
                let moodKey = "widgetMood_\(freshGroups[idx].id)"
                if let moodRaw = defaults?.string(forKey: moodKey),
                   let mood = Mood(rawValue: moodRaw) {
                    freshGroups[idx].currentMoods[userId] = mood
                }
                // Re-apply pending timestamp to prevent Supabase stale fetch from reverting it
                let timeKey = "widgetMoodTime_\(freshGroups[idx].id)_\(userId)"
                if let ts = defaults?.string(forKey: timeKey) {
                    freshGroups[idx].moodTimestamps[userId] = ts
                }
            }
        }

        // ── Re-apply any pending heart taps (same pattern as moods above) ─────
        // SendHeartIntent writes "widgetHeartCount_<groupId>" when the user taps
        // the heart. If timeline() fires before Supabase confirms, the fresh fetch
        // would revert the count. Override it with the pending value.
        for idx in freshGroups.indices where freshGroups[idx].type == .couple {
            let key = "widgetHeartCount_\(freshGroups[idx].id)"
            if let pending = defaults?.object(forKey: key) as? Int {
                freshGroups[idx].heartCount = pending
            }
        }

        // ── Preserve heartCount from previous cache (never go backwards) ──────
        // Hearts only ever increment. If the fresh Supabase fetch returned a lower
        // count (couple_hearts query failed, JWT expired, network blip), the
        // previously cached value is the truth. Take the max.
        if let cachedGroups = loadGroupsFromCache() {
            let cachedHearts = Dictionary(uniqueKeysWithValues: cachedGroups.map { ($0.id, $0.heartCount) })
            for idx in freshGroups.indices where freshGroups[idx].type == .couple {
                let cached = cachedHearts[freshGroups[idx].id] ?? 0
                if cached > freshGroups[idx].heartCount {
                    freshGroups[idx].heartCount = cached
                }
            }
        }

        // Persist merged data back to cache so mood button intents stay in sync
        if !freshGroups.isEmpty,
           let data = try? JSONEncoder().encode(freshGroups) {
            defaults?.set(data, forKey: "widget_groups")
        }

        // Prefer fresh → cached → preview; honour the user's group selection
        let allGroups = freshGroups.isEmpty ? (loadGroupsFromCache() ?? []) : freshGroups
        let group = pick(from: allGroups, selectedId: configuration.group?.id) ?? .preview
        let entry = MoodEntry(date: .now, group: group, configuration: configuration, currentUserId: currentUserId)

        // Request a refresh as a fallback safety net.
        // The primary update path is via silent APNs push (near-instant).
        // Simulator can't receive APNs pushes so it must rely on polling;
        // use 30-second intervals there. On real devices 2 minutes is enough.
        #if targetEnvironment(simulator)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: .now) ?? .now
        #else
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now) ?? .now
        #endif
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    /// Returns the group matching `selectedId`, or the first group if no selection was made.
    private func pick(from groups: [MoodGroup], selectedId: String?) -> MoodGroup? {
        if let id = selectedId, let match = groups.first(where: { $0.id == id }) {
            return match
        }
        return groups.first
    }

    private func loadGroupsFromCache() -> [MoodGroup]? {
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
        return groups.isEmpty ? nil : groups
    }
}

// MARK: - Thin Provider Wrappers

/// Delegates all logic to MoodWidgetProvider, bridging CoupleConfigurationIntent.
struct CoupleWidgetProvider: AppIntentTimelineProvider {
    private let core = MoodWidgetProvider()
    func placeholder(in context: Context) -> MoodEntry { core.placeholder(in: context) }
    func snapshot(for configuration: CoupleConfigurationIntent, in context: Context) async -> MoodEntry {
        var c = ConfigurationAppIntent()
        // Gallery preview (no group selected yet): show the user's first couple group from cache.
        // Falls back to core's .preview placeholder if no couple group exists in cache.
        c.group = configuration.group ?? previewEntity(filter: { $0.type == .couple })
        return await core.snapshot(for: c, in: context)
    }
    func timeline(for configuration: CoupleConfigurationIntent, in context: Context) async -> Timeline<MoodEntry> {
        var c = ConfigurationAppIntent(); c.group = configuration.group
        return await core.timeline(for: c, in: context)
    }
}

/// Delegates all logic to MoodWidgetProvider, bridging BFFConfigurationIntent (large widget).
struct BFFWidgetProvider: AppIntentTimelineProvider {
    private let core = MoodWidgetProvider()
    func placeholder(in context: Context) -> MoodEntry { core.placeholder(in: context) }
    func snapshot(for configuration: BFFConfigurationIntent, in context: Context) async -> MoodEntry {
        var c = ConfigurationAppIntent()
        // Gallery preview: show the user's first BFF/family group with 4+ members from cache.
        c.group = configuration.group ?? previewEntity(filter: {
            ($0.type == .bff || $0.type == .family) && $0.members.count >= 4
        })
        return await core.snapshot(for: c, in: context)
    }
    func timeline(for configuration: BFFConfigurationIntent, in context: Context) async -> Timeline<MoodEntry> {
        var c = ConfigurationAppIntent(); c.group = configuration.group
        return await core.timeline(for: c, in: context)
    }
}

/// Delegates all logic to MoodWidgetProvider, bridging BFFMediumConfigurationIntent (medium widget).
struct BFFMediumWidgetProvider: AppIntentTimelineProvider {
    private let core = MoodWidgetProvider()
    func placeholder(in context: Context) -> MoodEntry { core.placeholder(in: context) }
    func snapshot(for configuration: BFFMediumConfigurationIntent, in context: Context) async -> MoodEntry {
        var c = ConfigurationAppIntent()
        // Gallery preview: show the user's first BFF/family group with 2–3 members from cache.
        c.group = configuration.group ?? previewEntity(filter: {
            ($0.type == .bff || $0.type == .family) && $0.members.count <= 3
        })
        return await core.snapshot(for: c, in: context)
    }
    func timeline(for configuration: BFFMediumConfigurationIntent, in context: Context) async -> Timeline<MoodEntry> {
        var c = ConfigurationAppIntent(); c.group = configuration.group
        return await core.timeline(for: c, in: context)
    }
}

/// Returns a `GroupAppEntity` for the first cached group matching `filter`, or nil if none found.
/// Used by provider snapshot functions to show a real group in the widget gallery preview.
private func previewEntity(filter: (MoodGroup) -> Bool) -> GroupAppEntity? {
    guard let group = mergedGroups().first(where: filter) else { return nil }
    return GroupAppEntity(id: group.id, name: group.name, typeName: group.type.displayName)
}

// MARK: - Container Background (family-aware)

/// Medium widgets (4×2) use the group-specific background image rendered via containerBackground.
/// iOS dark-mode adaptive tinting. containerBackground gets plain cream to match.
/// Large widgets keep their group-type gradient in containerBackground.
private struct WidgetContainerBackground: View {
    @Environment(\.widgetFamily) var family
    let entry: MoodEntry

    var body: some View {
        Color(red: 1.0, green: 0.988, blue: 0.929) // #FFFCED — all widget sizes use cream
    }
}

// MARK: - Widget Definition

// MARK: - Couple Widget (4×2 only)

struct MoodCanvasWidget: Widget {
    let kind: String = "MoodCanvasCoupleWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CoupleConfigurationIntent.self,
            provider: CoupleWidgetProvider()
        ) { entry in
            MoodWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetContainerBackground(entry: entry)
                }
        }
        .configurationDisplayName("Moodi — Couple")
        .description("See your partner's mood and update yours.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - BFF / Family Widget — 4×2 Medium (Friends/Family groups with ≤ 3 members only)

struct MoodCanvasBFFMediumWidget: Widget {
    let kind: String = "MoodCanvasBFFMediumWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BFFMediumConfigurationIntent.self,
            provider: BFFMediumWidgetProvider()
        ) { entry in
            MoodWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetContainerBackground(entry: entry)
                }
        }
        .configurationDisplayName("Moodi")
        .description("Friends/Family · For groups of 2 or 3 members.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - BFF / Family Widget — 4×4 Large (Friends/Family groups with 4+ members only)

struct MoodCanvasBFFWidget: Widget {
    let kind: String = "MoodCanvasBFFWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BFFConfigurationIntent.self,
            provider: BFFWidgetProvider()
        ) { entry in
            MoodWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetContainerBackground(entry: entry)
                }
        }
        .configurationDisplayName("Moodi — Large")
        .description("Friends/Family · For groups of 4 or more members.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Previews

#Preview("Couple – Medium", as: .systemMedium) {
    MoodCanvasWidget()
} timeline: {
    MoodEntry(date: .now, group: .couplePreview, configuration: ConfigurationAppIntent(), currentUserId: "4")
}

#Preview("BFF – Medium (2 members)", as: .systemMedium) {
    MoodCanvasBFFMediumWidget()
} timeline: {
    MoodEntry(date: .now, group: .preview, configuration: ConfigurationAppIntent(), currentUserId: "1")
}

#Preview("BFF – Medium (3 members)", as: .systemMedium) {
    MoodCanvasBFFMediumWidget()
} timeline: {
    MoodEntry(date: .now, group: .bffThreePreview, configuration: ConfigurationAppIntent(), currentUserId: "1")
}

#Preview("BFF – Large (4 members)", as: .systemLarge) {
    MoodCanvasBFFWidget()
} timeline: {
    MoodEntry(date: .now, group: .bffLargePreview, configuration: ConfigurationAppIntent(), currentUserId: "1")
}

#Preview("Family – Medium (3 members)", as: .systemMedium) {
    MoodCanvasBFFMediumWidget()
} timeline: {
    MoodEntry(date: .now, group: .familyPreview, configuration: ConfigurationAppIntent(), currentUserId: "6")
}

#Preview("Family – Large", as: .systemLarge) {
    MoodCanvasBFFWidget()
} timeline: {
    MoodEntry(date: .now, group: .familyPreview, configuration: ConfigurationAppIntent(), currentUserId: "6")
}
