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

    var baseURL: String = "http://localhost:5000/api"

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private var authToken: String? {
        KeychainManager.shared.readToken()
    }

    func setBaseURL(_ url: String) {
        self.baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.server("Invalid response from server.")
            }

            if http.statusCode == 401 { throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) {
                if let apiMessage = try? decoder.decode(APIMessage.self, from: data),
                   let message = apiMessage.message {
                    throw APIError.server(message)
                }
                throw APIError.server("Request failed with status \(http.statusCode).")
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
