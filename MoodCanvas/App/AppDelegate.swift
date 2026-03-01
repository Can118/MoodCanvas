import UIKit
import FirebaseCore
import FirebaseAuth
import WidgetKit

extension Notification.Name {
    /// Posted on MainActor when a mood-update silent push arrives.
    /// HomeView observes this to refresh while the app is already in the foreground
    /// (scenePhase stays .active and onChange never fires in that case).
    static let moodUpdateReceived = Notification.Name("MoodCanvasMoodUpdate")
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
        let prevToken = UserDefaults.standard.string(forKey: "apns_device_token")
        let tokenRotated = prevToken != nil && prevToken != tokenHex
        print("[APNs] Registration succeeded — token: \(tokenHex.prefix(16))… (rotated=\(tokenRotated))")
        // Always update UserDefaults so fetchGroups() always has the latest token.
        UserDefaults.standard.set(tokenHex, forKey: "apns_device_token")

        // Always attempt to save to Supabase immediately — do not guard on hasJWT.
        // Rationale: if we skip the save here (because session restore hasn't finished yet),
        // fetchGroups() may run before this callback fires and store the OLD token.
        // The new token would sit in UserDefaults but never reach Supabase, causing the
        // "stale token → 410 → token deleted → no pushes" cycle.
        // saveDeviceToken() handles a missing JWT gracefully (logs the error, doesn't crash).
        // fetchGroups() will also save on the next app-open as a second safety net.
        guard let userId = Auth.auth().currentUser?.uid else {
            print("[APNs] No user yet — token stored in UserDefaults, will be saved on next fetchGroups()")
            return
        }
        Task { @MainActor in
            print("[APNs] Saving token to Supabase (hasJWT=\(SupabaseService.shared.hasJWT))")
            await SupabaseService.shared.saveDeviceToken(tokenHex, userId: userId)
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
            print("[Push] mood-update silent push received")
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

        // 1. Keep the AppGroup JWT fresh so the widget can authenticate.
        //    Happy path (JWT still valid for > 5 min): 0 network calls — just copy
        //    from Keychain to AppGroup and move on immediately.
        //    Sad path (JWT expired/expiring): 2 network calls to refresh via Firebase.
        //    We never pre-fetch groups here — the widget's own timeline() always
        //    fetches fresh data after reloadAllTimelines(), so a pre-fetch here
        //    would only add latency before the widget reload fires.
        if let stored = KeychainService.load(.supabaseJWT),
           !KeychainService.jwtIsExpiredOrExpiringSoon(stored) {
            defaults?.set(stored, forKey: "widget_jwt")
            print("[Push] JWT fresh — synced to AppGroup (no network)")
        } else if let firebaseUser = Auth.auth().currentUser {
            do {
                let idToken = try await firebaseUser.getIDToken(forcingRefresh: false)
                let newJWT = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)
                KeychainService.save(.supabaseJWT, value: newJWT)
                SupabaseService.shared.configure(jwt: newJWT)
                defaults?.set(newJWT, forKey: "widget_jwt")
                print("[Push] JWT refreshed — synced to AppGroup")
            } catch {
                print("[Push] JWT refresh failed (\(error.localizedDescription)) — using existing Keychain JWT")
                if let stored = KeychainService.load(.supabaseJWT) {
                    defaults?.set(stored, forKey: "widget_jwt")
                }
            }
        } else {
            if let stored = KeychainService.load(.supabaseJWT) {
                defaults?.set(stored, forKey: "widget_jwt")
            }
            print("[Push] No Firebase session — copied Keychain JWT to AppGroup")
        }

        // 2. Reload widget timelines — the widget's timeline() will fetch fresh data.
        WidgetCenter.shared.reloadAllTimelines()
        print("[Push] Widget timelines reloaded")

        // 3. Notify any live app UI to refresh its group list.
        //    When the app is already in the foreground, scenePhase stays .active
        //    and onChange never fires, so HomeView would otherwise show stale moods.
        await MainActor.run {
            NotificationCenter.default.post(name: .moodUpdateReceived, object: nil)
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
