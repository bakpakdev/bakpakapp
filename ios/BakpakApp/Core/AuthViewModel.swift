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
    /// Mid-signup: waiting for the student to click the verification link in email.
    @Published var isAwaitingEmailVerification = false
    /// Mid-signup: verification link was opened / email confirmed.
    @Published var hasVerifiedSignupEmail = false
    /// First-time signup only — profile setup before home.
    @Published var needsOnboarding = false
    /// Legacy Express API base URL (used only when Supabase is not configured).
    @Published var baseURL = "http://127.0.0.1:5001/api"

    private let legacyAuth = AuthService()
    private static let baseURLDefaultsKey = "popup.apiBaseURL"
    private static let onboardingRequiredPrefix = "popup.onboarding.required."
    /// Temporary password used only until the student sets their real password.
    private var pendingTempPassword: String?
    private var pendingSignupEmail: String?

    var usesSupabase: Bool { SupabaseConfig.isConfigured }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = saved
        }
        APIClient.shared.setBaseURL(baseURL)

        if usesSupabase {
            Task { @MainActor in await restoreSupabaseSession() }
        } else if KeychainManager.shared.readToken() != nil {
            isAuthenticated = true
            Task { @MainActor in await refreshMeLegacy() }
        }
    }

    func applyServerURL() {
        APIClient.shared.setBaseURL(baseURL)
        UserDefaults.standard.set(baseURL, forKey: Self.baseURLDefaultsKey)
    }

    // MARK: - Supabase

    private func restoreSupabaseSession() async {
        guard let client = SupabaseManager.shared.client() else { return }
        do {
            _ = try await client.auth.session
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
                try await client.auth.signIn(email: email, password: password)
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
        isAwaitingEmailVerification = true
        hasVerifiedSignupEmail = false
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
                isAwaitingEmailVerification = true
                hasVerifiedSignupEmail = false
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
                // Confirm email is OFF in the Supabase project — no confirmation email is sent.
                errorMessage =
                    "Supabase has “Confirm email” turned off, so no email was sent. Turn it ON under Authentication → Providers → Email, then tap Resend."
                hasVerifiedSignupEmail = false
                isAwaitingEmailVerification = true
                isAuthenticated = false
                user = nil
                return false
            }

            // No session means confirmation is required — Supabase should have queued the email.
            isAwaitingEmailVerification = true
            hasVerifiedSignupEmail = false
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
                    isAwaitingEmailVerification = true
                    hasVerifiedSignupEmail = false
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
    func handleAuthRedirect(_ url: URL) async {
        guard usesSupabase, let client = SupabaseManager.shared.client() else { return }

        do {
            _ = try await client.auth.session(from: url)
            if isAwaitingEmailVerification {
                hasVerifiedSignupEmail = true
                isAuthenticated = false
                user = nil
            } else {
                user = try await Self.fetchProfileWithRetry(client: client)
                isAuthenticated = true
                KeychainManager.shared.clearToken()
            }
        } catch {
            if isAwaitingEmailVerification {
                // Link opened the app — treat as verified even if token parse fails.
                hasVerifiedSignupEmail = true
                isAuthenticated = false
                user = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Unlocks the password step once the email is confirmed (e.g. link opened outside the app).
    func checkSignupEmailVerification() async {
        guard isAwaitingEmailVerification, !hasVerifiedSignupEmail else { return }
        guard usesSupabase, let client = SupabaseManager.shared.client() else { return }
        guard let email = pendingSignupEmail, let temp = pendingTempPassword else { return }

        do {
            try await client.auth.signIn(email: email, password: temp)
            hasVerifiedSignupEmail = true
            isAuthenticated = false
            user = nil
        } catch {
            // Still waiting for the confirmation link.
        }
    }

    func clearSignupVerificationState() {
        isAwaitingEmailVerification = false
        hasVerifiedSignupEmail = false
        pendingTempPassword = nil
        pendingSignupEmail = nil
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

                if signupResult.session == nil {
                    do {
                        try await client.auth.signIn(email: trimmedEmail, password: password)
                    } catch {
                        errorMessage =
                            "We created your account, but you’re not signed in yet. In Supabase: Authentication → Providers → Email → turn off “Confirm email” for development, or open the confirmation link in your email. Details: \(error.localizedDescription)"
                        isAuthenticated = false
                        user = nil
                        return
                    }
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
        if usesSupabase, let client = SupabaseManager.shared.client() {
            Task {
                try? await client.auth.signOut()
            }
        }
        KeychainManager.shared.clearToken()
        isAuthenticated = false
        user = nil
        needsOnboarding = false
        clearSignupVerificationState()
        AccountScopedDefaults.bind(userId: nil)
    }
}
