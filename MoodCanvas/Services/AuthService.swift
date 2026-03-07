import Foundation
import FirebaseAuth

@MainActor
class AuthService: ObservableObject {

    @Published var isAuthenticated = false
    @Published var needsNameEntry = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    /// True from init until the first Firebase auth-state callback resolves.
    /// During this window we show a neutral blank screen instead of onboarding,
    /// so a returning user never sees a flash of the login flow.
    @Published var isRestoringSession = true

    private var verificationID: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Init / Session Restore

    init() {
        // Firebase notifies us once it resolves the persisted session (async).
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let firebaseUser {
                    await self.restoreSession(for: firebaseUser)
                } else {
                    self.clearSession()
                }
                // Auth state is now definitively known — stop showing the
                // blank splash screen regardless of outcome.
                self.isRestoringSession = false
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Phone Auth — Step 1

    func sendVerificationCode(to rawPhone: String) async {
        errorMessage = nil
        guard let e164 = normalizeE164(rawPhone) else {
            errorMessage = "Please enter a valid phone number."
            return
        }
        do {
            verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(e164, uiDelegate: nil)
        } catch {
            errorMessage = friendlyFirebaseError(error)
        }
    }

    // MARK: - Phone Auth — Step 2

    func verifyCode(_ code: String, for rawPhone: String) async {
        errorMessage = nil
        guard let verificationID else {
            errorMessage = "Session expired. Please request a new code."
            return
        }
        guard isValidOTP(code) else {
            errorMessage = "Code must be 6 digits."
            return
        }

        do {
            // 1. Firebase sign-in
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            let result = try await Auth.auth().signIn(with: credential)

            // 2. Get short-lived Firebase ID token
            let idToken = try await result.user.getIDToken()

            // 3. Exchange for Supabase JWT via Edge Function (phone hashed server-side)
            let jwt = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)

            // 4. Persist to Keychain — never UserDefaults
            KeychainService.save(.firebaseUID, value: result.user.uid)
            KeychainService.save(.supabaseJWT, value: jwt)
            if let e164 = normalizeE164(rawPhone) {
                KeychainService.save(.phoneE164, value: e164)
            }

            // 5. Configure Supabase client with the JWT
            SupabaseService.shared.configure(jwt: jwt)
            storeJWTForWidget(jwt)

            // 6. Build local user object
            currentUser = User(
                id: result.user.uid,
                name: "Me",
                phoneNumber: normalizeE164(rawPhone) ?? rawPhone
            )

            // 7. Fetch actual name from Supabase — determines whether name entry is needed
            await fetchAndConfigureUserName(result.user.uid)

            // 8. Save APNs device token now that we have a confirmed user ID.
            //    fetchGroups() runs after the home screen loads, but APNs registration
            //    may not have completed yet at that point (race condition). Saving here
            //    covers the case where the token arrived before login finished.
            saveDeviceTokenIfAvailable(userId: result.user.uid)

            isAuthenticated = true
            self.verificationID = nil

        } catch let error as MCError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = friendlyFirebaseError(error)
        }
    }

    // MARK: - Name Entry

    /// Called from NameEntryView. Saves the name to Supabase and clears the name-entry gate.
    func setName(_ name: String) async {
        guard let uid = currentUser?.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            try await SupabaseService.shared.updateName(trimmed, userId: uid)
            currentUser?.name = trimmed
            needsNameEntry = false
            // Signal HomeView to request an App Store rating once on first appearance
            UserDefaults.standard.set(true, forKey: "requestRatingAfterOnboarding")
        } catch {
            errorMessage = "Could not save your name. Please try again."
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // Firebase sign-out failed — still clear local state
            #if DEBUG
            print("[Auth] Firebase signOut error: \(error.localizedDescription)")
            #endif
        }
        clearSession()
    }

    // MARK: - JWT Refresh

    /// Called on app foreground or before making an authenticated request.
    func refreshJWTIfNeeded() async {
        guard let jwt = KeychainService.load(.supabaseJWT),
              KeychainService.jwtIsExpiredOrExpiringSoon(jwt)
        else { return }

        guard let firebaseUser = Auth.auth().currentUser else {
            clearSession()
            return
        }

        do {
            let idToken = try await firebaseUser.getIDToken(forcingRefresh: true)
            let newJWT = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)
            KeychainService.save(.supabaseJWT, value: newJWT)
            SupabaseService.shared.configure(jwt: newJWT)
            storeJWTForWidget(newJWT)
        } catch {
            // Could not refresh — session is dead
            clearSession()
        }
    }

    // MARK: - Private Helpers

    private func restoreSession(for firebaseUser: FirebaseAuth.User) async {
        guard let storedUID = KeychainService.load(.firebaseUID),
              storedUID == firebaseUser.uid,
              let jwt = KeychainService.load(.supabaseJWT)
        else {
            // Keychain is inconsistent with Firebase state — clear everything
            clearSession()
            return
        }

        // Refresh JWT if it's near expiry
        let validJWT: String
        if KeychainService.jwtIsExpiredOrExpiringSoon(jwt) {
            do {
                let idToken = try await firebaseUser.getIDToken(forcingRefresh: true)
                validJWT = try await EdgeFunctionService.authenticate(firebaseIDToken: idToken)
                KeychainService.save(.supabaseJWT, value: validJWT)
            } catch {
                clearSession()
                return
            }
        } else {
            validJWT = jwt
        }

        SupabaseService.shared.configure(jwt: validJWT)
        storeJWTForWidget(validJWT)
        currentUser = User(
            id: firebaseUser.uid,
            name: "Me",
            phoneNumber: KeychainService.load(.phoneE164) ?? ""
        )

        // Fetch actual name from Supabase
        await fetchAndConfigureUserName(firebaseUser.uid)

        // Save APNs token if it arrived before session restoration completed
        saveDeviceTokenIfAvailable(userId: firebaseUser.uid)

        isAuthenticated = true
    }

    /// Saves the APNs device token to Supabase if it has already been registered.
    /// Called right after login/session-restore to handle the race condition where
    /// APNs registration completes before the user is authenticated, so fetchGroups()
    /// misses the token on first run.
    private func saveDeviceTokenIfAvailable(userId: String) {
        guard let token = KeychainService.load(.apnsToken) else {
            print("[Auth] APNs token not available yet at auth time — will be saved by fetchGroups() or APNs callback")
            return
        }
        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif
        print("[Auth] APNs token found at auth time — saving to Supabase now (env=\(apnsEnvironment))")
        Task {
            await SupabaseService.shared.saveDeviceToken(token, userId: userId, environment: apnsEnvironment)
        }
    }

    /// Writes the JWT to the App Group so the widget extension can make authenticated calls.
    private func storeJWTForWidget(_ jwt: String) {
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.set(jwt, forKey: "widget_jwt")
    }

    /// Reads the user's name from Supabase and updates the local model.
    /// Sets `needsNameEntry = true` when the name has never been set.
    private func fetchAndConfigureUserName(_ uid: String) async {
        do {
            let name = try await SupabaseService.shared.fetchUserName(userId: uid)
            if let name {
                currentUser?.name = name
                needsNameEntry = false
            } else {
                needsNameEntry = true
            }
        } catch {
            // Network error — don't block the user; they can set their name later
            needsNameEntry = false
        }
    }

    private func clearSession() {
        KeychainService.deleteAll()
        SupabaseService.shared.configure(jwt: nil)
        UserDefaults(suiteName: AppGroupConstants.suiteName)?.removeObject(forKey: "widget_jwt")
        isAuthenticated = false
        needsNameEntry = false
        currentUser = nil
        verificationID = nil
    }

    /// Returns E.164 format or nil if the input is too short/invalid.
    private func normalizeE164(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        switch digits.count {
        case 10:                              return "+1\(digits)"
        case 11 where digits.hasPrefix("1"): return "+\(digits)"
        case 7...15:                          return "+\(digits)"
        default:                              return nil
        }
    }

    private func isValidOTP(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy { $0.isNumber }
    }

    private func friendlyFirebaseError(_ error: Error) -> String {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else {
            // Never expose raw error text — it may contain sensitive info
            return "Something went wrong. Please try again."
        }
        switch code {
        case .invalidPhoneNumber:        return "Invalid phone number."
        case .sessionExpired:            return "Code expired. Request a new one."
        case .invalidVerificationCode:   return "Incorrect code. Try again."
        case .tooManyRequests:           return "Too many attempts. Try again later."
        case .networkError:              return "No internet connection."
        default:                         return "Something went wrong. Please try again."
        }
    }
}
