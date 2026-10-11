import Foundation
import Supabase

enum ReportServiceError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidTarget
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Reporting isn’t available right now."
        case .notSignedIn: return "Sign in to submit a report."
        case .invalidTarget: return "Couldn’t find who to report."
        case .failed: return "Couldn’t send your report. Try again."
        }
    }
}

enum ReportService {
    private static func client() async throws -> SupabaseClient {
        guard SupabaseConfig.isConfigured else { throw ReportServiceError.notConfigured }
        guard let c = await SupabaseManager.shared.clientWithValidSession() else {
            throw ReportServiceError.notSignedIn
        }
        return c
    }

    private static func uuidOrNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func submitUserReport(
        reportedUserId: String,
        reason: String,
        details: String?,
        conversationId: String? = nil,
        productId: String? = nil
    ) async throws {
        let reported = uuidOrNil(reportedUserId)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reported, !trimmedReason.isEmpty else {
            throw ReportServiceError.invalidTarget
        }

        let c = try await client()
        let me = try await c.auth.session.user.id.uuidString.lowercased()
        guard me != reported else { throw ReportServiceError.invalidTarget }

        let trimmedDetails = details?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detailsValue: String? = {
            guard let trimmedDetails, !trimmedDetails.isEmpty else { return nil }
            return String(trimmedDetails.prefix(1200))
        }()

        struct Ins: Encodable {
            let reporter_id: String
            let reported_id: String
            let conversation_id: String?
            let product_id: String?
            let reason: String
            let details: String?
        }

        do {
            _ = try await c.from("user_reports")
                .insert(
                    Ins(
                        reporter_id: me,
                        reported_id: reported,
                        conversation_id: uuidOrNil(conversationId),
                        product_id: uuidOrNil(productId),
                        reason: String(trimmedReason.prefix(80)),
                        details: detailsValue
                    )
                )
                .execute()
        } catch {
            throw ReportServiceError.failed
        }
    }
}
