import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case unauthorized
    case decoding(Error)
    case server(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL."
        case .unauthorized: return "Unauthorized. Please log in again."
        case .decoding(let error): return "Response parse error: \(error.localizedDescription)"
        case .server(let message): return message
        case .network(let error): return error.localizedDescription
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()
    private init() {}

    var baseURL: String = SquareConfig.apiBaseURL

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    func resolveAuthToken() async -> String? {
        if SupabaseConfig.isConfigured, let client = SupabaseManager.shared.client() {
            if let session = try? await client.auth.session {
                return session.accessToken
            }
        }
        return KeychainManager.shared.readToken()
    }

    func setBaseURL(_ url: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while u.hasSuffix("/") { u.removeLast() }
        self.baseURL = u
    }

    private func dataTrimmingUTF8BOM(_ data: Data) -> Data {
        guard data.count >= 3,
              data[data.startIndex] == 0xEF,
              data[data.index(data.startIndex, offsetBy: 1)] == 0xBB,
              data[data.index(data.startIndex, offsetBy: 2)] == 0xBF else { return data }
        return Data(data.dropFirst(3))
    }

    /// Best-effort message from error JSON (`message`, `error`, express-validator `errors[].msg`) or short plain text.
    private func serverMessage(from data: Data) -> String? {
        let trimmed = dataTrimmingUTF8BOM(data)
        if trimmed.isEmpty { return nil }

        if let m = try? decoder.decode(APIMessage.self, from: trimmed), let msg = m.message, !msg.isEmpty {
            return msg
        }
        struct ValidationEnvelope: Decodable {
            let errors: [ValidationItem]?
        }
        struct ValidationItem: Decodable {
            let msg: String?
        }
        if let env = try? decoder.decode(ValidationEnvelope.self, from: trimmed) {
            let parts = env.errors?.compactMap(\.msg).filter { !$0.isEmpty } ?? []
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: trimmed) as? [String: Any] else {
            if let s = String(data: trimmed, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty, s.count < 600 {
                if s.hasPrefix("<") { return "The server returned an HTML error page (often a proxy, VPN, or wrong URL)." }
                return s
            }
            return nil
        }
        if let m = obj["message"] as? String, !m.isEmpty { return m }
        if let e = obj["error"] as? String, !e.isEmpty { return e }
        if let errs = obj["errors"] as? [[String: Any]] {
            let msgs = errs.compactMap { $0["msg"] as? String }.filter { !$0.isEmpty }
            if !msgs.isEmpty { return msgs.joined(separator: " ") }
        }
        return nil
    }

    private func friendlyStatusMessage(statusCode: Int) -> String {
        switch statusCode {
        case 403:
            return "Access denied (403). The server refused this request—often wrong account for that resource, or a firewall/proxy blocking your API URL. Confirm the API base URL ends with /api and try logging out and back in."
        case 404:
            return "Not found (404). Check the API base URL and path."
        case 502, 503:
            return "Server unavailable (\(statusCode)). The API may be down or restarting."
        default:
            return "Request failed with status \(statusCode)."
        }
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        let joined = baseURL + path
        guard let url = URL(string: joined) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token = await resolveAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.server("Invalid response from server.")
            }

            if http.statusCode == 401 {
                if let msg = serverMessage(from: data) {
                    throw APIError.server(msg)
                }
                throw APIError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                if let msg = serverMessage(from: data) {
                    throw APIError.server(msg)
                }
                throw APIError.server(friendlyStatusMessage(statusCode: http.statusCode))
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.network(error)
        }
    }

    func requestVoid(path: String, method: String = "DELETE") async throws {
        let _: APIMessage = try await request(path: path, method: method)
    }
}
