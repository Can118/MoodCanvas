import SwiftUI

@main
struct MoodCanvasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()

    init() {
        // Share Supabase credentials with the widget extension via App Group.
        // The anon key is intentionally public (RLS enforced server-side).
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        defaults?.set(AppConfig.supabaseURL,     forKey: "widget_supabase_url")
        defaults?.set(AppConfig.supabaseAnonKey, forKey: "widget_supabase_anon_key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
        }
    }
}
