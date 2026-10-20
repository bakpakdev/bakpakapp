import Foundation
import Supabase

enum PayoutMFAError: Error, LocalizedError {
    case unavailable
    case notEnrolled
    case cancelled
    case enrollFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Sign in again to manage two-factor."
        case .notEnrolled: return "Turn on two-factor with an authenticator app first."
        case .cancelled: return "Enter your authenticator code to continue."
        case .enrollFailed: return "Couldn’t start authenticator setup. Try again."
        }
    }
}

/// Authenticator-app (TOTP) two-factor through Supabase Auth MFA.
/// Payout-method changes and cash outs need a code entered within `freshWindow`;
/// the backend enforces the same rule in middleware/payoutMfa.js.
@MainActor
enum PayoutMFA {
    /// Keep in sync with PAYOUT_MFA_MAX_AGE_SECONDS on the backend.
    static let freshWindow: TimeInterval = 10 * 60

    struct Enrollment: Equatable {
        let factorId: String
        let secret: String
        let uri: String
    }

    private static func authedClient() async throws -> SupabaseClient {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else {
            throw PayoutMFAError.unavailable
        }
        return client
    }

    /// Reads factors from the server so a factor added on another device is seen.
    static func verifiedFactor() async throws -> Factor? {
        let user = try await authedClient().auth.user()
        return user.factors?.first { $0.factorType == "totp" && $0.status == .verified }
    }

    /// Server truth for "is two-factor on"; also refreshes the cached flag settings rows read.
    @discardableResult
    static func isEnrolled() async -> Bool {
        let enrolled = (try? await verifiedFactor()) != nil
        AccountPrefsStore.twoFactorEnabled = enrolled
        return enrolled
    }

    /// Password (or restored) session is AAL1 while a verified authenticator factor exists.
    static func needsLoginChallenge(factors: [Factor]? = nil) async -> Bool {
        let fromSession = factors?.contains { $0.factorType == "totp" && $0.status == .verified } == true
        let fromServer = (try? await verifiedFactor()) != nil
        guard fromSession || fromServer else { return false }
        let aal = try? await authedClient().auth.mfa.getAuthenticatorAssuranceLevel()
        return aal?.currentLevel != "aal2"
    }

    static func enroll() async throws -> Enrollment {
        let client = try await authedClient()
        // Drop half-finished setups so retries don't collide on the factor name.
        let user = try await client.auth.user()
        for factor in user.factors ?? [] where factor.factorType == "totp" && factor.status == .unverified {
            _ = try? await client.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
        }
        let response = try await client.auth.mfa.enroll(
            params: .totp(issuer: "popup", friendlyName: "Authenticator app")
        )
        guard let totp = response.totp else { throw PayoutMFAError.enrollFailed }
        return Enrollment(factorId: response.id, secret: totp.secret, uri: totp.uri)
    }

    /// Verifies a 6-digit code. Upgrades the session to AAL2 and stamps a fresh TOTP time.
    static func verify(factorId: String, code: String) async throws {
        let digits = String(code.filter(\.isNumber).prefix(6))
        guard digits.count == 6 else { throw PayoutMFAError.enrollFailed }
        try await authedClient().auth.mfa.challengeAndVerify(
            params: MFAChallengeAndVerifyParams(factorId: factorId, code: digits)
        )
        AccountPrefsStore.twoFactorEnabled = true
    }

    static func verifyPayoutCode(_ code: String) async throws {
        guard let factor = try await verifiedFactor() else { throw PayoutMFAError.notEnrolled }
        try await verify(factorId: factor.id, code: code)
    }

    /// Completes sign-in: same TOTP check as payouts, required whenever 2FA is on.
    static func verifyLoginCode(_ code: String) async throws {
        try await verifyPayoutCode(code)
    }

    /// Supabase only lets an AAL2 session remove a verified factor, so callers verify a code first.
    static func turnOff() async throws {
        let client = try await authedClient()
        if let factor = try await verifiedFactor() {
            _ = try await client.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
        }
        AccountPrefsStore.twoFactorEnabled = false
        _ = try? await client.auth.refreshSession()
    }

    /// True when this session is AAL2 and an authenticator code was entered within `freshWindow`.
    static func hasFreshCode() async -> Bool {
        guard let client = SupabaseManager.shared.client(),
              let session = try? await client.auth.session,
              let claims = decodeClaims(session.accessToken),
              claims["aal"] as? String == "aal2" else { return false }
        let stamps = (claims["amr"] as? [[String: Any]] ?? [])
            .filter { $0["method"] as? String == "totp" }
            .compactMap { ($0["timestamp"] as? NSNumber)?.doubleValue }
        guard let last = stamps.max() else { return false }
        return Date().timeIntervalSince1970 - last <= freshWindow
    }

    private static func decodeClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Presents the code sheet (attached in RootView) when a payout action needs a fresh code.
@MainActor
final class PayoutMFAGate: ObservableObject {
    static let shared = PayoutMFAGate()

    @Published var isPrompting = false
    @Published private(set) var reason = ""
    private var continuation: CheckedContinuation<Void, Error>?

    private init() {}

    /// Returns once the session has a fresh authenticator code; throws if not enrolled or cancelled.
    func requireCode(for reason: String) async throws {
        guard await PayoutMFA.isEnrolled() else { throw PayoutMFAError.notEnrolled }
        if await PayoutMFA.hasFreshCode() { return }
        guard continuation == nil else { throw PayoutMFAError.cancelled }
        self.reason = reason
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            isPrompting = true
        }
    }

    func verified() {
        finish(.success(()))
    }

    /// Called when the sheet goes away without a verified code (swipe down or cancel).
    func cancelIfPending() {
        finish(.failure(PayoutMFAError.cancelled))
    }

    private func finish(_ result: Result<Void, Error>) {
        isPrompting = false
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
