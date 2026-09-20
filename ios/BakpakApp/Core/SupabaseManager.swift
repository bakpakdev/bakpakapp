import Foundation
import Supabase

/// Shared Supabase client when URL + anon key are configured at build time.
final class SupabaseManager {
    static let shared = SupabaseManager()

    private var cached: SupabaseClient?
    private let lock = NSLock()

    private init() {}

    /// Returns a client if `SupabaseConfig.isConfigured`; otherwise `nil`.
    func client() -> SupabaseClient? {
        guard SupabaseConfig.isConfigured,
              let url = URL(string: SupabaseConfig.urlString) else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if cached == nil {
            cached = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
        }
        return cached
    }

    /// Client only if the user has a valid (or refreshable) Supabase Auth session.
    func clientWithValidSession() async -> SupabaseClient? {
        guard let c = client() else { return nil }
        do {
            _ = try await c.auth.session
            return c
        } catch {
            return nil
        }
    }
}
