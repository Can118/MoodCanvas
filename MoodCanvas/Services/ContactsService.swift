import Contacts
import Foundation

/// Reads the device contact list, normalizes phone numbers to E.164,
/// then asks the match-contacts Edge Function which are on MoodCanvas.
///
/// Security notes:
/// • Phone numbers are transmitted over HTTPS to our Edge Function only.
/// • The Edge Function hashes them server-side — plaintext numbers never touch the DB.
/// • Contact names are never sent to the server.
/// • We read phone numbers and names only (names stay on-device — never transmitted).
/// A device contact entry with optional Moodi user attached.
struct ContactEntry: Identifiable {
    var id: String { phone }
    let name: String
    let phone: String          // normalized E.164
    let moodiUser: User?       // non-nil if this person is on Moodi
    var isOnMoodi: Bool { moodiUser != nil }
}

@MainActor
class ContactsService: ObservableObject {

    @Published var matchedUsers: [User] = []
    /// Full device contact list, with Moodi status resolved. Populated by fetchAllContactsAndMatch().
    @Published var allContactEntries: [ContactEntry] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?

    var authService: AuthService?

    private let contactStore = CNContactStore()
    private static let cacheKey = "contact_name_cache_v1"

    // MARK: - Public

    func fetchAndMatch() async {
        await authService?.refreshJWTIfNeeded()
        guard let jwt = KeychainService.load(.supabaseJWT) else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 1. Read phone numbers + contact names (names stay on-device, never sent)
        let contacts = await readContacts()
        guard !contacts.isEmpty else { return }

        // 2. Build local phone → contactName map (never leaves the device)
        var phoneToName: [String: String] = [:]
        for (rawPhone, contactName) in contacts {
            if let e164 = normalizeE164(rawPhone) {
                phoneToName[e164] = contactName
            }
        }

        // 3. Normalize and deduplicate phone numbers for the server call
        let normalized = Array(Set(contacts.compactMap { normalizeE164($0.phone) }))
        guard !normalized.isEmpty else { return }

        // 4. Match via Edge Function — server hashes, we never see the hash.
        //    Server now echoes back the matched phone so we can resolve contact names.
        do {
            let matched = try await EdgeFunctionService.matchContacts(
                phoneNumbers: normalized,
                jwt: jwt
            )
            matchedUsers = matched

            // 5. Build userId → contactName map using the echoed phone numbers
            //    and save it persistently so invitation cards can resolve names later.
            var idToName: [String: String] = Self.loadContactNameCache()
            for user in matched where !user.phoneNumber.isEmpty {
                if let name = phoneToName[user.phoneNumber] {
                    idToName[user.id] = name
                }
            }
            Self.saveContactNameCache(idToName)

        } catch let error as MCError {
            errorMessage = error.localizedDescription
        } catch {
            // Generic fallback — don't expose raw error
            errorMessage = "Could not load contacts. Please try again."
        }
    }

    /// Reads ALL device contacts, matches them against Moodi users, and
    /// populates `allContactEntries` with Moodi status attached to each entry.
    func fetchAllContactsAndMatch() async {
        await authService?.refreshJWTIfNeeded()
        guard let jwt = KeychainService.load(.supabaseJWT) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let rawContacts = await readContacts()
        guard !rawContacts.isEmpty else { return }

        // Build phone → display name map (local only, never sent)
        var phoneToName: [String: String] = [:]
        for (rawPhone, name) in rawContacts {
            if let e164 = normalizeE164(rawPhone) {
                if phoneToName[e164] == nil { phoneToName[e164] = name }
            }
        }
        let uniquePhones = Array(phoneToName.keys)

        // Build entry list from local device data first — alphabetically, no Moodi status yet.
        // This ensures contacts are shown even if the server call fails.
        allContactEntries = uniquePhones
            .compactMap { phone -> ContactEntry? in
                guard let name = phoneToName[phone] else { return nil }
                return ContactEntry(name: name, phone: phone, moodiUser: nil)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        do {
            let matched = try await EdgeFunctionService.matchContacts(
                phoneNumbers: uniquePhones,
                jwt: jwt
            )
            matchedUsers = matched

            // Build phone → Moodi user map for O(1) lookup
            var moodiByPhone: [String: User] = [:]
            for user in matched where !user.phoneNumber.isEmpty {
                moodiByPhone[user.phoneNumber] = user
            }

            // Update contact name cache
            var idToName = Self.loadContactNameCache()
            for user in matched where !user.phoneNumber.isEmpty {
                if let name = phoneToName[user.phoneNumber] { idToName[user.id] = name }
            }
            Self.saveContactNameCache(idToName)

            // Re-sort with Moodi status: Moodi users first, then alphabetically
            allContactEntries = uniquePhones
                .compactMap { phone -> ContactEntry? in
                    guard let name = phoneToName[phone] else { return nil }
                    return ContactEntry(name: name, phone: phone, moodiUser: moodiByPhone[phone])
                }
                .sorted {
                    if $0.isOnMoodi != $1.isOnMoodi { return $0.isOnMoodi }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

        } catch let error as MCError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Could not load contacts. Please try again."
        }
    }

    /// Search for a single user by manually-entered phone number.
    /// Normalises to E.164 then calls the match-contacts Edge Function.
    /// Merges any found user into `matchedUsers` (deduplicating by id).
    func searchByPhone(_ raw: String) async {
        await authService?.refreshJWTIfNeeded()
        guard let jwt = KeychainService.load(.supabaseJWT) else {
            errorMessage = "Not signed in."
            return
        }
        guard let normalized = normalizeE164(raw) else {
            errorMessage = "Enter a valid number — e.g. +15551234567 or 5551234567."
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let results = try await EdgeFunctionService.matchContacts(
                phoneNumbers: [normalized],
                jwt: jwt
            )
            for user in results where !matchedUsers.contains(where: { $0.id == user.id }) {
                matchedUsers.append(user)
            }
            if results.isEmpty {
                errorMessage = "No MoodCanvas user found for that number."
            }
        } catch MCError.edgeFunction(let msg) where msg.lowercased().contains("unauthorized") {
            errorMessage = "Session expired — restart the app and try again."
        } catch MCError.rateLimited {
            errorMessage = "Too many searches. Wait a minute and try again."
        } catch {
            errorMessage = "Search failed (\(error.localizedDescription)). Try restarting the app."
        }
    }

    // MARK: - Contact Name Cache

    /// Returns the contact-saved name for a given MoodCanvas user ID, or nil if unknown.
    static func contactDisplayName(forUserId id: String) -> String? {
        loadContactNameCache()[id]
    }

    static func loadContactNameCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveContactNameCache(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Private

    /// Reads phone numbers AND full names from the device contacts.
    /// Names are used only locally to build the userId→contactName cache.
    private func readContacts() async -> [(phone: String, name: String)] {
        await withCheckedContinuation { continuation in
            var entries: [(phone: String, name: String)] = []

            let keysToFetch: [CNKeyDescriptor] = [
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactGivenNameKey   as CNKeyDescriptor,
                CNContactFamilyNameKey  as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                try contactStore.enumerateContacts(with: request) { contact, _ in
                    let full = [contact.givenName, contact.familyName]
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let displayName = full.isEmpty ? "Unknown" : full
                    for phone in contact.phoneNumbers {
                        entries.append((phone: phone.value.stringValue, name: displayName))
                    }
                }
            } catch {
                #if DEBUG
                print("[Contacts] Enumeration error type: \(type(of: error))")
                #endif
            }

            continuation.resume(returning: entries)
        }
    }

    /// Normalizes a raw phone string to E.164.
    /// Returns nil for strings that can't be reliably converted.
    func normalizeE164(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        let e164: String
        switch digits.count {
        case 10:                              e164 = "+1\(digits)"
        case 11 where digits.hasPrefix("1"): e164 = "+\(digits)"
        case 7...15:                          e164 = "+\(digits)"
        default:                              return nil
        }
        // Validate E.164 regex before returning
        guard e164.range(of: #"^\+[1-9]\d{6,14}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return e164
    }
}
