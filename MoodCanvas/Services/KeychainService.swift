import Foundation
import Security

// MARK: - Key Definitions

enum KeychainKey: String, CaseIterable {
    case firebaseUID   = "mc_firebase_uid"
    case supabaseJWT   = "mc_supabase_jwt"
    case jwtExpiry     = "mc_jwt_expiry"      // Unix timestamp string
    case phoneE164     = "mc_phone_e164"
}

// MARK: - Service

/// Thin, type-safe wrapper around Security framework keychain calls.
/// All items are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// so they are NOT backed up to iCloud and are tied to this device.
enum KeychainService {

    private static let serviceName = "com.huseyinturkay.moodcanvas.app"
    private static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    // MARK: Write

    @discardableResult
    static func save(_ key: KeychainKey, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first (upsert pattern)
        SecItemDelete(query(for: key) as CFDictionary)

        var item = query(for: key)
        item[kSecValueData] = data as AnyObject

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            #if DEBUG
            print("[Keychain] Save failed for key \(key.rawValue): \(status)")
            #endif
            return false
        }
        return true
    }

    // MARK: Read

    static func load(_ key: KeychainKey) -> String? {
        var item = query(for: key)
        item[kSecReturnData]  = true as AnyObject
        item[kSecMatchLimit]  = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(item as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    // MARK: Delete

    static func delete(_ key: KeychainKey) {
        SecItemDelete(query(for: key) as CFDictionary)
    }

    static func deleteAll() {
        KeychainKey.allCases.forEach { delete($0) }
    }

    // MARK: JWT Helpers

    /// Decode the `exp` claim from a JWT without verifying the signature.
    /// Used to decide when to refresh — trust is based on Keychain storage, not self-verification.
    static func jwtIsExpiredOrExpiringSoon(_ jwt: String, buffer: TimeInterval = 300) -> Bool {
        let parts = jwt.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return true }

        // Base64URL → Base64
        var padded = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }

        guard let data = Data(base64Encoded: padded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval
        else { return true }

        return Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(buffer)
    }

    // MARK: Private

    private static func query(for key: KeychainKey) -> [CFString: AnyObject] {
        [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  serviceName as AnyObject,
            kSecAttrAccount:  key.rawValue as AnyObject,
            kSecAttrAccessible: accessibility,
        ]
    }
}
