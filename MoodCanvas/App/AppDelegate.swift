import UIKit
import FirebaseCore
import FirebaseAuth
import WidgetKit
import os

private let pushLog = Logger(subsystem: "com.huseyinturkay.moodcanvas.app", category: "push")

extension Notification.Name {
    /// Posted on MainActor when a mood-update silent push arrives.
    /// HomeView observes this to refresh while the app is already in the foreground
    /// (scenePhase stays .active and onChange never fires in that case).
    static let moodUpdateReceived = Notification.Name("MoodCanvasMoodUpdate")
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set the window background to the app's cream color so there is never
        // a black frame visible during launch or any SwiftUI view transition.
        // UIWindow.appearance() applies before any window is created by SwiftUI's WindowGroup.
        UIWindow.appearance().backgroundColor = UIColor(red: 1.0, green: 0.988, blue: 0.929, alpha: 1.0)

        FirebaseApp.configure()
        #if targetEnvironment(simulator)
        // Firebase 11 collects the APNs token BEFORE checking
        // isAppVerificationDisabledForTesting, so on simulator (no real APNs)
        // it times out and force-unwraps nil → crash.
        // Fix: feed Firebase a fake non-nil token so the collection step
        // succeeds immediately, then disable app verification so the test
        // phone number bypass kicks in normally.
        let fakeToken = Data(repeating: 0xAB, count: 32)
        Auth.auth().setAPNSToken(fakeToken, type: .unknown)
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #else
        // Register for remote notifications to receive silent mood-update pushes.
        // No user permission needed — silent pushes don't show any UI.
        print("[APNs] Calling registerForRemoteNotifications()…")
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward to Firebase (needed for phone number verification)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let prevToken = KeychainService.load(.apnsToken)
        let tokenRotated = prevToken != nil && prevToken != tokenHex
        print("[APNs] Registration succeeded — token: \(tokenHex.prefix(16))… (rotated=\(tokenRotated))")
        // Store in Keychain (not UserDefaults) — encrypted, excluded from iCloud backup.
        KeychainService.save(.apnsToken, value: tokenHex)

        // Always attempt to save to Supabase immediately — do not guard on hasJWT.
        // Rationale: if we skip the save here (because session restore hasn't finished yet),
        // fetchGroups() may run before this callback fires and store the OLD token.
        // The new token would sit in UserDefaults but never reach Supabase, causing the
        // "stale token → 410 → token deleted → no pushes" cycle.
        // saveDeviceToken() handles a missing JWT gracefully (logs the error, doesn't crash).
        // fetchGroups() will also save on the next app-open as a second safety net.
        guard let userId = Auth.auth().currentUser?.uid else {
            print("[APNs] No user yet — token stored in Keychain, will be saved on next fetchGroups()")
            return
        }
        // Sandbox tokens (debug/Xcode builds) must go to api.sandbox.push.apple.com.
        // Production tokens (TestFlight/App Store) must go to api.push.apple.com.
        // Mixing them causes 400 BadDeviceToken and silently drops every push.
        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif
        Task { @MainActor in
            print("[APNs] Saving token to Supabase (hasJWT=\(SupabaseService.shared.hasJWT), env=\(apnsEnvironment))")
            await SupabaseService.shared.saveDeviceToken(tokenHex, userId: userId, environment: apnsEnvironment)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration FAILED: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Check for our mood-update push BEFORE calling Firebase's
        // canHandleNotification(). Firebase 11 returns true for ANY
        // content-available:1 push — including ours — and calls completionHandler
        // early, which means WidgetCenter.reloadAllTimelines() is never reached.
        // The "mood-update" key in the payload lets us identify and claim our
        // push first so Firebase never gets a chance to swallow it.
        if userInfo["mood-update"] != nil {
            pushLog.info("mood-update silent push received")
            Task {
                await handleMoodUpdatePush()
                completionHandler(.newData)
            }
            return
        }
        // Let Firebase handle its own phone-auth silent pushes
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        // Unknown push — still reload just in case
        WidgetCenter.shared.reloadAllTimelines()
        completionHandler(.newData)
    }

    // Extracted so the completionHandler is always called at the Task boundary,
    // regardless of what happens inside (network timeout, JWT failure, etc.).
    private func handleMoodUpdatePush() async {
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)

        // 1. Immediately sync whatever JWT is in Keychain to AppGroup.
        //    We do this unconditionally — even an expiring JWT is better than
        //    nothing. WidgetDataService handles 401s gracefully (returns cached
        //    data), so the widget won't crash with a stale token.
        if let stored = KeychainService.load(.supabaseJWT) {
            defaults?.set(stored, forKey: "widget_jwt")
            pushLog.info("JWT synced to AppGroup from Keychain")
        }

        // 2. Set the force-refresh flag so the widget's timeline() skips the
        //    pending-change fast path and goes straight to a Supabase fetch.
        //
        //    Background: timeline() has a fast path that returns cached data when
        //    a widgetMood_* key exists (set by SetMoodIntent when the user taps a
        //    mood button in the widget). If that key was never cleared (background
        //    sync failed), the widget is permanently stuck showing stale cached
        //    data — it never reaches the Supabase fetch regardless of how many
        //    times reloadAllTimelines() is called.
        //
        //    The force-refresh flag overrides this: timeline() detects it, clears
        //    it, and goes to the slow path (Supabase fetch). Pending mood keys are
        //    still re-applied on top of the fresh data in the slow path, so any
        //    in-flight widget taps are preserved correctly.
        defaults?.set(true, forKey: "widget_force_refresh")
        // Also reset the fast-path loop timer. timeline() starts a timer the first
        // time it enters the pending-key fast path; after 2 minutes it expires the
        // pending keys and forces the slow path. Resetting it here means the push-
        // triggered timeline() call is treated as a fresh cycle, not a continuation
        // of whatever loop was running before the push arrived.
        defaults?.removeObject(forKey: "widget_fast_path_loop_start")
        defaults?.synchronize()

        // 3. Reload widget timelines NOW — before any network calls.
        //    The widget's own timeline() fetches fresh Supabase data independently.
        //    Firing the reload here (rather than after a slow JWT refresh) means
        //    the widget update begins in < 1 ms instead of waiting up to ~15 s
        //    for getIDToken() + authenticate() to complete.
        WidgetCenter.shared.reloadAllTimelines()
        pushLog.info("reloadAllTimelines called")

        // 4. Notify any live app UI to refresh its group list.
        //    When the app is already in the foreground, scenePhase stays .active
        //    and onChange never fires, so HomeView would otherwise show stale moods.
        await MainActor.run {
            NotificationCenter.default.post(name: .moodUpdateReceived, object: nil)
        }

        // 5. Prefetch fresh groups and write directly to widget_groups cache.
        //    Rationale: reloadAllTimelines() is subject to WidgetKit's daily budget.
        //    If the budget is exhausted, timeline() is never called and the widget
        //    stays stale. Writing fresh data directly to the cache means the widget
        //    will show the partner's new mood on its NEXT timeline() call — whether
        //    that call comes from the reload above, a 30-second fast-path safety net,
        //    or the 15-minute scheduled poll.
        //    If the fetch returns empty (network error, JWT issue) we keep the
        //    existing cache untouched so the widget never goes blank.
        pushLog.info("prefetching fresh groups from Supabase")
        let freshGroups = await WidgetDataService.fetchGroups()
        if !freshGroups.isEmpty, let data = try? JSONEncoder().encode(freshGroups) {
            defaults?.set(data, forKey: "widget_groups")
            defaults?.synchronize()
            pushLog.info("wrote \(freshGroups.count) fresh group(s) to AppGroup cache")
        } else {
            pushLog.warning("prefetch returned empty — keeping existing cache")
        }

        // 6. If the JWT is expired/expiring, refresh it via Firebase and do a
        //    second widget reload so the widget's Supabase fetch succeeds with a
        //    valid token. On the happy path (JWT still fresh) we skip this block
        //    entirely, so completionHandler fires almost instantly.
        guard let storedJWT = KeychainService.load(.supabaseJWT),
              KeychainService.jwtIsExpiredOrExpiringSoon(storedJWT),
              let firebaseUser = Auth.auth().currentUser else {
            return
        }
        do {
            let idToken = try await firebaseUser.getIDToken(forcingRefresh: false)
            let newJWT = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)
            KeychainService.save(.supabaseJWT, value: newJWT)
            SupabaseService.shared.configure(jwt: newJWT)
            defaults?.set(newJWT, forKey: "widget_jwt")
            print("[Push] JWT refreshed — triggering second widget reload")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("[Push] JWT refresh failed (\(error.localizedDescription))")
        }
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Widget's Message button sends sms: URLs here — forward them to Messages.
        // (WidgetKit always routes Link URLs through the parent app rather than
        //  opening them directly in the system.)
        if url.scheme == "sms" {
            UIApplication.shared.open(url)
            return true
        }
        return Auth.auth().canHandle(url)
    }
}
