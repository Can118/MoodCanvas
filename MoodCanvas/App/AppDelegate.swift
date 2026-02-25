import UIKit
import FirebaseCore
import FirebaseAuth
import WidgetKit

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
        // Save the hex token so GroupService can register it with Supabase after login
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNs] Registration succeeded — token: \(tokenHex.prefix(16))…")
        UserDefaults.standard.set(tokenHex, forKey: "apns_device_token")
        // Eagerly persist to Supabase only if the JWT is already configured.
        // If Supabase isn't authenticated yet (session restoration still in-flight),
        // skip — AuthService.saveDeviceTokenIfAvailable() will save after configure(jwt:).
        if let userId = Auth.auth().currentUser?.uid {
            Task { @MainActor in
                if SupabaseService.shared.hasJWT {
                    print("[APNs] JWT ready — saving token to Supabase immediately")
                    await SupabaseService.shared.saveDeviceToken(tokenHex, userId: userId)
                } else {
                    print("[APNs] JWT not ready yet — token in UserDefaults, AuthService will save after session restore")
                }
            }
        } else {
            print("[APNs] No user yet — token stored in UserDefaults, will be saved on next fetchGroups()")
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

        // 1. Try to issue a fresh Supabase JWT using the cached Firebase session.
        //    The widget JWT in AppGroup is valid for 7 days, but refreshing it here
        //    on every incoming push keeps the window from ever getting stale.
        //    Falls back to copying whatever is in Keychain if Firebase is unavailable.
        if let firebaseUser = Auth.auth().currentUser {
            do {
                let idToken = try await firebaseUser.getIDToken(forcingRefresh: false)
                let newJWT = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)
                KeychainService.save(.supabaseJWT, value: newJWT)
                defaults?.set(newJWT, forKey: "widget_jwt")
                print("[Push] JWT refreshed from Firebase (\(newJWT.prefix(20))…)")
            } catch {
                print("[Push] JWT refresh failed (\(error.localizedDescription)) — falling back to Keychain copy")
                if let stored = KeychainService.load(.supabaseJWT) {
                    defaults?.set(stored, forKey: "widget_jwt")
                }
            }
        } else {
            print("[Push] No active Firebase session — copying Keychain JWT to AppGroup")
            if let stored = KeychainService.load(.supabaseJWT) {
                defaults?.set(stored, forKey: "widget_jwt")
            }
        }

        // 2. Pre-fetch the latest groups and write them into the AppGroup cache
        //    BEFORE telling WidgetKit to reload. The widget's timeline() will find
        //    warm data already waiting, so it shows the right mood immediately.
        let freshGroups = await WidgetDataService.fetchGroups()
        print("[Push] fetchGroups returned \(freshGroups.count) group(s)")
        if !freshGroups.isEmpty, let data = try? JSONEncoder().encode(freshGroups) {
            defaults?.set(data, forKey: "widget_groups")
        }

        // 3. Reload widget timelines — cache is now warm.
        WidgetCenter.shared.reloadAllTimelines()
        print("[Push] Widget timelines reloaded")
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
