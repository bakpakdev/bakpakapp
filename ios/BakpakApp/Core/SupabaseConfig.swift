import Foundation

/// Reads Supabase credentials from the app bundle (Info.plist).
///
/// **Setup**
/// 1. In Xcode: add the Swift package `https://github.com/supabase/supabase-swift.git` (product **Supabase**).
/// 2. Target → Build Settings → **User-Defined** (or an `.xcconfig` file):
///    - `SUPABASE_URL` = `https://YOUR_PROJECT_REF.supabase.co`
///    - `SUPABASE_ANON_KEY` = your **anon** key (Dashboard → Project Settings → API).
/// 3. Info.plist already maps those keys via `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)`.
///
/// Use only the **anon** key in the app. Never ship the **service_role** key in iOS.
enum SupabaseConfig {
    private static let urlKey = "SUPABASE_URL"
    private static let anonKeyKey = "SUPABASE_ANON_KEY"
    private static let authRedirectKey = "SUPABASE_AUTH_REDIRECT_URL"

    static var urlString: String {
        (Bundle.main.object(forInfoDictionaryKey: urlKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var anonKey: String {
        (Bundle.main.object(forInfoDictionaryKey: anonKeyKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true` when URL and anon key look valid (substituted from build settings, not left as `$(...)`).
    static var isConfigured: Bool {
        let u = urlString
        let k = anonKey
        guard !k.isEmpty, !u.isEmpty else { return false }
        guard let parsed = URL(string: u),
              let host = parsed.host,
              !host.isEmpty,
              parsed.scheme == "https" else { return false }
        if u.contains("$(") || k.contains("$(") { return false }
        guard looksLikeJWT(k) else { return false }
        return true
    }

    /// Supabase anon key should be a JWT-like value: header.payload.signature
    private static func looksLikeJWT(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { !$0.isEmpty }
    }

    /// Where Supabase sends the user after they tap the email confirmation link.
    /// Defaults to the app deep link so the email opens popup directly.
    /// Must be allowlisted in Supabase → Authentication → URL Configuration → Redirect URLs.
    static var authRedirectURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: authRedirectKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, !raw.contains("$("), let url = URL(string: raw) {
            return url
        }
        return appAuthCallbackURL
    }

    /// Native deep link used to return into the iOS app.
    static var appAuthCallbackURL: URL {
        URL(string: "popup://auth-callback")!
    }
}
