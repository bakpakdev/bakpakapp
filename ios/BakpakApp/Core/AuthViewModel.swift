import Combine
import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: User? {
        didSet { AccountScopedDefaults.bind(userId: user?.id) }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Mid-signup: waiting for the student to open the verification link in email.
    @Published var isAwaitingEmailVerification = false
    /// Deep link from the email was opened and Supabase confirmed the address server-side.
    @Published var emailConfirmationLinkOpened = false
    /// Student tapped **Confirm email** in the app (required before Continue / password).
    @Published var hasVerifiedSignupEmail = false
    /// First-time signup only — profile setup before home.
    @Published var needsOnboarding = false
    /// Password accepted; waiting on the authenticator code before entering the app.
    @Published var pendingLoginMFA = false
    /// Set when a password-reset email link opens the app; shows the new-password screen.
    @Published var pendingPasswordResetToken: String?
    /// Legacy Express API base URL (used only when Supabase is not configured).
    @Published var baseURL = PaymentsConfig.apiBaseURL

    private let legacyAuth = AuthService()
    private static let baseURLDefaultsKey = "popup.apiBaseURL"
    private static let onboardingRequiredPrefix = "popup.onboarding.required."
    private static let awaitingEmailKey = "popup.signup.awaitingEmail"
    private static let signupEmailKey = "popup.signup.email"
    private static let linkOpenedKey = "popup.signup.linkOpened.fromEmail"
    /// Temporary password used only until the student sets their real password.
    private var pendingTempPassword: String? {
        get { KeychainManager.shared.readSignupTempPassword() }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainManager.shared.saveSignupTempPassword(newValue)
            } else {
                KeychainManager.shared.clearSignupTempPassword()
            }
        }
    }
    private var pendingSignupEmail: String? {
        get { UserDefaults.standard.string(forKey: Self.signupEmailKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: Self.signupEmailKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.signupEmailKey)
            }
        }
    }

    var usesSupabase: Bool { SupabaseConfig.isConfigured }

    /// Debug-only signup address that skips email confirmation. The API honors it only when
    /// DEMO_BYPASS_ENABLED=true and NODE_ENV isn't production; keep in sync with DEMO_BYPASS_EMAIL.
    static func isDemoBypassEmail(_ email: String) -> Bool {
        #if DEBUG
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == demoBypassEmail
        #else
        return false
        #endif
    }

    #if DEBUG
    static let demoBypassEmail = "demo@popupdev.test"
    #endif

    /// Show the in-app confirm gate (link opened, Confirm not tapped yet).
    var needsInAppEmailConfirm: Bool {
        isAwaitingEmailVerification && emailConfirmationLinkOpened && !hasVerifiedSignupEmail
    }

    /// Email address mid-signup (for restoring the verify screen).
    var pendingVerificationEmail: String? { pendingSignupEmail }

    init() {
        // The editable "API server" override only exists for the legacy Express auth path.
        // With Supabase configured, always use the build's API_BASE_URL so a saved
        // localhost override can't hijack TestFlight / App Store builds.
        if !usesSupabase,
           let saved = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = saved
        }
        APIClient.shared.setBaseURL(baseURL)
        restorePersistedSignupGate()

        if usesSupabase {
            Task { @MainActor in await restoreSupabaseSession() }
        } else if KeychainManager.shared.readToken() != nil {
            isAuthenticated = true
            Task { @MainActor in await refreshMeLegacy() }
        }
    }

    private func restorePersistedSignupGate() {
        isAwaitingEmailVerification = UserDefaults.standard.bool(forKey: Self.awaitingEmailKey)
        emailConfirmationLinkOpened = UserDefaults.standard.bool(forKey: Self.linkOpenedKey)
        // Never restore "confirmed in app" — that tap must happen this session after the link.
        hasVerifiedSignupEmail = false
    }

    private func persistSignupGate() {
        UserDefaults.standard.set(isAwaitingEmailVerification, forKey: Self.awaitingEmailKey)
        UserDefaults.standard.set(emailConfirmationLinkOpened, forKey: Self.linkOpenedKey)
    }

    func applyServerURL() {
        APIClient.shared.setBaseURL(baseURL)
        UserDefaults.standard.set(baseURL, forKey: Self.baseURLDefaultsKey)
    }

    // MARK: - Supabase

    private func restoreSupabaseSession() async {
        guard let client = SupabaseManager.shared.client() else { return }
        do {
            let session = try await client.auth.session
            guard session.user.emailConfirmedAt != nil else {
                // Don't sign out mid-signup — TestFlight cold-opens the confirm
                // deep link in parallel with this restore, and a signOut here
                // races verifyOTP.
                if !isAwaitingEmailVerification {
                    try? await client.auth.signOut()
                }
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                return
            }
            // Mid-signup: stay on auth until they open the email link, then Confirm in-app.
            if isAwaitingEmailVerification {
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                pendingLoginMFA = false
                return
            }
            if await PayoutMFA.needsLoginChallenge(factors: session.user.factors) {
                pendingLoginMFA = true
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                return
            }
            pendingLoginMFA = false
            user = try await Self.fetchProfile(client: client)
            isAuthenticated = true
            refreshOnboardingFlag()
        } catch {
            isAuthenticated = false
            user = nil
            needsOnboarding = false
        }
    }

    private static func fetchProfile(client: SupabaseClient, userId: String? = nil) async throws -> User {
        let uid: String
        if let userId, !userId.isEmpty {
            uid = userId.lowercased()
        } else {
            uid = try await client.auth.session.user.id.uuidString.lowercased()
        }
        struct Row: Decodable {
            let id: UUID
            let username: String
            let email: String?
            let first_name: String?
            let last_name: String?
            let avatar_url: String?
            let bio: String?
            let shop_name: String?
            let date_of_birth: String?
            let country: String?
            let is_verified: Bool?
        }
        let rows: [Row] = try await client
            .from("profiles")
            .select("id, username, email, first_name, last_name, avatar_url, bio, shop_name, date_of_birth, country, is_verified")
            .eq("id", value: uid)
            .limit(1)
            .execute()
            .value
        guard let r = rows.first else { throw SupabaseDataError.notFound }
        return User(
            id: r.id.uuidString.lowercased(),
            email: r.email,
            username: r.username,
            firstName: r.first_name,
            lastName: r.last_name,
            avatar: r.avatar_url,
            bio: r.bio,
            shopName: r.shop_name,
            dateOfBirth: r.date_of_birth,
            country: r.country,
            isVerified: r.is_verified
        )
    }

    /// After `auth.signUp`, `public.profiles` is inserted by trigger `on_auth_user_created`; allow a short window for it to appear.
    private static func fetchProfileWithRetry(client: SupabaseClient, maxAttempts: Int = 12, delayNanoseconds: UInt64 = 120_000_000) async throws -> User {
        var lastError: Error = SupabaseDataError.notFound
        for attempt in 0..<maxAttempts {
            do {
                return try await fetchProfile(client: client)
            } catch let e as SupabaseDataError where e == .notFound {
                lastError = e
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            } catch {
                throw error
            }
        }
        throw lastError
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if usesSupabase {
            guard let client = SupabaseManager.shared.client() else {
                errorMessage = "Supabase is not configured."
                return
            }
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            do {
                // Stale Simulator keychain sessions make password sign-in throw
                // "Auth session missing" even when the password is correct.
                try? await client.auth.signOut()
                let session = try await signInWithPasswordRetry(
                    client: client,
                    email: trimmedEmail,
                    password: password
                )
                if session.user.emailConfirmedAt == nil {
                    try? await client.auth.signOut()
                    errorMessage = "Confirm your campus email first. Open the popup link we sent, tap Confirm email in the app, then sign in."
                    isAuthenticated = false
                    user = nil
                    needsOnboarding = false
                    pendingLoginMFA = false
                    pendingSignupEmail = trimmedEmail
                    beginAwaitingEmailVerification()
                    return
                }
                if await PayoutMFA.needsLoginChallenge(factors: session.user.factors) {
                    pendingLoginMFA = true
                    isAuthenticated = false
                    user = nil
                    needsOnboarding = false
                    return
                }
                try await finishAuthenticatedSession(
                    client: client,
                    userId: session.user.id.uuidString.lowercased()
                )
            } catch {
                errorMessage = friendlyAuthError(error)
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                pendingLoginMFA = false
            }
            return
        }

        do {
            applyServerURL()
            let response = try await legacyAuth.login(email: email, password: password)
            KeychainManager.shared.saveToken(response.token)
            user = response.user
            isAuthenticated = true
            refreshOnboardingFlag()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Forces another verification email (confirm-signup + magic link fallback).
    @discardableResult
    func resendSignupVerificationEmail(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard usesSupabase, SupabaseManager.shared.client() != nil else {
            errorMessage = "Email verification requires Supabase. Add your project keys and rebuild."
            return false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@"), trimmedEmail.hasSuffix(".edu") else {
            errorMessage = "Use a valid college email ending in .edu."
            return false
        }

        pendingSignupEmail = trimmedEmail
        beginAwaitingEmailVerification()
        isAuthenticated = false

        // Landing-page mail only. Do not call Supabase resend/generateLink — those
        // HTTPS verify URLs are consumed by Mail prefetch on TestFlight.
        let emailed = await deliverCampusConfirmation(email: trimmedEmail)
        if !emailed {
            errorMessage = "We couldn’t send the confirmation email. Tap Resend verification email."
        }
        return emailed
    }

    /// Creates the auth user on our API and emails a TestFlight-safe landing page.
    @discardableResult
    func sendSignupVerificationEmail(
        email: String,
        username: String,
        firstName: String,
        lastName: String,
        school: String
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard usesSupabase, SupabaseManager.shared.client() != nil else {
            errorMessage = "Email verification requires Supabase. Add your project keys and rebuild."
            return false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDemo = Self.isDemoBypassEmail(trimmedEmail)
        guard isDemo || (trimmedEmail.contains("@") && trimmedEmail.hasSuffix(".edu")) else {
            errorMessage = "Use a valid college email ending in .edu."
            return false
        }
        guard trimmedUser.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return false
        }

        let tempPassword = "Tmp!\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))aA1"
        pendingTempPassword = tempPassword
        pendingSignupEmail = trimmedEmail
        beginAwaitingEmailVerification()
        isAuthenticated = false
        user = nil

        do {
            struct CampusRegisterRequest: Encodable {
                let email: String
                let password: String
                let username: String
                let first_name: String
                let last_name: String
                let school: String
            }
            let response: CampusConfirmResponse = try await APIClient.shared.request(
                path: "/auth/campus-register",
                method: "POST",
                body: JSONEncoder().encode(
                    CampusRegisterRequest(
                        email: trimmedEmail,
                        password: tempPassword,
                        username: trimmedUser,
                        first_name: firstName,
                        last_name: lastName,
                        school: school
                    )
                )
            )
            if isDemo, response.confirmed == true {
                // API created the account already confirmed; sign in and skip the email step.
                guard let client = SupabaseManager.shared.client() else { return false }
                _ = try await signInWithPasswordRetry(client: client, email: trimmedEmail, password: tempPassword)
                emailConfirmationLinkOpened = true
                hasVerifiedSignupEmail = true
                persistSignupGate()
                errorMessage = nil
                return true
            }
            if response.emailed != true {
                errorMessage = response.message ?? "We couldn’t send the confirmation email. Tap Resend verification email."
                return false
            }
            errorMessage = nil
            return true
        } catch {
            // The API refused the signup (bad email, taken username, server down), so no
            // email went out. Leave the verify gate, or the next launch opens on a
            // "We sent a link" screen for an account that was never created.
            isAwaitingEmailVerification = false
            pendingSignupEmail = nil
            pendingTempPassword = nil
            persistSignupGate()
            errorMessage = friendlyAuthError(error)
            return false
        }
    }

    private func beginAwaitingEmailVerification() {
        isAwaitingEmailVerification = true
        emailConfirmationLinkOpened = false
        hasVerifiedSignupEmail = false
        persistSignupGate()
    }

    private struct CampusConfirmResponse: Decodable {
        let emailed: Bool?
        let confirmed: Bool?
        let message: String?
    }

    /// Asks our API to also email the confirmation link (UO often drops Supabase's mailer).
    /// Never confirms the address itself: only the student clicking the link does that.
    @discardableResult
    func deliverCampusConfirmation(email: String) async -> Bool {
        do {
            let body = try JSONEncoder().encode(["email": email])
            let response: CampusConfirmResponse = try await APIClient.shared.request(
                path: "/auth/campus-confirm",
                method: "POST",
                body: body
            )
            return response.emailed == true
        } catch {
            print("campus-confirm: \(error.localizedDescription)")
            return false
        }
    }

    private func finishAuthenticatedSession(client: SupabaseClient, userId: String? = nil) async throws {
        clearSignupVerificationState()
        pendingLoginMFA = false
        user = try await Self.fetchProfile(client: client, userId: userId)
        isAuthenticated = true
        refreshOnboardingFlag()
        KeychainManager.shared.clearToken()
    }

    func verifyLoginMFA(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard usesSupabase, let client = SupabaseManager.shared.client() else {
            errorMessage = "Supabase is not configured."
            return
        }
        do {
            try await PayoutMFA.verifyLoginCode(code)
            try await finishAuthenticatedSession(client: client)
        } catch {
            pendingLoginMFA = true
            isAuthenticated = false
            user = nil
            errorMessage = "That code didn’t match. Open Passwords and enter the current 6-digit code for popup."
        }
    }

    func cancelLoginMFA() async {
        pendingLoginMFA = false
        errorMessage = nil
        isAuthenticated = false
        user = nil
        needsOnboarding = false
        guard let client = SupabaseManager.shared.client() else { return }
        try? await client.auth.signOut()
    }

    private func signInWithPasswordRetry(
        client: SupabaseClient,
        email: String,
        password: String
    ) async throws -> Session {
        do {
            return try await client.auth.signIn(email: email, password: password)
        } catch {
            guard isAuthSessionMissing(error) else { throw error }
            try? await client.auth.signOut()
            return try await client.auth.signIn(email: email, password: password)
        }
    }

    private func isAuthSessionMissing(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("session missing")
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if isAuthSessionMissing(error) {
            return "Couldn’t start your session. Try signing in again — if it keeps happening, confirm your campus email first."
        }
        if lower.contains("invalid login") || lower.contains("invalid credentials") {
            return "That email or password doesn’t match. Try again, or register if you don’t have an account yet."
        }
        if lower.contains("email not confirmed") {
            return "Confirm your campus email first. Open the popup link we sent, tap Confirm email in the app, then sign in."
        }
        if lower.contains("redirect") || lower.contains("not allowed") {
            return "Verification email blocked by redirect URL settings. In Supabase → Authentication → URL Configuration, add: \(SupabaseConfig.authRedirectURL.absoluteString)"
        }
        if lower.contains("rate") || lower.contains("limit") {
            return "Supabase hit its email rate limit. Wait a few minutes, or add custom SMTP under Project Settings → Authentication."
        }
        return message
    }

    /// Handles `popup://auth-callback` after the student taps the email confirmation link.
    /// Does **not** unlock Continue — they must tap Confirm email in the app.
    func handleAuthRedirect(_ url: URL) async {
        guard usesSupabase, let client = SupabaseManager.shared.client() else { return }
        guard url.scheme == "popup" else { return }

        let params = Self.authCallbackParams(url)
        if let resetToken = params["reset_token"], !resetToken.isEmpty {
            errorMessage = nil
            pendingPasswordResetToken = resetToken
            return
        }
        if let errorText = params["error_description"] ?? params["error"], !errorText.isEmpty {
            errorMessage = friendlyConfirmLinkError(message: errorText)
            persistSignupGate()
            return
        }

        do {
            let session: Session
            if let campusToken = params["campus_token"], !campusToken.isEmpty {
                if let confirmed = try await confirmCampusToken(campusToken) {
                    session = confirmed
                } else {
                    persistSignupGate()
                    return
                }
            } else if let tokenHash = params["token_hash"] ?? params["token"], !tokenHash.isEmpty {
                let otpType = Self.emailOTPType(from: params["type"])
                if let verified = try await Self.verifyEmailTokenHash(client: client, tokenHash: tokenHash, type: otpType) {
                    session = verified
                } else if let existing = try? await client.auth.session, existing.user.emailConfirmedAt != nil {
                    session = existing
                } else {
                    errorMessage = "That link didn’t confirm your email. Tap Resend verification email and try the new link."
                    persistSignupGate()
                    return
                }
            } else if params["code"] != nil || params["access_token"] != nil {
                session = try await client.auth.session(from: url)
            } else {
                return
            }

            guard session.user.emailConfirmedAt != nil else {
                try? await client.auth.signOut()
                errorMessage = "That link didn’t confirm your email. Tap Resend verification email and try the new link."
                emailConfirmationLinkOpened = false
                hasVerifiedSignupEmail = false
                isAuthenticated = false
                user = nil
                persistSignupGate()
                return
            }

            errorMessage = nil

            let midSignup = isAwaitingEmailVerification
                || pendingSignupEmail != nil
                || UserDefaults.standard.bool(forKey: Self.awaitingEmailKey)

            if midSignup {
                isAwaitingEmailVerification = true
                emailConfirmationLinkOpened = true
                hasVerifiedSignupEmail = false
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                if let email = session.user.email?.lowercased(), !email.isEmpty {
                    pendingSignupEmail = email
                }
                persistSignupGate()
                return
            }

            user = try await Self.fetchProfileWithRetry(client: client)
            isAuthenticated = true
            KeychainManager.shared.clearToken()
            refreshOnboardingFlag()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = friendlyConfirmLinkError(message: error.localizedDescription)
            persistSignupGate()
        }
    }

    private struct CampusVerifyResponse: Decodable {
        let confirmed: Bool?
        let email: String?
        let message: String?
    }

    /// Confirms via our hosted API so TestFlight never depends on a Supabase verify URL.
    private func confirmCampusToken(_ token: String) async throws -> Session? {
        guard let client = SupabaseManager.shared.client() else { return nil }
        let response: CampusVerifyResponse = try await APIClient.shared.request(
            path: "/auth/campus-verify",
            method: "POST",
            body: try JSONEncoder().encode(["token": token])
        )
        guard response.confirmed == true else {
            errorMessage = response.message
                ?? "That confirmation link expired. Tap Resend verification email, then open the new one on this phone."
            return nil
        }
        if let email = response.email?.lowercased(), !email.isEmpty {
            pendingSignupEmail = email
        }
        if let email = pendingSignupEmail, let temp = pendingTempPassword {
            var session = try await signInWithPasswordRetry(client: client, email: email, password: temp)
            if session.user.emailConfirmedAt == nil {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let refreshed = try? await client.auth.session {
                    session = refreshed
                }
            }
            return session
        }
        if let existing = try? await client.auth.session, existing.user.emailConfirmedAt != nil {
            return existing
        }
        isAwaitingEmailVerification = true
        emailConfirmationLinkOpened = true
        hasVerifiedSignupEmail = false
        isAuthenticated = false
        user = nil
        persistSignupGate()
        return nil
    }

    private static func authCallbackParams(_ url: URL) -> [String: String] {
        var items: [String: String] = [:]
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in comps.queryItems ?? [] {
                if let value = item.value, !value.isEmpty {
                    items[item.name] = value
                }
            }
        }
        if let fragment = url.fragment {
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                items[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return items
    }

    private static func verifyEmailTokenHash(
        client: SupabaseClient,
        tokenHash: String,
        type: EmailOTPType
    ) async throws -> Session? {
        do {
            return try await client.auth.verifyOTP(tokenHash: tokenHash, type: type).session
        } catch {
            if type != .magiclink {
                return try await client.auth.verifyOTP(tokenHash: tokenHash, type: .magiclink).session
            }
            throw error
        }
    }

    private static func emailOTPType(from raw: String?) -> EmailOTPType {
        switch (raw ?? "signup").lowercased() {
        case "magiclink": return .magiclink
        case "recovery": return .recovery
        case "invite": return .invite
        case "email_change", "emailchange": return .emailChange
        default: return .signup
        }
    }

    private func friendlyConfirmLinkError(message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("expir") || lower.contains("otp") || lower.contains("invalid") {
            return "That confirmation link expired. Tap Resend verification email, then open the new one on this phone."
        }
        if lower.contains("cancel") || lower.contains("denied") || lower.contains("pkce") || lower.contains("verifier") {
            return "That confirmation link didn’t open in popup. Tap Resend verification email and use Open popup on this phone."
        }
        return "Couldn’t confirm that email link. Tap Resend verification email and try again."
    }

    /// Called when the student taps **Confirm email** in the app after opening the link.
    @discardableResult
    func confirmSignupEmailInApp() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard usesSupabase, let client = SupabaseManager.shared.client() else {
            errorMessage = "Supabase is not configured."
            return false
        }
        guard isAwaitingEmailVerification, emailConfirmationLinkOpened else {
            errorMessage = "Open the popup link in your email first, then tap Confirm."
            return false
        }

        do {
            let session: Session
            if let existing = try? await client.auth.session, existing.user.emailConfirmedAt != nil {
                session = existing
            } else if let email = pendingSignupEmail, let temp = pendingTempPassword {
                session = try await client.auth.signIn(email: email, password: temp)
            } else {
                errorMessage = "Open the link in your popup email first, then tap Confirm."
                return false
            }

            guard session.user.emailConfirmedAt != nil else {
                try? await client.auth.signOut()
                errorMessage = "Your email isn’t confirmed yet. Open the popup link we sent, then try again."
                emailConfirmationLinkOpened = false
                hasVerifiedSignupEmail = false
                persistSignupGate()
                return false
            }

            emailConfirmationLinkOpened = true
            hasVerifiedSignupEmail = true
            isAuthenticated = false
            user = nil
            persistSignupGate()
            return true
        } catch {
            errorMessage = "Open the link in your popup email first, then tap Confirm."
            return false
        }
    }

    func clearSignupVerificationState() {
        isAwaitingEmailVerification = false
        emailConfirmationLinkOpened = false
        hasVerifiedSignupEmail = false
        pendingTempPassword = nil
        pendingSignupEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.awaitingEmailKey)
        UserDefaults.standard.removeObject(forKey: Self.linkOpenedKey)
        UserDefaults.standard.removeObject(forKey: Self.signupEmailKey)
    }

    /// After email is verified, set password and finish signing the student in.
    func completeSignupWithPassword(
        password: String,
        firstName: String,
        lastName: String,
        school: String
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard usesSupabase, let client = SupabaseManager.shared.client() else {
            errorMessage = "Supabase is not configured."
            return
        }

        guard hasVerifiedSignupEmail else {
            errorMessage = "Verify your email before creating a password."
            return
        }

        guard Self.passwordMeetsRules(password) else {
            errorMessage = Self.passwordRulesMessage
            return
        }

        do {
            // Ensure we have a session (deep link or temp-password sign-in).
            do {
                _ = try await client.auth.session
            } catch {
                if let email = pendingSignupEmail, let temp = pendingTempPassword {
                    try await client.auth.signIn(email: email, password: temp)
                } else {
                    throw error
                }
            }

            _ = try await client.auth.update(
                user: UserAttributes(
                    password: password,
                    data: [
                        "first_name": .string(firstName),
                        "last_name": .string(lastName),
                        "school": .string(school),
                    ]
                )
            )

            let session = try await client.auth.session
            guard session.user.emailConfirmedAt != nil else {
                try? await client.auth.signOut()
                errorMessage = "Confirm your campus email before creating a password."
                isAuthenticated = false
                user = nil
                hasVerifiedSignupEmail = false
                return
            }
            let uid = session.user.id.uuidString.lowercased()
            struct ProfilePatch: Encodable {
                let first_name: String
                let last_name: String
                let country: String
            }
            try await client
                .from("profiles")
                .update(ProfilePatch(first_name: firstName, last_name: lastName, country: school))
                .eq("id", value: uid)
                .execute()

            user = try await Self.fetchProfileWithRetry(client: client)
            isAuthenticated = true
            markNeedsOnboardingForCurrentUser()
            clearSignupVerificationState()
            KeychainManager.shared.clearToken()
        } catch {
            errorMessage = Self.isPasswordRuleError(error) ? Self.passwordRulesMessage : error.localizedDescription
            isAuthenticated = false
            user = nil
        }
    }

    // MARK: Password reset

    private struct PasswordResetResponse: Decodable {
        let message: String?
        let email: String?
    }

    /// Emails a reset link (our landing page → `popup://auth-callback?reset_token=…`).
    /// Returns the message to show; the API answers the same whether or not the account exists.
    func requestPasswordReset(email: String) async -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else {
            errorMessage = "Enter the email you signed up with."
            return nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: PasswordResetResponse = try await APIClient.shared.request(
                path: "/auth/password-reset",
                method: "POST",
                body: JSONEncoder().encode(["email": trimmed])
            )
            return response.message ?? "Check your email for a reset link."
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Sets the new password from a reset link, then signs in with it (2FA still applies).
    func completePasswordReset(newPassword: String) async {
        guard let token = pendingPasswordResetToken else { return }
        guard Self.passwordMeetsRules(newPassword) else {
            errorMessage = Self.passwordRulesMessage
            return
        }
        isLoading = true
        errorMessage = nil
        let email: String
        do {
            struct Body: Encodable { let token: String; let password: String }
            let response: PasswordResetResponse = try await APIClient.shared.request(
                path: "/auth/password-reset/complete",
                method: "POST",
                body: JSONEncoder().encode(Body(token: token, password: newPassword))
            )
            email = response.email ?? ""
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return
        }
        isLoading = false
        pendingPasswordResetToken = nil
        guard !email.isEmpty else { return }
        if isAuthenticated { await logoutAsync() }
        await login(email: email, password: newPassword)
    }

    // MARK: Password rules

    /// Mirrors the Supabase project's password policy (min length + lower, upper, digit).
    struct PasswordRule: Identifiable {
        let id: String
        let label: String
        let isMet: (String) -> Bool
    }

    static let passwordRules: [PasswordRule] = [
        PasswordRule(id: "length", label: "At least 6 characters") { $0.count >= 6 },
        PasswordRule(id: "lower", label: "One lowercase letter") { $0.contains(where: \.isLowercase) },
        PasswordRule(id: "upper", label: "One uppercase letter") { $0.contains(where: \.isUppercase) },
        PasswordRule(id: "digit", label: "One number") { $0.contains(where: \.isNumber) },
    ]

    static let passwordRulesMessage = "Use at least 6 characters with a lowercase letter, an uppercase letter, and a number."

    static func passwordMeetsRules(_ password: String) -> Bool {
        passwordRules.allSatisfy { $0.isMet(password) }
    }

    /// Supabase returns e.g. "Password should contain at least one character of each: abcdef…"
    private static func isPasswordRuleError(_ error: Error) -> Bool {
        let lower = error.localizedDescription.lowercased()
        return lower.contains("password should") || lower.contains("weak password") || lower.contains("weak_password")
    }

    /// Call after first-time profile setup finishes.
    func completeOnboarding() {
        if let id = user?.id {
            UserDefaults.standard.set(false, forKey: Self.onboardingRequiredPrefix + id)
        }
        needsOnboarding = false
    }

    private func markNeedsOnboardingForCurrentUser() {
        guard let id = user?.id else {
            needsOnboarding = true
            return
        }
        UserDefaults.standard.set(true, forKey: Self.onboardingRequiredPrefix + id)
        needsOnboarding = true
    }

    private func refreshOnboardingFlag() {
        guard let id = user?.id else {
            needsOnboarding = false
            return
        }
        needsOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingRequiredPrefix + id)
    }

    func register(email: String, username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if usesSupabase {
            guard let client = SupabaseManager.shared.client() else {
                errorMessage = "Supabase is not configured."
                return
            }
            do {
                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedEmail.isEmpty, !password.isEmpty else {
                    errorMessage = "Email and password are required."
                    return
                }
                guard trimmedUser.count >= 3 else {
                    errorMessage = "Username must be at least 3 characters."
                    return
                }

                let signupResult = try await client.auth.signUp(
                    email: trimmedEmail,
                    password: password,
                    data: ["username": .string(trimmedUser)]
                )

                let session = signupResult.session
                if session == nil || session?.user.emailConfirmedAt == nil {
                    try? await client.auth.signOut()
                    pendingSignupEmail = trimmedEmail
                    beginAwaitingEmailVerification()
                    isAuthenticated = false
                    user = nil
                    errorMessage = "Confirm your campus email first. Open the popup link we sent, tap Confirm email in the app, then sign in."
                    return
                }

                user = try await Self.fetchProfileWithRetry(client: client)
                isAuthenticated = true
                markNeedsOnboardingForCurrentUser()
                KeychainManager.shared.clearToken()
            } catch {
                errorMessage = error.localizedDescription
                isAuthenticated = false
                user = nil
            }
            return
        }

        do {
            applyServerURL()
            let response = try await legacyAuth.register(email: email, username: username, password: password)
            KeychainManager.shared.saveToken(response.token)
            user = response.user
            isAuthenticated = true
            markNeedsOnboardingForCurrentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMe() async {
        if usesSupabase, let client = SupabaseManager.shared.client() {
            do {
                let session = try await client.auth.session
                guard session.user.emailConfirmedAt != nil else {
                    try? await client.auth.signOut()
                    isAuthenticated = false
                    user = nil
                    return
                }
                let profile = try await Self.fetchProfile(client: client)
                guard !Task.isCancelled else { return }
                user = profile
                isAuthenticated = true
            } catch is CancellationError {
                // Tab switches cancel Profile's `.task` — don't bounce to login.
                return
            } catch {
                // Keep a signed-in session on transient network blips.
                if !isAuthenticated {
                    user = nil
                }
            }
            return
        }
        await refreshMeLegacy()
    }

    private func refreshMeLegacy() async {
        do {
            let me = try await legacyAuth.me()
            guard !Task.isCancelled else { return }
            user = me
            isAuthenticated = true
        } catch is CancellationError {
            return
        } catch {
            if !isAuthenticated {
                user = nil
            }
        }
    }

    /// Verifies the password on the API and permanently deletes the Supabase user.
    /// Caller should clear navigation, then call `logoutAsync()` on success.
    func deleteAccount(password: String) async -> String? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            return "Enter your password to delete your account."
        }

        do {
            let body = try JSONEncoder().encode(["password": trimmed])
            let _: APIMessage = try await APIClient.shared.request(
                path: "/auth/delete-account",
                method: "POST",
                body: body
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Clears the local session. Prefer `logoutAsync()` so callers can reset navigation first.
    func logout() {
        Task { await logoutAsync() }
    }

    /// Local UI clears immediately; remote `signOut` is bounded so TestFlight can't hang.
    func logoutAsync() async {
        KeychainManager.shared.clearToken()
        clearSignupVerificationState()

        // Drop the authenticated shell without waiting on the network.
        isAuthenticated = false
        user = nil
        needsOnboarding = false
        pendingLoginMFA = false

        guard usesSupabase, let client = SupabaseManager.shared.client() else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await client.auth.signOut()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}
