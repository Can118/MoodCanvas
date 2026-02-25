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
                    let key = "widgetMood_\(groups[idx].id)"
                    if let moodRaw = defaults?.string(forKey: key),
                       let mood    = Mood(rawValue: moodRaw) {
                        groups[idx].currentMoods[userId] = mood
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
                let key = "widgetMood_\(freshGroups[idx].id)"
                if let moodRaw = defaults?.string(forKey: key),
                   let mood = Mood(rawValue: moodRaw) {
                    freshGroups[idx].currentMoods[userId] = mood
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

        // Request a refresh every 2 minutes as a fallback safety net.
        // The primary update path is via silent APNs push (near-instant),
        // but this ensures stale data is corrected quickly even if a push
        // is delayed or dropped by the OS.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: .now) ?? .now
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
        guard
            let data   = defaults?.data(forKey: "widget_groups"),
            let groups = try? JSONDecoder().decode([MoodGroup].self, from: data)
        else { return nil }
        return groups
    }
}

// MARK: - Widget Definition

struct MoodCanvasWidget: Widget {
    let kind: String = "MoodCanvasWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ConfigurationAppIntent.self,
            provider: MoodWidgetProvider()
        ) { entry in
            MoodWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    // BFF uses a custom image background rendered INSIDE the widget view
                    // (in BFFMediumWidgetView) to avoid iOS dark-mode adaptive treatment.
                    // Other group types use their gradient here.
                    if entry.group.type == .bff {
                        // BFF uses a custom image background rendered INSIDE the
                        // widget view to avoid iOS dark-mode adaptive treatment.
                        // This plain cream colour matches the image fill colour.
                        Color(red: 0.99, green: 0.98, blue: 0.95)
                    } else {
                        entry.group.type.backgroundGradient
                    }
                }
        }
        .configurationDisplayName("Mood Canvas")
        .description("See your group's current moods and update yours.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    MoodCanvasWidget()
} timeline: {
    MoodEntry(date: .now, group: .preview, configuration: ConfigurationAppIntent(), currentUserId: "1")
    MoodEntry(date: .now, group: .couplePreview, configuration: ConfigurationAppIntent(), currentUserId: "4")
}

#Preview(as: .systemLarge) {
    MoodCanvasWidget()
} timeline: {
    MoodEntry(date: .now, group: .familyPreview, configuration: ConfigurationAppIntent(), currentUserId: "6")
}
