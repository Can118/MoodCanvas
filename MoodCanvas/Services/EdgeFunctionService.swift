import Foundation

/// Typed client for Supabase Edge Functions.
/// All calls go over HTTPS. Secrets live server-side only.
enum EdgeFunctionService {

    // MARK: - Response types

    private struct AuthResponse: Decodable {
        let jwt: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case jwt
            case expiresIn = "expiresIn"
        }
    }

    private struct MatchResponse: Decodable {
        struct MatchedUser: Decodable {
            let id: String
            let name: String?
            /// Index into the original `phoneNumbers` input array — the server never
            /// echoes phone numbers back. The client resolves the phone locally.
            let inputIndex: Int
        }
        let matches: [MatchedUser]
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    // MARK: - authenticate

    /// Exchange a Firebase ID token for a short-lived Supabase JWT.
    /// The Edge Function verifies the token with Google and hashes the phone number.
    static func authenticate(firebaseIDToken: String) async throws -> String {
        let url = edgeFunctionURL("authenticate")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(["firebaseIdToken": firebaseIDToken])
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 200 {
            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
            return decoded.jwt
        }

        // Decode error message without exposing internals
        let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            ?? "Authentication failed (HTTP \(status))"
        throw MCError.edgeFunction(msg)
    }

    // MARK: - match-contacts

    /// Send E.164 phone numbers to the server, which hashes them and returns matching users.
    /// Phone numbers are transmitted over HTTPS but never stored by the Edge Function.
    static func matchContacts(phoneNumbers: [String], jwt: String) async throws -> [User] {
        guard !phoneNumbers.isEmpty else { return [] }

        let url = edgeFunctionURL("match-contacts")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(["phoneNumbers": phoneNumbers])
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200:
            let decoded = try JSONDecoder().decode(MatchResponse.self, from: data)
            return decoded.matches.compactMap { match in
                guard match.inputIndex >= 0, match.inputIndex < phoneNumbers.count else { return nil }
                let phone = phoneNumbers[match.inputIndex]
                return User(id: match.id, name: match.name ?? "MoodCanvas User", phoneNumber: phone)
            }
        case 429:
            throw MCError.rateLimited
        default:
            let msg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? "Contact match failed (HTTP \(status))"
            throw MCError.edgeFunction(msg)
        }
    }

    // MARK: - invite-by-phone

    /// Stores a deferred phone invitation in Supabase so that when the invitee
    /// downloads the app and registers, they automatically see the invite.
    /// Fire-and-forget — errors are logged but not thrown to the caller.
    static func inviteByPhone(groupId: String, phone: String, jwt: String) async {
        let url = edgeFunctionURL("invite-by-phone")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(["group_id": groupId, "phone": phone])
        req.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                print("[Invite] inviteByPhone failed (HTTP \(status)) for phone \(phone.prefix(6))…")
            }
        } catch {
            print("[Invite] inviteByPhone network error: \(error.localizedDescription)")
        }
    }

    // MARK: - send-invite-push

    /// Sends a silent APNs push to a user who has just been invited to a group so
    /// their app wakes and calls fetchPendingInvitations() immediately.
    /// Fire-and-forget — errors are logged but not thrown to the caller.
    static func notifyInvited(groupId: String, invitedUserId: String) async {
        guard let jwt = KeychainService.load(.supabaseJWT) else {
            print("[Invite] notifyInvited: no JWT in Keychain — skipping push")
            return
        }
        let url = edgeFunctionURL("send-invite-push")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode([
            "group_id": groupId,
            "invited_user_id": invitedUserId,
        ])
        req.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                print("[Invite] notifyInvited failed (HTTP \(status)) for user \(invitedUserId.prefix(8))…")
            }
        } catch {
            print("[Invite] notifyInvited network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private static func edgeFunctionURL(_ name: String) -> URL {
        URL(string: "\(AppConfig.supabaseURL)/functions/v1/\(name)")!
    }
}

// MARK: - App Error Type

enum MCError: LocalizedError {
    case edgeFunction(String)
    case rateLimited
    case noSession

    var errorDescription: String? {
        switch self {
        case .edgeFunction(let msg): return msg
        case .rateLimited:          return "Too many requests. Please try again in a minute."
        case .noSession:            return "Not signed in. Please restart the app."
        }
    }
}
