import Foundation

/// Lightweight Supabase client for use inside the widget extension.
///
/// The main app stores credentials in the App Group at startup and on every JWT change.
/// The widget reads these credentials here so it can fetch live data without
/// the full Supabase Swift SDK (which is only linked into the main app target).
struct WidgetDataService {

    /// Upserts the current user's mood for a group directly to Supabase.
    /// Called from SetMoodIntent so other devices see the change within their
    /// next 5-minute refresh cycle without requiring the main app to be opened.
    /// Silently no-ops on any error; the pending widgetMood_* key acts as fallback.
    static func syncMood(_ mood: Mood, userId: String, groupId: String) async {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard
            let jwt         = defaults?.string(forKey: "widget_jwt"),
            let supabaseURL = defaults?.string(forKey: "widget_supabase_url"),
            let anonKey     = defaults?.string(forKey: "widget_supabase_anon_key"),
            let url = URL(string: "\(supabaseURL)/rest/v1/moods")
        else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)",    forHTTPHeaderField: "Authorization")
        request.setValue(anonKey,            forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Upsert: merge on unique (user_id, group_id)
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        struct MoodPayload: Encodable {
            let user_id:  String
            let group_id: String
            let mood:     String
        }
        request.httpBody = try? JSONEncoder().encode(
            MoodPayload(user_id: userId, group_id: groupId, mood: mood.rawValue)
        )

        // If the upsert succeeded (any 2xx), notify other group members via silent APNs push.
        // We accept the full 2xx range because PostgREST may return 200 or 201 depending on
        // whether a row was inserted vs. updated. Failures are logged — the pending
        // widgetMood_* key is the fallback so the mood isn't lost.
        if let (data, response) = try? await URLSession.shared.data(for: request) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                print("[Widget] syncMood succeeded (HTTP \(status)) — sending push to group members")
                await notifyMoodUpdate(groupId: groupId, userId: userId)
            } else {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                print("[Widget] syncMood failed — HTTP \(status): \(body)")
            }
        } else {
            print("[Widget] syncMood network error (no response)")
        }
    }

    /// Calls the send-mood-push Edge Function so other group members' widgets
    /// get a silent APNs wakeup and reload their timelines immediately.
    static func notifyMoodUpdate(groupId: String, userId: String) async {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard
            let jwt         = defaults?.string(forKey: "widget_jwt"),
            let supabaseURL = defaults?.string(forKey: "widget_supabase_url"),
            let anonKey     = defaults?.string(forKey: "widget_supabase_anon_key"),
            let url = URL(string: "\(supabaseURL)/functions/v1/send-mood-push")
        else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey,           forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable { let group_id: String; let updated_by: String }
        request.httpBody = try? JSONEncoder().encode(Payload(group_id: groupId, updated_by: userId))

        if let (data, response) = try? await URLSession.shared.data(for: request) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[Widget] notifyMoodUpdate HTTP \(status): \(body)")
        } else {
            print("[Widget] notifyMoodUpdate network error (no response)")
        }
    }

    /// Calls the `increment_heart` Supabase RPC and returns the new authoritative count.
    /// Returns 0 on any error; the caller's optimistic count acts as fallback.
    static func incrementHeart(groupId: String) async -> Int {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard
            let jwt         = defaults?.string(forKey: "widget_jwt"),
            let supabaseURL = defaults?.string(forKey: "widget_supabase_url"),
            let anonKey     = defaults?.string(forKey: "widget_supabase_anon_key"),
            let url = URL(string: "\(supabaseURL)/rest/v1/rpc/increment_heart")
        else { return 0 }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)",    forHTTPHeaderField: "Authorization")
        request.setValue(anonKey,            forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_group_id": groupId])

        if let (data, response) = try? await URLSession.shared.data(for: request) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status),
               let count = try? JSONDecoder().decode(Int.self, from: data) {
                print("[Widget] incrementHeart succeeded — new count: \(count)")
                return count
            } else {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                print("[Widget] incrementHeart failed — HTTP \(status): \(body)")
            }
        } else {
            print("[Widget] incrementHeart network error (no response)")
        }
        return 0
    }

    /// Fetches the current user's groups with members and moods from Supabase.
    /// For couple groups, also fetches `couple_hearts` and merges the count.
    /// Returns an empty array on any error (network, auth, parse).
    static func fetchGroups() async -> [MoodGroup] {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        guard
            let jwt         = defaults?.string(forKey: "widget_jwt"),
            let supabaseURL = defaults?.string(forKey: "widget_supabase_url"),
            let anonKey     = defaults?.string(forKey: "widget_supabase_anon_key"),
            let url = URL(string: "\(supabaseURL)/rest/v1/rpc/get_widget_data")
        else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey,           forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                print("[Widget] fetchGroups failed — HTTP \(status): \(body)")
                return []
            }
            var groups = try JSONDecoder().decode([MoodGroup].self, from: data)
            print("[Widget] fetchGroups returned \(groups.count) group(s)")

            // Merge heart counts for couple groups.
            // Also load previously cached counts as a fallback — if the couple_hearts
            // fetch fails (expired JWT, network blip), we must not regress to 0.
            let cachedHearts: [String: Int] = {
                guard let data   = defaults?.data(forKey: "widget_groups"),
                      let cached = try? JSONDecoder().decode([MoodGroup].self, from: data)
                else { return [:] }
                return Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0.heartCount) })
            }()

            let coupleIds = groups.filter { $0.type == .couple }.map { $0.id }
            if !coupleIds.isEmpty {
                let idList = coupleIds.joined(separator: ",")
                if let heartURL = URL(string: "\(supabaseURL)/rest/v1/couple_hearts?group_id=in.(\(idList))&select=group_id,count") {
                    var heartReq = URLRequest(url: heartURL, timeoutInterval: 10)
                    heartReq.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
                    heartReq.setValue(anonKey,          forHTTPHeaderField: "apikey")
                    heartReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    if let (hData, hResp) = try? await URLSession.shared.data(for: heartReq),
                       (hResp as? HTTPURLResponse)?.statusCode == 200 {
                        struct HRec: Decodable { let group_id: String; let count: Int }
                        if let records = try? JSONDecoder().decode([HRec].self, from: hData) {
                            let map = Dictionary(uniqueKeysWithValues: records.map { ($0.group_id, $0.count) })
                            for idx in groups.indices where groups[idx].type == .couple {
                                let fetched = map[groups[idx].id] ?? 0
                                let cached  = cachedHearts[groups[idx].id] ?? 0
                                groups[idx].heartCount = max(fetched, cached)
                            }
                        }
                    } else {
                        // Fetch failed — preserve whatever the cache had
                        for idx in groups.indices where groups[idx].type == .couple {
                            groups[idx].heartCount = cachedHearts[groups[idx].id] ?? 0
                        }
                    }
                }
            }
            return groups
        } catch {
            print("[Widget] fetchGroups error: \(error)")
            return []
        }
    }
}
