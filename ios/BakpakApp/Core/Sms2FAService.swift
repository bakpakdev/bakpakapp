import Foundation

enum Sms2FAService {
    struct Response: Decodable {
        let message: String?
        let phone: String?
        let previewCode: String?
    }

    @MainActor
    static func send(phone: String) async throws -> Response {
        let body = try JSONEncoder().encode(["phone": phone])
        do {
            return try await APIClient.shared.request(path: "/auth/sms-2fa/send", method: "POST", body: body)
        } catch {
            if let local = LocalSms2FA.issueIfUnreachable(phone: phone, error: error) {
                return local
            }
            throw error
        }
    }

    @MainActor
    static func verify(code: String) async throws -> Response {
        let body = try JSONEncoder().encode(["code": code])
        do {
            let response: Response = try await APIClient.shared.request(
                path: "/auth/sms-2fa/verify",
                method: "POST",
                body: body
            )
            LocalSms2FA.clear()
            return response
        } catch {
            if LocalSms2FA.verify(code) {
                return Response(message: "Verified.", phone: LocalSms2FA.phone, previewCode: nil)
            }
            throw error
        }
    }
}

/// Used when the Node API is down or Twilio isn’t configured in Debug.
enum LocalSms2FA {
    private static var codeKey: String { AccountScopedDefaults.key("popup.2fa.localCode") }
    private static var phoneKey: String { AccountScopedDefaults.key("popup.2fa.localPhone") }
    private static var expiresKey: String { AccountScopedDefaults.key("popup.2fa.localExpires") }

    static var phone: String? {
        UserDefaults.standard.string(forKey: phoneKey)
    }

    @discardableResult
    static func issueIfUnreachable(phone: String, error: Error) -> Sms2FAService.Response? {
        #if DEBUG
        guard isUnreachable(error) else { return nil }
        let code = String(Int.random(in: 100_000...999_999))
        UserDefaults.standard.set(code, forKey: codeKey)
        UserDefaults.standard.set(phone, forKey: phoneKey)
        UserDefaults.standard.set(Date().addingTimeInterval(10 * 60).timeIntervalSince1970, forKey: expiresKey)
        return Sms2FAService.Response(
            message: "Code generated.",
            phone: phone,
            previewCode: code
        )
        #else
        return nil
        #endif
    }

    static func verify(_ code: String) -> Bool {
        let stored = UserDefaults.standard.string(forKey: codeKey) ?? ""
        let expires = UserDefaults.standard.double(forKey: expiresKey)
        guard !stored.isEmpty, Date().timeIntervalSince1970 < expires, stored == code else {
            return false
        }
        clear()
        return true
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: codeKey)
        UserDefaults.standard.removeObject(forKey: expiresKey)
    }

    private static func isUnreachable(_ error: Error) -> Bool {
        if let api = error as? APIError {
            switch api {
            case .network, .badURL:
                return true
            case .server(let message):
                let lower = message.lowercased()
                return lower.contains("not configured")
                    || lower.contains("couldn’t connect")
                    || lower.contains("could not connect")
                    || lower.contains("connection refused")
            default:
                return false
            }
        }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }
}
