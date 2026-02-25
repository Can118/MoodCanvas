import Contacts
import Foundation

/// Reads the device contact list, normalizes phone numbers to E.164,
/// then asks the match-contacts Edge Function which are on MoodCanvas.
///
/// Security notes:
/// • Phone numbers are transmitted over HTTPS to our Edge Function only.
/// • The Edge Function hashes them server-side — plaintext numbers never touch the DB.
/// • Contact names are never sent to the server.
/// • We read phone numbers only (no names, photos, emails, etc.).
@MainActor
class ContactsService: ObservableObject {

    @Published var matchedUsers: [User] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?

    var authService: AuthService?

    private let contactStore = CNContactStore()

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

        // 1. Read phone numbers only (never contact names or other PII)
        let rawNumbers = await readPhoneNumbers()
        guard !rawNumbers.isEmpty else { return }

        // 2. Normalize and deduplicate
        let normalized = Array(
            Set(rawNumbers.compactMap { normalizeE164($0) })
        )
        guard !normalized.isEmpty else { return }

        // 3. Match via Edge Function (server hashes, we never see the hash)
        do {
            matchedUsers = try await EdgeFunctionService.matchContacts(
                phoneNumbers: normalized,
                jwt: jwt
            )
        } catch let error as MCError {
            errorMessage = error.localizedDescription
        } catch {
            // Generic fallback — don't expose raw error
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

    // MARK: - Private

    private func readPhoneNumbers() async -> [String] {
        await withCheckedContinuation { continuation in
            var numbers: [String] = []

            // Fetch ONLY phone numbers — no names, emails, photos, etc.
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            do {
                try contactStore.enumerateContacts(with: request) { contact, _ in
                    for phone in contact.phoneNumbers {
                        numbers.append(phone.value.stringValue)
                    }
                }
            } catch {
                // Log error type only — never log contact data
                #if DEBUG
                print("[Contacts] Enumeration error type: \(type(of: error))")
                #endif
            }

            continuation.resume(returning: numbers)
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
