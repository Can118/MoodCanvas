import Foundation

/// Reads build-time configuration injected via Secrets.xcconfig → Info.plist.
/// Raw strings are NEVER hardcoded here — this file is committed to git.
enum AppConfig {

    // MARK: - Supabase

    static let supabaseURL: String = {
        value(for: "SUPABASE_URL", hint: "Add SUPABASE_URL to Secrets.xcconfig")
    }()

    static let supabaseAnonKey: String = {
        value(for: "SUPABASE_ANON_KEY", hint: "Add SUPABASE_ANON_KEY to Secrets.xcconfig")
    }()

    // MARK: - Firebase
    // Firebase credentials come from GoogleService-Info.plist.
    // FirebaseApp.configure() reads that file automatically — no values needed here.

    // MARK: - Private

    private static func value(for key: String, hint: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty,
              !raw.hasPrefix("$(")   // catches unexpanded xcconfig variables
        else {
            fatalError("[\(key)] not configured. \(hint)")
        }
        return raw
    }
}
