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
    /// Legacy Express API base URL (used only when Supabase is not configured).
    @Published var baseURL = SquareConfig.apiBaseURL

    private let legacyAuth = AuthService()
    private static let baseURLDefaultsKey = "popup.apiBaseURL"
    private static let onboardingRequiredPrefix = "popup.onboarding.required."
    private static let awaitingEmailKey = "popup.signup.awaitingEmail"
    private static let signupEmailKey = "popup.signup.email"
    private static let linkOpenedKey = "popup.signup.linkOpened"
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
                try? await client.auth.signOut()
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                return
            }
            // Mid-signup: keep them on auth until they Confirm in-app and set a password.
            if isAwaitingEmailVerification {
                if session.user.emailConfirmedAt != nil {
                    emailConfirmationLinkOpened = true
                    persistSignupGate()
                }
                isAuthenticated = false
                user = nil
                needsOnboarding = false
                return
            }
            user = try await Self.fetchProfile(client: client)
            isAuthenticated = true
            refreshOnboardingFlag()
        } catch {
            isAuthenticated = false
            user = nil
            needsOnboarding = false
        }
    }

    private static func fetchProfile(client: SupabaseClient) async throws -> User {
        let session = try await client.auth.session
        let uid = session.user.id.uuidString.lowercased()
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
            do {
                let session = try await client.auth.signIn(email: email, password: password)
                if session.user.emailConfirmedAt == nil {
                    try? await client.auth.signOut()
                    errorMessage = "Confirm your campus email first. Open the popup link we sent, tap Confirm email in the app, then sign in."
                    isAuthenticated = false
                    user = nil
                    needsOnboarding = false
                    pendingSignupEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    beginAwaitingEmailVerification()
                    return
                }
                user = try await Self.fetchProfile(client: client)
                isAuthenticated = true
                refreshOnboardingFlag()
                KeychainManager.shared.clearToken()
            } catch {
                errorMessage = error.localizedDescription
                isAuthenticated = false
                user = nil
                needsOnboarding = false
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

        guard usesSupabase, let client = SupabaseManager.shared.client() else {
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

        var sentConfirm = false
        var sentMagicLink = false
        var lastError: Error?

        // 1) Resend the Confirm signup email.
        do {
            try await client.auth.resend(
                email: trimmedEmail,
                type: .signup,
                emailRedirectTo: SupabaseConfig.authRedirectURL
            )
            sentConfirm = true
        } catch {
            do {
                try await client.auth.resend(
                    email: trimmedEmail,
                    type: .signup,
                    emailRedirectTo: nil
                )
                sentConfirm = true
            } catch {
                lastError = error
            }
        }

        // 2) Also send a magic link — this is what reliably triggers Supabase to deliver mail.
        do {
            try await client.auth.signInWithOTP(
                email: trimmedEmail,
                redirectTo: SupabaseConfig.authRedirectURL,
                shouldCreateUser: false
            )
            sentMagicLink = true
        } catch {
            do {
                try await client.auth.signInWithOTP(
                    email: trimmedEmail,
                    redirectTo: SupabaseConfig.authRedirectURL,
                    shouldCreateUser: true
                )
                sentMagicLink = true
            } catch {
                lastError = error
            }
        }

        if sentConfirm || sentMagicLink {
            return true
        }

        errorMessage = lastError.map(friendlyAuthError) ?? "Couldn’t resend the verification email. Try again in a minute."
        return false
    }

    /// Creates the auth user and sends Supabase’s “Confirm signup” email with a link.
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

        guard usesSupabase, let client = SupabaseManager.shared.client() else {
            errorMessage = "Email verification requires Supabase. Add your project keys and rebuild."
            return false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.hasSuffix(".edu") else {
            errorMessage = "Use a valid college email ending in .edu."
            return false
        }
        guard trimmedUser.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return false
        }

        let metadata: [String: AnyJSON] = [
            "username": .string(trimmedUser),
            "first_name": .string(firstName),
            "last_name": .string(lastName),
            "school": .string(school),
        ]

        // Explicit resend after a successful earlier signup for this email.
        if pendingSignupEmail == trimmedEmail, pendingTempPassword != nil {
            do {
                try await client.auth.resend(
                    email: trimmedEmail,
                    type: .signup,
                    emailRedirectTo: SupabaseConfig.authRedirectURL
                )
                beginAwaitingEmailVerification()
                isAuthenticated = false
                return true
            } catch {
                errorMessage = friendlyAuthError(error)
                return false
            }
        }

        let tempPassword = "Tmp!\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))aA1"

        do {
            let session = try await signUpSendingConfirmation(
                client: client,
                email: trimmedEmail,
                password: tempPassword,
                data: metadata
            )

            pendingTempPassword = tempPassword
            pendingSignupEmail = trimmedEmail

            if session != nil {
                // Confirm email is OFF — sign out and refuse to continue until it's turned on.
                try? await client.auth.signOut()
                errorMessage =
                    "Supabase has “Confirm email” turned off, so no email was sent. Turn it ON under Authentication → Providers → Email, then tap Resend."
                beginAwaitingEmailVerification()
                isAuthenticated = false
                user = nil
                return false
            }

            // No session means confirmation is required — Supabase should have queued the email.
            beginAwaitingEmailVerification()
            isAuthenticated = false
            user = nil
            return true
        } catch {
            let message = error.localizedDescription.lowercased()
            let alreadyRegistered =
                message.contains("already")
                || message.contains("registered")
                || message.contains("exists")
                || message.contains("user_already_exists")

            if alreadyRegistered {
                do {
                    try await client.auth.resend(
                        email: trimmedEmail,
                        type: .signup,
                        emailRedirectTo: SupabaseConfig.authRedirectURL
                    )
                    pendingSignupEmail = trimmedEmail
                    pendingTempPassword = tempPassword
                    beginAwaitingEmailVerification()
                    isAuthenticated = false
                    return true
                } catch {
                    errorMessage = friendlyAuthError(error)
                    return false
                }
            }

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

    /// Signs up and asks Supabase to email a confirmation link.
    /// Retries without a custom redirect if the redirect URL was rejected.
    private func signUpSendingConfirmation(
        client: SupabaseClient,
        email: String,
        password: String,
        data: [String: AnyJSON]
    ) async throws -> Session? {
        do {
            let result = try await client.auth.signUp(
                email: email,
                password: password,
                data: data,
                redirectTo: SupabaseConfig.authRedirectURL
            )
            return result.session
        } catch {
            let message = error.localizedDescription.lowercased()
            let redirectProblem =
                message.contains("redirect")
                || message.contains("url")
                || message.contains("not allowed")
                || message.contains("whitelist")
                || message.contains("allow")
            guard redirectProblem else { throw error }

            // Fall back so the confirmation email still sends even if redirect isn't allowlisted yet.
            let result = try await client.auth.signUp(
                email: email,
                password: password,
                data: data,
                redirectTo: nil
            )
            return result.session
        }
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
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

        do {
            let session = try await client.auth.session(from: url)
            guard session.user.emailConfirmedAt != nil else {
                try? await client.auth.signOut()
                errorMessage = "That link didn’t confirm your email. Request a new popup email and try again."
                emailConfirmationLinkOpened = false
                hasVerifiedSignupEmail = false
                isAuthenticated = false
                user = nil
                persistSignupGate()
                return
            }

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
                // Keep the confirmed session so they can set a password after Confirm.
                return
            }

            // Returning user (e.g. magic link / recovery) — only sign in if email is confirmed.
            user = try await Self.fetchProfileWithRetry(client: client)
            isAuthenticated = true
            KeychainManager.shared.clearToken()
            refreshOnboardingFlag()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        guard isAwaitingEmailVerification else {
            errorMessage = "Start signup and open the email we sent first."
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

    /// Detects that the email link confirmed the address (does not unlock Continue).
    func pollSignupEmailLinkStatus() async {
        guard isAwaitingEmailVerification, !emailConfirmationLinkOpened, !hasVerifiedSignupEmail else { return }
        guard usesSupabase, let client = SupabaseManager.shared.client() else { return }

        if let session = try? await client.auth.session, session.user.emailConfirmedAt != nil {
            emailConfirmationLinkOpened = true
            persistSignupGate()
            isAuthenticated = false
            user = nil
            return
        }

        guard let email = pendingSignupEmail, let temp = pendingTempPassword else { return }
        do {
            let session = try await client.auth.signIn(email: email, password: temp)
            guard session.user.emailConfirmedAt != nil else {
                try? await client.auth.signOut()
                return
            }
            emailConfirmationLinkOpened = true
            persistSignupGate()
            isAuthenticated = false
            user = nil
        } catch {
            // Still waiting for the confirmation link.
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

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
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
            errorMessage = error.localizedDescription
            isAuthenticated = false
            user = nil
        }
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
                user = try await Self.fetchProfile(client: client)
                isAuthenticated = true
            } catch {
                isAuthenticated = false
                user = nil
            }
            return
        }
        await refreshMeLegacy()
    }

    private func refreshMeLegacy() async {
        do {
            user = try await legacyAuth.me()
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            user = nil
        }
    }

    func logout() {
        KeychainManager.shared.clearToken()
        isAuthenticated = false
        user = nil
        needsOnboarding = false
        clearSignupVerificationState()
        if usesSupabase, let client = SupabaseManager.shared.client() {
            Task { try? await client.auth.signOut() }
        }
    }
}
